import Foundation
import CQBCore

/// MemberApp 로컬 진단 파일. 서버 공통 raw 계약으로 사용하지 않는다.
nonisolated struct RawTrackDocument: Codable, Sendable {
    var schemaVersion = 1
    let identity: TrackIdentity
    let floorPlan: FloorPlanReference
    let localStartedAt: Date
    let start: MapPoint
    let direction: MapPoint
    let pixelsPerMeter: Double
    let rotationDegrees: Double
    let samples: [RawTrackSample]
}

nonisolated struct RawTrackSample: Codable, Sendable {
    let t: Double
    let x: Double
    let y: Double
    let z: Double
    let relative: MapPoint?
    let trackingState: String
    let segment: Int
}

nonisolated struct LocalRecordingFiles: Sendable {
    let directory: URL
    var video: URL { directory.appendingPathComponent("video.mov") }
    var raw: URL { directory.appendingPathComponent("raw-track.json") }
    var result: URL { directory.appendingPathComponent("result.json") }
    var diagnostics: URL { directory.appendingPathComponent("correction-diagnostics.json") }
}
