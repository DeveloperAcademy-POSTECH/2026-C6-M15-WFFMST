import CQBCore
import Foundation
import Testing
@testable import CQBFirebase

private let floorPlanID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
private let identity = TrackIdentity(
    sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
    memberID: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
    recordingID: UUID(uuidString: "00000000-0000-0000-0000-000000000704")!
)
private let reference = FloorPlanReference(floorPlanID: floorPlanID, navigationSHA256: "nav-sha")

@Test("도면 파일 3개는 floorPlans/{floorPlanID}/ 아래에 있다")
func floorPlanPaths() {
    let base = "floorPlans/00000000-0000-0000-0000-000000000701"
    #expect(StoragePaths.floorPlanImage(reference) == "\(base)/original.png")
    #expect(StoragePaths.floorPlanMask(reference) == "\(base)/resolved-mask.bin")
    #expect(StoragePaths.floorPlanNavigationMap(reference) == "\(base)/navigation-map.json")
}

@Test("보정 결과는 기록당 하나의 result.json이다")
func trackResultPath() {
    #expect(StoragePaths.trackResult(identity)
        == "sessions/00000000-0000-0000-0000-000000000702/recordings/00000000-0000-0000-0000-000000000704/result.json")
}

@Test("영상 조각 파일명은 0 기반 네 자리 index다")
func videoChunkPaths() {
    let base = "sessions/00000000-0000-0000-0000-000000000702/recordings/00000000-0000-0000-0000-000000000704/video"
    #expect(StoragePaths.videoChunk(identity, index: 0) == "\(base)/chunk_0000.mp4")
    #expect(StoragePaths.videoChunk(identity, index: 12) == "\(base)/chunk_0012.mp4")
    #expect(StoragePaths.videoChunkFileName(index: 3) == "chunk_0003.mp4")
}

@Test("도면 지문은 소문자 16진수 SHA-256이다")
func sha256Format() {
    #expect(StorageTransfer.sha256(Data("{}".utf8))
        == "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
}
