import Foundation

// 앱 내부 경계. 정규화 이미지는 화면과 AR 대응점이 즉시 사용하고,
// 마스크 추출은 별도 Task로 계속할 수 있도록 두 단계를 분리한다.
protocol FloorPlanImporting: Sendable {
    func normalize(url: URL) async throws -> LocalImportedImage
    func extractMask(from image: LocalImportedImage) async throws -> LocalMaskExtractionResult
    func extractFallbackMask(from image: LocalImportedImage) async throws -> LocalMaskExtractionResult
}

extension FloorPlanImporting {
    /// 기존 단일 단계 호출이 필요한 검사 도구를 위한 조합 API다.
    func process(url: URL) async throws -> LocalExtractionResult {
        let image = try await normalize(url: url)
        let result: LocalMaskExtractionResult
        do {
            result = try await extractMask(from: image)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result = try await extractFallbackMask(from: image)
        }
        return LocalExtractionResult(
            image: image,
            baseGrid: result.baseGrid,
            suggestedOutline: result.suggestedOutline,
            extractionAlgorithm: result.extractionAlgorithm
        )
    }
}
