import Foundation
import CQBCore

nonisolated struct RouteCorrectionOutput: Sendable {
    let document: TrackResultDocument
    let diagnostics: MapMatchResult?
}

/// V13 contextAware 결과를 공통 업로드 계약으로 변환한다. 원본 파일은 수정하지 않는다.
nonisolated enum RouteCorrectionService {
    static func correct(raw: RawTrackDocument, rawHash: String, map: TrainingMap) -> RouteCorrectionOutput {
        let input = raw.samples.map { MatchInput(meters: $0.relative, time: $0.t, segment: $0.segment) }
        let match = InitialHeadingMatcher.match(input: input, anchor: raw.start,
            pixelsPerMeter: raw.pixelsPerMeter, rotationDegrees: raw.rotationDegrees,
            map: map.navigation, mapHash: raw.floorPlan.navigationSHA256,
            recordingID: raw.identity.recordingID.uuidString, level: .standard,
            preserveExcursions: true, improvedExcursions: true)
        return convert(raw: raw, rawHash: rawHash, match: match)
    }

    static func convert(raw: RawTrackDocument, rawHash: String, match: MapMatchResult?) -> RouteCorrectionOutput {
        var distance = 0.0
        for i in raw.samples.indices.dropFirst() {
            if raw.samples[i].segment == raw.samples[i - 1].segment,
               let a = raw.samples[i - 1].relative, let b = raw.samples[i].relative {
                distance += hypot(b.x - a.x, b.y - a.y)
            }
        }
        let failure: TrackUnresolvedReason = distance <= 0.01 ? .insufficientMovement : .noCandidate
        let chosen = match?.chosen
        let source = chosen?.vertices ?? []
        let vertices = source.map {
            TrackResultVertex(t: $0.time, point: ImagePoint(x: $0.point.x, y: $0.point.y),
                part: $0.part, sampleIndex: $0.sampleIndex, provenance: .correctedSample)
        }
        var coverage: [TrackSampleCoverage] = []
        var covered = Set<Int>()
        // 하나의 part 내부 정점 사이만 원본 샘플을 대표한다. 단절을 건너 연결하지 않는다.
        for (index, vertex) in source.enumerated() {
            if index > 0, source[index - 1].part == vertex.part {
                let previous = source[index - 1]
                let lower = previous.sampleIndex + 1
                if lower <= vertex.sampleIndex {
                    coverage.append(TrackSampleCoverage(samples: .init(from: lower, through: vertex.sampleIndex),
                        vertices: .init(from: index - 1, through: index)))
                    covered.formUnion(lower...vertex.sampleIndex)
                }
            } else {
                coverage.append(TrackSampleCoverage(samples: .init(from: vertex.sampleIndex, through: vertex.sampleIndex),
                    vertices: .init(from: index, through: index)))
                covered.insert(vertex.sampleIndex)
            }
        }
        var intervals: [TrackUnresolvedInterval] = []
        func add(_ from: Int, _ through: Int, _ reason: TrackUnresolvedReason,
                 _ description: String, bounds: TrackIntervalBounds = .closed) {
            guard raw.samples.indices.contains(from), raw.samples.indices.contains(through), from <= through else { return }
            intervals.append(.init(from: raw.samples[from].t, to: raw.samples[through].t,
                bounds: bounds, reason: reason, samples: .init(from: from, through: through), sourceReason: description))
        }
        var index = 0
        while index < raw.samples.count {
            if covered.contains(index) { index += 1; continue }
            let first = index
            let lost = raw.samples[index].relative == nil
            while index + 1 < raw.samples.count, !covered.contains(index + 1),
                  (raw.samples[index + 1].relative == nil) == lost { index += 1 }
            coverage.append(.init(samples: .init(from: first, through: index), vertices: nil))
            add(first, index, lost ? .trackingLost : (chosen == nil ? failure : .connectionUnverified),
                lost ? "AR 추적을 사용할 수 없는 원본 샘플" : "보정 경로가 없는 원본 샘플")
            index += 1
        }
        // 정점 양끝이 유효해도 그 사이 추적 단절은 유효 경로로 해석하지 않는다.
        for i in raw.samples.indices.dropFirst() where raw.samples[i].relative != nil {
            if raw.samples[i - 1].relative == nil || raw.samples[i].segment != raw.samples[i - 1].segment {
                var previous = i - 1
                while previous > 0, raw.samples[previous].relative == nil { previous -= 1 }
                add(previous, i, .trackingLost, "추적 단절 후 재개: 두 위치 사이 경로를 추정하지 않음", bounds: .open)
            }
        }
        for range in chosen?.unresolved ?? [] {
            add(range.from, range.through, range.reason.contains("한도") ? .searchLimit : .connectionUnverified, range.reason)
        }
        let incomplete = (match?.searchIncomplete ?? false) || (chosen?.searchLimited ?? false)
        var warnings: [TrackResultWarning] = []
        if raw.samples.contains(where: { $0.relative == nil }) || intervals.contains(where: { $0.reason == .trackingLost }) {
            warnings.append(.trackingLost)
        }
        if intervals.contains(where: { $0.reason == .connectionUnverified }) { warnings.append(.connectionUnverified) }
        if incomplete { warnings.append(.searchIncomplete) }
        if match?.initialHeadingSearch?.ambiguous == true { warnings.append(.headingAmbiguous) }
        let failed = vertices.isEmpty
        let document = TrackResultDocument(identity: raw.identity, floorPlan: raw.floorPlan,
            sourceRawSHA256: rawHash,
            algorithm: .init(name: "contextAware", version: "V13", settingsID: "standard-heading60-excursions-23.11pxpm"),
            status: failed ? .failed : (intervals.isEmpty && warnings.isEmpty ? .done : .partial),
            vertices: vertices, sampleCoverage: coverage.sorted { $0.samples.from < $1.samples.from },
            unresolvedIntervals: intervals.sorted { $0.from < $1.from }, searchIncomplete: incomplete,
            warnings: warnings, failureReason: failed ? failure : nil)
        return RouteCorrectionOutput(document: document, diagnostics: match)
    }
}
