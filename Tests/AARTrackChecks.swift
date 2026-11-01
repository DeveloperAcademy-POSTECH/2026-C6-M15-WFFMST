import CoreGraphics
import CQBCore
import Foundation

@main
enum AARTrackChecks {
    static func main() async throws {
        checkPosition()
        checkOffset()
        checkLayout()
        await checkLoader()
        print("AARTrackChecks passed")
    }

    // MARK: - 시각별 위치

    static func checkPosition() {
        let path = AARTrackPath(result: result(
            vertices: [
                vertex(t: 2, x: 100, y: 100, part: 0),
                vertex(t: 0, x: 0, y: 0, part: 0),
                vertex(t: 4, x: 300, y: 300, part: 1),
                vertex(t: 6, x: 500, y: 300, part: 1),
            ],
            unresolved: [TrackUnresolvedInterval(
                from: 5, to: 5.5, bounds: .closed, reason: .trackingLost, samples: TrackSampleRange(from: 0, through: 0)
            )]
        ))

        check(path.position(at: -1) == .init(point: ImagePoint(x: 0, y: 0), presence: .uncertain), "첫 꼭짓점 이전에는 첫 위치에 흐리게 표시한다")
        check(path.position(at: 0) == .init(point: ImagePoint(x: 0, y: 0), presence: .tracked), "첫 꼭짓점 위치")
        check(path.position(at: 1) == .init(point: ImagePoint(x: 50, y: 50), presence: .tracked), "같은 구간은 직선으로 잇는다 (정렬 전 입력)")
        check(path.position(at: 3) == .init(point: ImagePoint(x: 100, y: 100), presence: .uncertain), "구간이 바뀌는 사이는 마지막 위치에 흐리게")
        check(path.position(at: 4.5)?.presence == .tracked, "새 구간에서는 다시 또렷하게")
        check(path.position(at: 5.25) == .init(point: ImagePoint(x: 425, y: 300), presence: .uncertain), "추적 끊김 구간은 흐리게")
        check(path.position(at: 100) == .init(point: ImagePoint(x: 500, y: 300), presence: .tracked), "마지막 이후에는 마지막 위치에 고정")
        check(path.endTime == 6, "타임라인 길이는 마지막 꼭짓점 시각")

        let empty = AARTrackPath(result: result(vertices: []))
        check(empty.position(at: 0) == nil && empty.endTime == nil, "꼭짓점이 없으면 위치도 길이도 없다")

        let same = AARTrackPath(result: result(vertices: [vertex(t: 1, x: 10, y: 10, part: 0), vertex(t: 1, x: 20, y: 20, part: 0)]))
        check(same.position(at: 1)?.point == ImagePoint(x: 20, y: 20), "같은 시각 꼭짓점은 나중 것을 쓴다")
    }

    static func checkOffset() {
        let path = AARTrackPath(
            result: result(vertices: [vertex(t: 0, x: 0, y: 0, part: 0), vertex(t: 10, x: 100, y: 0, part: 0)]),
            recordingOffset: 3
        )
        check(path.position(at: 2) == .init(point: ImagePoint(x: 0, y: 0), presence: .uncertain), "세션 시각이 기록 시작 전이면 첫 위치에 흐리게 표시한다")
        check(path.position(at: 8)?.point == ImagePoint(x: 50, y: 0), "세션 시각에서 기록 시작 오프셋을 뺀다")
        check(path.endTime == 13, "타임라인 길이는 세션 시각 기준")
    }

    // MARK: - 좌표 변환

    static func checkLayout() {
        // 가로로 긴 도면: 여백 20을 뺀 960×560 안에 2:1로 맞추면 960×480, 위아래 가운데
        let wide = AARFloorPlanLayout(imageSize: CGSize(width: 2000, height: 1000), container: CGSize(width: 1000, height: 600), padding: 20)
        check(wide.imageFrame == CGRect(x: 20, y: 60, width: 960, height: 480), "가로로 긴 도면 맞추기")
        check(wide.viewPoint(for: ImagePoint(x: 0, y: 0)) == CGPoint(x: 20, y: 60), "왼쪽 위")
        check(wide.viewPoint(for: ImagePoint(x: 2000, y: 1000)) == CGPoint(x: 980, y: 540), "오른쪽 아래")
        check(wide.viewPoint(for: ImagePoint(x: 1000, y: 500)) == CGPoint(x: 500, y: 300), "가운데")

        let tall = AARFloorPlanLayout(imageSize: CGSize(width: 500, height: 1000), container: CGSize(width: 1000, height: 600), padding: 20)
        check(tall.imageFrame == CGRect(x: 360, y: 20, width: 280, height: 560), "세로로 긴 도면 맞추기")

        let broken = AARFloorPlanLayout(imageSize: .zero, container: CGSize(width: 100, height: 100), padding: 20)
        check(broken.viewPoint(for: ImagePoint(x: 5, y: 5)) == CGPoint(x: 20, y: 20), "크기를 모르는 도면에서도 멈추지 않는다")
    }

    // MARK: - 다운로드

    static func checkLoader() async {
        let ok = result(vertices: [vertex(t: 0, x: 0, y: 0, part: 0)])
        let ready = FakeRepository(response: .success(ok))
        let loader = AARTrackLoader(repository: ready)
        async let first = loader.load(identity, floorPlan: floorPlan, recordingOffset: 0)
        async let second = loader.load(identity, floorPlan: floorPlan, recordingOffset: 0)
        let results = await [first, second]
        check(results.allSatisfy { $0 == .loaded(AARTrackPath(result: ok), partial: false) }, "받은 결과")
        _ = await loader.load(identity, floorPlan: floorPlan, recordingOffset: 0)
        check(await ready.calls == 1, "같은 기록은 한 번만 받는다 (동시 요청 포함)")

        let partial = result(vertices: [vertex(t: 0, x: 0, y: 0, part: 0)], status: .partial)
        check(await AARTrackLoader(repository: FakeRepository(response: .success(partial)))
            .load(identity, floorPlan: floorPlan, recordingOffset: 0) == .loaded(AARTrackPath(result: partial), partial: true), "일부만 보정된 결과")

        let failed = result(vertices: [], status: .failed)
        check(await AARTrackLoader(repository: FakeRepository(response: .success(failed)))
            .load(identity, floorPlan: floorPlan, recordingOffset: 0) == .failed, "보정 실패")

        let other = FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "other")
        check(await AARTrackLoader(repository: ready)
            .load(identity, floorPlan: other, recordingOffset: 0) == .floorPlanMismatch, "세션 도면과 다른 결과")

        let missing = FakeRepository(response: .failure(RepositoryError.notFound))
        let missingLoader = AARTrackLoader(repository: missing)
        check(await missingLoader.load(identity, floorPlan: floorPlan, recordingOffset: 0) == .notUploaded, "아직 올라오지 않음")
        _ = await missingLoader.load(identity, floorPlan: floorPlan, recordingOffset: 0)
        check(await missing.calls == 2, "아직 없으면 다음 요청에서 다시 받는다")

        let offline = FakeRepository(response: .failure(URLError(.notConnectedToInternet)))
        check(await AARTrackLoader(repository: offline)
            .load(identity, floorPlan: floorPlan, recordingOffset: 0) == .unavailable, "네트워크 오류")
    }

    // MARK: - 도우미

    static let floorPlan = FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "nav")
    static let identity = TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID())

    static func vertex(t: Double, x: Double, y: Double, part: Int) -> TrackResultVertex {
        TrackResultVertex(t: t, point: ImagePoint(x: x, y: y), part: part, sampleIndex: nil)
    }

    static func result(
        vertices: [TrackResultVertex],
        unresolved: [TrackUnresolvedInterval] = [],
        status: TrackResultStatus = .done
    ) -> TrackResultDocument {
        TrackResultDocument(
            identity: identity,
            floorPlan: floorPlan,
            sourceRawSHA256: "raw",
            algorithm: TrackAlgorithmIdentity(name: "test", version: "1", settingsID: "test"),
            status: status,
            vertices: vertices,
            sampleCoverage: [],
            unresolvedIntervals: unresolved,
            searchIncomplete: false,
            warnings: []
        )
    }

    static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("❌ \(message)")
            exit(1)
        }
    }
}

private actor FakeRepository: TrackResultRepository {
    let response: Result<TrackResultDocument, Error>
    private(set) var calls = 0

    init(response: Result<TrackResultDocument, Error>) {
        self.response = response
    }

    func upload(_ result: TrackResultDocument) async throws {}

    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument {
        calls += 1
        try await Task.sleep(for: .milliseconds(10))
        return try response.get()
    }
}
