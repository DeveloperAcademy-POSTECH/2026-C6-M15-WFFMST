import Foundation

// 앱 내부 경계. 공통 Repository/파일 형식이 확정되면 별도 계약 PR에서 연결한다.
protocol FloorPlanImporting: Sendable {
    func process(url: URL) async throws -> LocalExtractionResult
}
