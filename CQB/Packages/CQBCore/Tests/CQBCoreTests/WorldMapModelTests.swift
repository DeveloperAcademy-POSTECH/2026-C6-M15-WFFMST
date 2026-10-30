import Foundation
import Testing
@testable import CQBCore

private let floorPlan = FloorPlanReference(
    floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
    navigationSHA256: "navigation-sha256"
)
private let worldMap = WorldMapReference(
    worldMapID: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!,
    setupSHA256: "setup-sha256",
    floorPlan: floorPlan
)
private let otherFloorPlan = FloorPlanReference(
    floorPlanID: UUID(uuidString: "00000000-0000-0000-0000-000000000903")!,
    navigationSHA256: "other-navigation-sha256"
)

private func sampleSetup() -> WorldMapSetup {
    let pose = ARPose(x: 4.25, y: 0.07, z: 6.1, forwardX: -0.9, forwardZ: -0.44)
    return WorldMapSetup(
        schemaVersion: 1,
        worldMapID: worldMap.worldMapID,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000),
        floorPlan: floorPlan,
        start: WorldMapStart(
            pose: pose,
            planPoint: NormalizedPoint(x: 0.856, y: 0.372),
            directionPoint: NormalizedPoint(x: 0.912, y: 0.366)
        ),
        correspondences: [
            WorldMapCorrespondence(
                label: "출발 기준점",
                planPoint: NormalizedPoint(x: 0.856, y: 0.372),
                arPose: pose,
                capturedAt: Date(timeIntervalSince1970: 1_799_999_900)
            ),
        ],
        alignment: WorldMapAlignment(
            rotationDegrees: 32.1,
            pixelsPerMeter: 40,
            translation: ImagePoint(x: 1_200, y: 300),
            rmsErrorMeters: 0.3,
            algorithmVersion: "similarity-v1"
        ),
        compression: .lzfse,
        worldMapSHA256: "world-map-sha256",
        worldMapBytes: 17_320_220
    )
}

@Test("Session이 스캔 참조를 보존한다")
func sessionWorldMapRoundTrip() throws {
    let session = Session(
        id: UUID(),
        pin: "123456",
        name: "스캔 훈련",
        status: .waiting,
        floorPlan: floorPlan,
        worldMap: worldMap
    )

    let decoded = try codableRoundTrip(session)

    #expect(decoded.worldMap == worldMap)
}

@Test("스캔 참조가 없는 기존 세션 문서도 읽힌다")
func sessionWithoutWorldMapDecodes() throws {
    let session = Session(id: UUID(), pin: "654321", name: "기존 훈련", status: .waiting, floorPlan: floorPlan)

    let object = try encodedJSONObject(session)
    let decoded = try codableRoundTrip(session)

    #expect(object["worldMap"] == nil)
    #expect(decoded.worldMap == nil)
}

@Test("WorldMapSetup이 대응점, 변환, 무결성 정보를 보존한다")
func worldMapSetupRoundTrip() throws {
    let setup = sampleSetup()

    let decoded = try codableRoundTrip(setup)

    #expect(decoded == setup)
}

@Test("setup.json은 같은 스캔 ID와 같은 도면일 때만 참조와 맞는다")
func worldMapSetupMatchesReference() {
    let setup = sampleSetup()

    #expect(setup.matches(worldMap))
    #expect(!setup.matches(WorldMapReference(
        worldMapID: UUID(), setupSHA256: worldMap.setupSHA256, floorPlan: floorPlan
    )))
    #expect(!setup.matches(WorldMapReference(
        worldMapID: worldMap.worldMapID, setupSHA256: worldMap.setupSHA256, floorPlan: otherFloorPlan
    )))
}

@Test("세션의 스캔은 세션 도면에서 만든 것이어야 한다")
func sessionWorldMapMatchesFloorPlan() {
    let matching = Session(id: UUID(), pin: "111111", name: "같은 도면", status: .waiting, floorPlan: floorPlan, worldMap: worldMap)
    let mismatched = Session(id: UUID(), pin: "222222", name: "다른 도면", status: .waiting, floorPlan: otherFloorPlan, worldMap: worldMap)
    let withoutScan = Session(id: UUID(), pin: "333333", name: "스캔 없음", status: .waiting, floorPlan: floorPlan)

    #expect(matching.worldMapMatchesFloorPlan)
    #expect(!mismatched.worldMapMatchesFloorPlan)
    #expect(withoutScan.worldMapMatchesFloorPlan)
}

@Test("WorldMapCompression은 setup.json에 문자열로 저장된다")
func worldMapCompressionRawValues() {
    #expect(WorldMapCompression.none.rawValue == "none")
    #expect(WorldMapCompression.lzfse.rawValue == "lzfse")
}

@Test("WorldMapAlignment는 AR 월드 좌표를 도면 이미지 좌표로 바꾼다")
func worldMapAlignmentImagePoint() {
    let identity = WorldMapAlignment(
        rotationDegrees: 0, pixelsPerMeter: 10, translation: ImagePoint(x: 100, y: 200),
        rmsErrorMeters: 0, algorithmVersion: "test"
    )
    let point = identity.imagePoint(x: 2, z: 3)
    #expect(point.x == 120)
    #expect(point.y == 230)

    let rotated = WorldMapAlignment(
        rotationDegrees: 90, pixelsPerMeter: 10, translation: ImagePoint(x: 0, y: 0),
        rmsErrorMeters: 0, algorithmVersion: "test"
    )
    let turned = rotated.imagePoint(x: 1, z: 0)
    #expect(abs(turned.x) < 1e-9)
    #expect(abs(turned.y - 10) < 1e-9)
}
