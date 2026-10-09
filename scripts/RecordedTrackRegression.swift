import Foundation
import CoreGraphics
import ImageIO
import CQBCore

/// Diagnostic harness only; not an app import/migration or a production V13 adapter.
@main struct RecordedTrackRegression {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "RecordedTrackRegression", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func point(_ p: MapPoint) -> ImagePoint { .init(x: p.x, y: p.y) }
    static func assertPreserved(_ chosen: MapMatchCandidate, _ result: TrackResultDocument, offset: Double) throws {
        try require(result.vertices.count == chosen.vertices.count, "Vertex count changed")
        for (before, after) in zip(chosen.vertices, result.vertices) {
            try require(before.point.x == after.point.x && before.point.y == after.point.y,
                "Result geometry changed during contract round trip")
            try require(before.part == after.part && before.sampleIndex == after.sampleIndex && before.time + offset == after.t,
                "Part/index/time changed during contract round trip")
        }
    }
    static func write(_ value: Any, name: String, output: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(name), options: .atomic)
    }
    static func main() throws {
        setbuf(stdout, nil)
        let args = CommandLine.arguments
        try require(args.count == 5, "Expected experiment, map directory, output directory, PoC source directory")
        let experiment = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let record = try RecordingStore.decode(experiment)
        let folder = URL(fileURLWithPath: args[2]), output = URL(fileURLWithPath: args[3])
        func data(_ name: String) throws -> Data { try Data(contentsOf: folder.appendingPathComponent(name)) }
        guard let binding = record.navigationBinding, let saved = record.mapMatching, let chosen = saved.chosen,
              let start = record.setup.start, let toward = record.setup.directionPoint,
              let scale = record.setup.scale, let camera = record.cameraDirectionRadians,
              let a = record.setup.a, let b = record.setup.b, let meters = Double(record.setup.meters),
              let planID = UUID(uuidString: binding.planID), let revisionID = UUID(uuidString: binding.revisionID) else {
            throw NSError(domain: "Missing experiment inputs", code: 1)
        }
        let nav = try JSONDecoder().decode(NavigationMapExportMetadata.self, from: data("navigation-map.json"))
        var plan = try JSONDecoder().decode(FloorPlan.self, from: data("floorplan.json"))
        let maskBytes = try data("resolved-mask.bin"), imageBytes = try data("original.png")
        let source = CGImageSourceCreateWithData(imageBytes as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let nonopaque = stride(from: 3, to: rgba.count, by: 4).filter { rgba[$0] != 255 }.count
        let mask = ResolvedGridMask(columns: nav.columns, rows: nav.rows,
            cellSize: nav.cellSizePixels, blocked: [UInt8](maskBytes))
        let fingerprint = NavigationMapIdentity.fingerprint(mask: mask,
            imageFingerprint: binding.imageFingerprint, pixelsPerMeter: scale)
        try require(nav.planID == binding.planID && nav.revisionID == binding.revisionID &&
            plan.id == planID && plan.revisionID == nav.revisionID &&
            nav.navigationFingerprint == binding.navigationFingerprint && fingerprint == binding.navigationFingerprint &&
            saved.mapHash == fingerprint && FloorPlanWallDetector.fingerprint(image) == binding.imageFingerprint &&
            nav.imageFingerprint == binding.imageFingerprint && nav.pixelsPerMeter == saved.pixelsPerMeter &&
            abs(nav.pixelsPerMeter - scale) < 1e-9 && record.imageSize == [Double(image.width), Double(image.height)] &&
            maskBytes.count == nav.columns * nav.rows, "Exact revision/image/grid/scale mismatch")
        plan.navigationDraft?.baseBlocked = try data("base-mask.bin")
        try require(plan.navigationDraft != nil && NavigationMaskBuilder.resolve(plan.navigationDraft!) == mask,
            "Saved edits do not reproduce the supplied resolved mask")
        let grid = NavigationMapIdentity.grid(mask)
        let savedGeometry = NavigationMapIdentity.validates(saved, mask: mask, fingerprint: fingerprint)
        let experimentHash = FloorPlanJSON.sha256(experiment)
        var report: [String: Any] = [
            "experimentSHA256": experimentHash, "exactMapVerified": true, "editsReproduceMask": true,
            "planID": binding.planID, "revisionID": binding.revisionID, "navigationFingerprint": fingerprint,
            "imagePixels": [image.width, image.height], "pixelsPerMeter": scale,
            "rawSamples": record.samples.count, "durationSeconds": record.samples.last!.time,
            "selectedCandidate": saved.selected, "selectedVertices": chosen.vertices.count,
            "savedGeometryValidUnderPoCRules": savedGeometry,
            "savedDirectionMode": record.setup.directionMode!.rawValue,
            "savedRotationDegrees": record.setup.rotationDegrees,
            "imageDiagnostics": ["bitsPerComponent": image.bitsPerComponent,
                "colorSpace": image.colorSpace?.name as String? ?? "unknown", "nonopaquePixels": nonopaque],
            "cameraRotationDegrees": RouteHeading.rotation(start: start, toward: toward, referenceRadians: camera)!,
            "productionDirectionPolicyConforms": record.setup.directionMode == .cameraAtStart,
            "legacyHeadingAmbiguous": saved.initialHeadingSearch?.ambiguous as Any? ?? NSNull(),
            "limitations": ["No ground-truth physical route", "Not a device performance measurement",
                "Legacy firstWalk is retained for replay; no automatic cameraAtStart migration",
                "Session/member/recording/result IDs and 0.4s offset below are synthetic harness context",
                "manuallyReviewed and rasterizationVersion are harness assumptions, not facts exported by PoC",
                "Only explicit heading ambiguity is mapped here; codec probe does not certify all legacy diagnostics"]
        ]
        var fileHashes: [String: String] = [:]
        for name in ["original.png", "floorplan.json", "navigation-map.json", "base-mask.bin", "resolved-mask.bin"] {
            fileHashes[name] = FloorPlanJSON.sha256(try data(name))
        }
        var sourceHashes: [String: String] = [:]
        for name in ["AnchoredRouteCorrector", "MapMatching", "NonrigidRouteMatcher", "InitialHeadingMatcher", "RouteHeading",
                     "RecordingStore", "TestBuild", "FloorPlanWallDetector", "NavigationMapIdentity", "Models", "Geometry",
                     "NavigationMask", "WallMapAnalyzer", "GuidedWallRecognizer"] {
            sourceHashes[name] = FloorPlanJSON.sha256(try Data(contentsOf:
                URL(fileURLWithPath: args[4]).appendingPathComponent(name + ".swift")))
        }
        report["inputFileHashes"] = fileHashes; report["pocSourceHashes"] = sourceHashes

        // First test the representation boundary. Never replace legacy direction
        // with a fabricated camera heading to make its raw projection match.
        do {
            let manifest = FloorPlanManifest(schemaVersion: 1, floorPlanID: planID, revisionID: revisionID,
                coordinateSystem: "image-top-left-row-major", imageWidth: image.width, imageHeight: image.height,
                imageSHA256: FloorPlanJSON.sha256(imageBytes),
                scale: MapScale(a: point(a), b: point(b), meters: meters),
                indoorOutline: nav.indoorOutline!.map { NormalizedPoint(x: $0.x, y: $0.y) },
                navigationGrid: NavigationGridDescriptor(columns: nav.columns, rows: nav.rows, cellSizePixels: nav.cellSizePixels,
                    encoding: "uint8-row-major", freeValue: 0, blockedValue: 1, outsideIsBlocked: true,
                    maskSHA256: FloorPlanJSON.sha256(maskBytes)), extractionAlgorithmVersion: nav.analysisVersion!,
                rasterizationVersion: 1, manuallyReviewed: true)
            let manifestBytes = try FloorPlanJSON.encodeManifest(manifest)
            let reference = FloorPlanReference(floorPlanID: planID, revisionID: revisionID,
                navigationSHA256: FloorPlanJSON.sha256(manifestBytes))
            try manifestBytes.write(to: output.appendingPathComponent("derived-navigation-map.json"))
            let identity = TrackIdentity(sessionID: UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1")!,
                memberID: UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2")!,
                recordingID: UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3")!)
            let offset = 0.4
            let raw = RawTrackDocument(identity: identity, floorPlan: reference,
                originMeters: .init(x: Double(record.origin[0]), y: Double(record.origin[1]), z: Double(record.origin[2])),
                startPose: .init(positionNormalized: .init(x: start.x / Double(image.width), y: start.y / Double(image.height)),
                    directionPointNormalized: .init(x: toward.x / Double(image.width), y: toward.y / Double(image.height)),
                    cameraDirectionRadians: camera), recordingStartOffsetSeconds: offset,
                samples: try record.samples.map { s in
                    guard let state = TrackTrackingState(rawValue: s.state) else { throw TrackValidationError.invalidRaw }
                    return TrackRawSample(time: s.time, arTimestamp: s.arTimestamp, arPosition: s.arPosition.map(Double.init),
                        relativeMeters: s.relativeMeters.map { .init(x: $0.x, y: $0.y) }, trackingState: state, segment: s.segment)
                })
            let rawBytes = try TrackDocumentJSON.encode(raw)
            try rawBytes.write(to: output.appendingPathComponent("derived-raw.json"))
            try require(chosen.unresolved.isEmpty && !saved.searchIncomplete &&
                record.samples.allSatisfy { $0.relativeMeters != nil } && Set(chosen.vertices.map(\.part)).count == 1,
                "Harness currently supports this complete, uninterrupted experiment only")
            let timeline = try TrackTimeline.sessionTimeline(from: chosen.vertices.map {
                RecordingRouteVertex(point: point($0.point), time: $0.time, sampleIndex: $0.sampleIndex, part: $0.part)
            }, recordingStartOffset: offset)
            let result = TrackResultDocument(identity: identity,
                resultID: UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee4")!, floorPlan: reference,
                sourceRawSHA256: FloorPlanJSON.sha256(rawBytes),
                algorithm: .init(name: saved.algorithm, version: "unspecified-in-export",
                    settingsID: "legacy-experiment-sha256:" + experimentHash), status: .done,
                vertices: timeline.vertices.map { .init(t: $0.sessionTime, point: $0.point, part: $0.part,
                    sampleIndex: $0.sampleIndex, provenance: .unspecified) }, unresolvedIntervals: [],
                searchIncomplete: saved.searchIncomplete,
                warnings: saved.initialHeadingSearch?.ambiguous == true ? [.headingAmbiguous] : [])
            let resultBytes = try TrackDocumentJSON.encode(result)
            try resultBytes.write(to: output.appendingPathComponent("derived-result.json"))
            let decoded = try JSONDecoder().decode(TrackResultDocument.self, from: resultBytes)
            let differences = zip(chosen.vertices, decoded.vertices).map { a, b in
                hypot(a.point.x - b.point.x, a.point.y - b.point.y)
            }
            try assertPreserved(chosen, decoded, offset: offset)
            try require(decoded.warnings == result.warnings &&
                decoded.warnings.contains(.headingAmbiguous) == (saved.initialHeadingSearch?.ambiguous == true),
                "Explicit heading ambiguity was lost during contract round trip")
            report["headingWarningPreserved"] = true
            report["mappedWarnings"] = decoded.warnings.map(\.rawValue)
            var rejectedMutations = 0
            for mutation in 0..<3 {
                var changed = decoded
                if mutation == 0 {
                    changed.vertices[0].point = .init(x: changed.vertices[0].point.x * scale, y: changed.vertices[0].point.y)
                } else if mutation == 1 { changed.vertices[0].t += offset }
                else { changed.vertices[0].part += 1 }
                do { try assertPreserved(chosen, changed, offset: offset) }
                catch { rejectedMutations += 1 }
            }
            try require(rejectedMutations == 3, "Regression guard failed to detect scale/time/part mutation")
            report["rejectedTransferMutations"] = rejectedMutations
            report["resultCodecRoundTrip"] = "passed (not full validation)"
            report["transferMaximumDisplacementPixels"] = differences.max()!
            report["transferTimeAndPartsPreserved"] = true
            report["commonFloorPlanValidation"] = "not completed"
            let map = try FloorPlanValidator(imageValidator: PNGFloorPlanImageValidator()).validate(
                files: .init(imagePNG: imageBytes, navigationMapJSON: manifestBytes, resolvedMask: maskBytes), reference: reference)
            report["commonFloorPlanValidation"] = "passed"
            let rawChecked = try TrackDocumentValidator.raw(rawBytes, floorPlan: map)
            report["commonRawValidation"] = "passed"
            _ = try TrackDocumentValidator.result(resultBytes, raw: rawChecked, floorPlan: map)
            report["commonResultValidation"] = "passed"
        } catch {
            report["contractProbeFailure"] = String(describing: error)
            print("Contract compatibility probe: \(error). Inputs and validators are unchanged.")
        }

        print("Exact map verified. Replaying unchanged PoC core twice with saved settings...")
        try require(record.matchEngine == .contextAware && saved.deformationLevel == .standard,
            "Unsupported engine/settings; do not silently run a different algorithm")
        let inputs = record.samples.map { MatchInput(meters: $0.relativeMeters, time: $0.time, segment: $0.segment) }
        var runs: [[String: Any]] = []
        var replayPassed = true
        for run in 1...2 {
            guard let replay = InitialHeadingMatcher.match(input: inputs, anchor: start, pixelsPerMeter: scale,
                rotationDegrees: record.setup.rotationDegrees, map: MatchNavigationMap(grid: grid), mapHash: fingerprint,
                recordingID: saved.sourceRecordingID, level: .standard, budgetSeconds: 20,
                preserveExcursions: true, improvedExcursions: true) else {
                replayPassed = false
                runs.append(["run": run, "error": "no result"]); continue
            }
            var comparisons: [[String: Any]] = []
            for (index, candidate) in replay.candidates.enumerated() {
                guard candidate.samplePoints.count == chosen.samplePoints.count else { continue }
                let pairs = zip(chosen.samplePoints, candidate.samplePoints)
                guard pairs.allSatisfy({ ($0 == nil) == ($1 == nil) }) else { continue }
                let distances = pairs.compactMap { a, b -> Double? in
                    guard let a, let b else { return nil }; return hypot(a.x - b.x, a.y - b.y)
                }
                var verticesEqual = candidate.vertices.count == chosen.vertices.count
                for (lhs, rhs) in zip(candidate.vertices, chosen.vertices) {
                    if lhs.point.x != rhs.point.x || lhs.point.y != rhs.point.y || lhs.time != rhs.time ||
                        lhs.part != rhs.part || lhs.sampleIndex != rhs.sampleIndex { verticesEqual = false }
                }
                comparisons.append(["candidateIndex": index, "sampleMaximumDisplacementPixels": distances.max() ?? 0,
                    "sampleMeanDisplacementPixels": distances.reduce(0, +) / Double(max(1, distances.count)),
                    "verticesExactlyEqual": verticesEqual])
            }
            runs.append(["run": run, "elapsedSeconds": replay.elapsedSeconds, "selectedIndex": replay.selected,
                "candidateCount": replay.candidates.count, "searchIncomplete": replay.searchIncomplete,
                "geometryValidUnderPoCRules": NavigationMapIdentity.validates(replay, mask: mask, fingerprint: fingerprint),
                "comparisonToSavedSelected": comparisons])
            let selectedComparison = comparisons.first { $0["candidateIndex"] as? Int == replay.selected }
            replayPassed = replayPassed && selectedComparison?["verticesExactlyEqual"] as? Bool == true &&
                selectedComparison?["sampleMaximumDisplacementPixels"] as? Double == 0
            print("Replay \(run) completed: \(replay.candidates.count) candidates, \(replay.elapsedSeconds)s")
        }
        report["replays"] = runs
        report["savedSelectedReplayPassed"] = replayPassed
        try write(report, name: "report.json", output: output)
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        // Full-contract rejection is a diagnostic finding, not silently waived.
        // Exit 0 means replay + transfer preserved; inspect contractProbeFailure.
        try require(replayPassed && report["transferTimeAndPartsPreserved"] as? Bool == true &&
            report["headingWarningPreserved"] as? Bool == true,
            "Regression: saved selected result or contract codec transfer changed; inspect report.json")
    }
}
