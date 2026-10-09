import Foundation
import Testing
import CQBCore
import CQBFixtures
import CQBImageIO

// Fixture DTOs stay private: review JSON is not a production raw/result schema.
private struct RawExample: Decodable {
    struct Origin: Decodable { let x: Double; let z: Double }
    struct Meters: Decodable { let x: Double; let y: Double }
    struct Pose: Decodable {
        let positionNormalized: NormalizedPoint
        let directionPointNormalized: NormalizedPoint
        let cameraDirectionRadians: Double
    }
    struct Sample: Decodable {
        let time: Double
        let arPosition: [Double]?
        let relativeMeters: Meters?
    }
    let floorPlan: FloorPlanReference
    let originMeters: Origin
    let startPose: Pose
    let samples: [Sample]
}

private struct Snapshots: Decodable {
    struct Vertex: Decodable {
        let point: ImagePoint; let time: Double; let sampleIndex: Int; let part: Int
        var input: RecordingRouteVertex {
            RecordingRouteVertex(point: point, time: time, sampleIndex: sampleIndex, part: part)
        }
    }
    struct Chosen: Decodable { let vertices: [Vertex] }
    struct Solver: Decodable { let chosen: Chosen }
    struct Case: Decodable {
        let id: String; let rawFile: String; let recordingStartOffsetSeconds: Double
        let solverSnapshot: Solver?
    }
    let cases: [Case]
}

private struct Expectations: Decodable {
    struct Vertex: Decodable {
        let x: Double; let y: Double; let t: Double; let sampleIndex: Int; let part: Int
    }
    struct Case: Decodable {
        let id: String; let vertices: [Vertex]; let connectedSourcePairs: [[Int]]
    }
    let cases: [Case]
}

private func trackMap() throws -> ValidatedFloorPlan {
    let files = FloorPlanFiles(imagePNG: try NormalFloorPlanFixture.data(for: .image),
        navigationMapJSON: try NormalFloorPlanFixture.data(for: .manifest),
        resolvedMask: try NormalFloorPlanFixture.data(for: .mask))
    let reference = try JSONDecoder().decode(FloorPlanReference.self,
        from: NormalFloorPlanFixture.data(for: .reference))
    return try FloorPlanValidator(imageValidator: PNGFloorPlanImageValidator())
        .validate(files: files, reference: reference)
}

private func vertex(_ time: Double = 0, part: Int = 0, index: Int = 0,
                    point: ImagePoint = ImagePoint(x: 100, y: 120)) -> RecordingRouteVertex {
    RecordingRouteVertex(point: point, time: time, sampleIndex: index, part: part)
}

struct TrackCoordinateTests {
    @Test func sharedCodeConsumesAllFourHandAuthoredCases() throws {
        let decoder = JSONDecoder(), map = try trackMap()
        let snapshots = try decoder.decode(Snapshots.self, from: MinimalTrackFixture.data(for: .solverSnapshots))
        let expected = try decoder.decode(Expectations.self, from: MinimalTrackFixture.data(for: .expectations))
        #expect(snapshots.cases.count == 4)
        for item in snapshots.cases {
            let file = try #require(MinimalTrackFixture.File(rawValue: item.rawFile))
            let raw = try decoder.decode(RawExample.self, from: MinimalTrackFixture.data(for: file))
            let target = try #require(expected.cases.first { $0.id == item.id })
            #expect(raw.floorPlan == map.reference)
            let transform = try TrackCoordinateTransform(floorPlan: map,
                start: raw.startPose.positionNormalized, directionPoint: raw.startPose.directionPointNormalized,
                cameraDirectionRadians: raw.startPose.cameraDirectionRadians)
            #expect(transform.floorPlan == map.reference)
            #expect(transform.pixelsPerMeter == 20)
            #expect(transform.rotationDegrees == 0)
            let inputs = item.solverSnapshot?.chosen.vertices.map(\.input) ?? []
            let timeline = try TrackTimeline.sessionTimeline(from: inputs,
                recordingStartOffset: item.recordingStartOffsetSeconds)
            #expect(timeline.vertices.count == target.vertices.count)
            for (actual, wanted) in zip(timeline.vertices, target.vertices) {
                #expect(actual.point == ImagePoint(x: wanted.x, y: wanted.y))
                #expect(abs(actual.sessionTime - wanted.t) < 1e-9)
                #expect(actual.sampleIndex == wanted.sampleIndex && actual.part == wanted.part)
                let sample = raw.samples[try #require(actual.sampleIndex)]
                let position = try #require(sample.arPosition)
                let relative = try #require(sample.relativeMeters)
                #expect(position.count == 3)
                #expect(position[0] - raw.originMeters.x == relative.x)
                #expect(position[2] - raw.originMeters.z == relative.y)
                // Only these synthetic examples have no correction displacement.
                #expect(try transform.project(RelativeTrackMeters(x: relative.x, y: relative.y)) == actual.point)
            }
            let pairs = try timeline.continuousParts.flatMap { part in
                let indices = try part.map { try #require($0.sampleIndex) }
                return zip(indices, indices.dropFirst()).map { [$0, $1] }
            }
            #expect(pairs == target.connectedSourcePairs)
        }
    }

    @Test func rotationUsesImageDownwardYAndSubtractsCameraHeading() throws {
        let map = try trackMap()
        let downward = try TrackCoordinateTransform(floorPlan: map, start: .init(x: 0.1, y: 0.2),
            directionPoint: .init(x: 0.1, y: 0.4), cameraDirectionRadians: 0)
        #expect(downward.rotationDegrees == 90)
        let down = try downward.project(.init(x: 1, y: 0))
        #expect(abs(down.x - 100) < 1e-9 && abs(down.y - 140) < 1e-9)
        let cameraTurn = try TrackCoordinateTransform(floorPlan: map, start: .init(x: 0.1, y: 0.2),
            directionPoint: .init(x: 0.2, y: 0.2), cameraDirectionRadians: .pi / 2)
        #expect(cameraTurn.rotationDegrees == 270)
        let right = try cameraTurn.project(.init(x: 0, y: 1))
        #expect(abs(right.x - 120) < 1e-9 && abs(right.y - 120) < 1e-9)
    }

    @Test func rejectsUnavailableCameraAndTooShortDirection() throws {
        let map = try trackMap()
        for heading in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            #expect(throws: TrackCoordinateError.invalidAlignment) {
                try TrackCoordinateTransform(floorPlan: map, start: .init(x: 0.1, y: 0.2),
                    directionPoint: .init(x: 0.2, y: 0.2), cameraDirectionRadians: heading)
            }
        }
        for x in [0.1, 0.109] {
            #expect(throws: TrackCoordinateError.invalidAlignment) {
                try TrackCoordinateTransform(floorPlan: map, start: .init(x: 0.1, y: 0.2),
                    directionPoint: .init(x: x, y: 0.2), cameraDirectionRadians: 0)
            }
        }
        _ = try TrackCoordinateTransform(floorPlan: map, start: .init(x: 0.1, y: 0.2),
            directionPoint: .init(x: 0.11, y: 0.2), cameraDirectionRadians: 0)
    }

    @Test func startMustBeFreeButDirectionNeedNotBeFree() throws {
        let map = try trackMap()
        #expect(map.isBlocked(at: .init(x: 220, y: 120)))
        _ = try TrackCoordinateTransform(floorPlan: map, start: .init(x: 0.1, y: 0.2),
            directionPoint: .init(x: 0.22, y: 0.2), cameraDirectionRadians: 0)
        #expect(throws: FloorPlanValidationError.blockedStart) {
            try TrackCoordinateTransform(floorPlan: map, start: .init(x: 0.22, y: 0.2),
                directionPoint: .init(x: 0.1, y: 0.2), cameraDirectionRadians: 0)
        }
        #expect(throws: FloorPlanValidationError.invalidCoordinate) {
            try TrackCoordinateTransform(floorPlan: map, start: .init(x: 1, y: 0.2),
                directionPoint: .init(x: 0.1, y: 0.2), cameraDirectionRadians: 0)
        }
    }

    @Test func rawProjectionDoesNotClampDriftAndRejectsNonfiniteResults() throws {
        let transform = try TrackCoordinateTransform(floorPlan: trackMap(), start: .init(x: 0.1, y: 0.2),
            directionPoint: .init(x: 0.2, y: 0.2), cameraDirectionRadians: 0)
        #expect(try transform.project(.init(x: -10, y: 0)) == ImagePoint(x: -100, y: 120))
        for x in [Double.nan, .infinity, .greatestFiniteMagnitude] {
            #expect(throws: TrackCoordinateError.invalidCoordinate) { try transform.project(.init(x: x, y: 0)) }
        }
    }

    @Test func correctedPixelsAreNotReprojectedOrScaled() throws {
        // Deliberately differs from the raw projection. AAR must preserve it.
        let corrected = ImagePoint(x: 137.25, y: 141.5)
        let result = try TrackTimeline.sessionTimeline(from: [vertex(2, point: corrected)], recordingStartOffset: 0.4)
        #expect(result.vertices.first?.point == corrected)
        #expect(result.vertices.first?.sessionTime == 2.4)
    }

    @Test func separatesRunsEvenWhenPartIdentifierReappears() throws {
        let input = [vertex(0, part: 0, index: 0), vertex(1, part: 0, index: 1),
            vertex(4, part: 1, index: 4), vertex(5, part: 0, index: 5)]
        let timeline = try TrackTimeline.sessionTimeline(from: input, recordingStartOffset: 0.4)
        #expect(timeline.continuousParts.map { $0.map(\.sampleIndex) } == [[0, 1], [4], [5]])
    }

    @Test func acceptsEqualTimesWithoutSortingOrReindexing() throws {
        let input = [vertex(1, index: 9), vertex(1, index: 11)]
        let result = try TrackTimeline.sessionTimeline(from: input, recordingStartOffset: 0)
        #expect(result.vertices.map(\.sampleIndex) == [9, 11])
        #expect(result.vertices.map(\.sessionTime) == [1, 1])
        #expect(throws: TrackCoordinateError.timeOrder) {
            try TrackTimeline.sessionTimeline(from: [vertex(2), vertex(1)], recordingStartOffset: 0)
        }
    }

    @Test func rejectsInvalidTimesAndOverflow() throws {
        for time in [Double.nan, .infinity, -1] {
            #expect(throws: TrackCoordinateError.invalidTime) {
                try TrackTimeline.sessionTimeline(from: [vertex(time)], recordingStartOffset: 0)
            }
            #expect(throws: TrackCoordinateError.invalidTime) {
                try TrackTimeline.sessionTimeline(from: [], recordingStartOffset: time)
            }
        }
        #expect(throws: TrackCoordinateError.invalidTime) {
            try TrackTimeline.sessionTimeline(from: [vertex(.greatestFiniteMagnitude)],
                recordingStartOffset: .greatestFiniteMagnitude)
        }
    }

    @Test func rejectsInvalidVertexMetadata() throws {
        for bad in [vertex(part: -1), vertex(index: -1), vertex(point: .init(x: .nan, y: 0))] {
            #expect(throws: TrackCoordinateError.invalidVertex) {
                try TrackTimeline.sessionTimeline(from: [bad], recordingStartOffset: 0)
            }
        }
    }

    @Test func emptyResultDoesNotFabricateStationaryPath() throws {
        let result = try TrackTimeline.sessionTimeline(from: [], recordingStartOffset: 0.4)
        #expect(result.vertices.isEmpty && result.continuousParts.isEmpty)
    }

    @Test func generatedVertexMayHaveNoSourceIndex() throws {
        let input = RecordingRouteVertex(point: .init(x: 110, y: 125), time: 0.5, sampleIndex: nil, part: 0)
        let result = try TrackTimeline.sessionTimeline(from: [input], recordingStartOffset: 0.4)
        #expect(result.vertices.first?.sampleIndex == nil)
        #expect(result.vertices.first?.point == input.point)
    }

    @Test func cancellationPropagatesEvenForEmptyResult() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try TrackTimeline.sessionTimeline(from: [], recordingStartOffset: 0)
        }
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
