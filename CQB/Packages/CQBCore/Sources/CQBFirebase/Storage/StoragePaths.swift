//
//  StoragePaths.swift
//  CQB
//

import CQBCore
import Foundation

/// Storage 파일 경로 (`docs/cqb-core-models.md` Storage 계약). 경로 문자열은 여기서만 만든다.
enum StoragePaths {
    static func floorPlanImage(_ reference: FloorPlanReference) -> String {
        "\(floorPlan(reference))/original.png"
    }

    static func floorPlanMask(_ reference: FloorPlanReference) -> String {
        "\(floorPlan(reference))/resolved-mask.bin"
    }

    static func floorPlanNavigationMap(_ reference: FloorPlanReference) -> String {
        "\(floorPlan(reference))/navigation-map.json"
    }

    static func trackResult(_ identity: TrackIdentity) -> String {
        "\(recording(identity))/result.json"
    }

    static func videoChunk(_ identity: TrackIdentity, index: Int) -> String {
        "\(recording(identity))/video/\(videoChunkFileName(index: index))"
    }

    /// 0 기반 index를 네 자리로 채운다. 예: 3 → `chunk_0003.mp4`
    static func videoChunkFileName(index: Int) -> String {
        "chunk_\(String(format: "%04d", index)).mp4"
    }

    private static func floorPlan(_ reference: FloorPlanReference) -> String {
        "floorPlans/\(reference.floorPlanID.uuidString)"
    }

    private static func recording(_ identity: TrackIdentity) -> String {
        "sessions/\(identity.sessionID.uuidString)/recordings/\(identity.recordingID.uuidString)"
    }
}
