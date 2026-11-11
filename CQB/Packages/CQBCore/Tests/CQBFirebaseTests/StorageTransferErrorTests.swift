import CQBCore
import FirebaseStorage
import Foundation
import Testing
@testable import CQBFirebase

struct StorageTransferErrorTests {
    @Test("Firebase가 다운로드 중 감지한 스캔·설정 파일 용량 초과를 변환한다")
    func mapsFirebaseDownloadSizeExceeded() {
        for maximum in [StorageTransfer.maxWorldMapBytes, StorageTransfer.maxWorldMapSetupBytes] {
            let error = StorageError.downloadSizeExceeded(total: maximum + 1_024 * 1_024, maxSize: maximum)
            let mapped = StorageTransfer.mapDownloadError(error)
            #expect(mapped as? RepositoryError == .fileTooLarge)
        }
    }

    @Test("다운로드 파일 없음은 기존대로 notFound로 변환한다")
    func preservesNotFoundMapping() {
        let error = StorageError.objectNotFound(object: "worldMaps/test/world-map.arexperience", serverError: [:])
        let mapped = StorageTransfer.mapDownloadError(error)
        #expect(mapped as? RepositoryError == .notFound)
    }

    @Test("다른 Firebase 오류는 원래 타입과 코드로 전달한다")
    func preservesOtherFirebaseErrors() throws {
        let error = StorageError.retryLimitExceeded
        let mapped = try #require(StorageTransfer.mapDownloadError(error) as? StorageError)
        #expect(mapped.errorCode == error.errorCode)
    }

    @Test("네트워크 오류를 용량 초과로 오인하지 않는다")
    func preservesNetworkError() {
        let error = NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue)
        let mapped = StorageTransfer.mapDownloadError(error)
        #expect((mapped as NSError) === error)
    }

    @Test("한 파일 묶음의 독립적인 Storage 요청을 동시에 시작한다")
    func uploadsBundleFilesConcurrently() async throws {
        let requests = ["image", "mask", "navigation"].map { role in
            StorageTransfer.UploadRequest(
                data: Data(role.utf8),
                fileRole: role,
                path: "floorPlans/test/\(role)",
                contentType: "application/octet-stream"
            )
        }
        let recorder = UploadConcurrencyRecorder()

        try await StorageTransfer.uploadConcurrently(requests) { request in
            try await recorder.perform(request)
        }

        let result = await recorder.result()
        #expect(result.maximumInFlight == requests.count)
        #expect(result.fileRoles == Set(requests.map(\.fileRole)))
    }
}

private actor UploadConcurrencyRecorder {
    private var inFlight = 0
    private var maximumInFlight = 0
    private var fileRoles: Set<String> = []

    func perform(_ request: StorageTransfer.UploadRequest) async throws {
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        fileRoles.insert(request.fileRole)
        defer { inFlight -= 1 }
        try await Task.sleep(for: .milliseconds(50))
    }

    func result() -> (maximumInFlight: Int, fileRoles: Set<String>) {
        (maximumInFlight, fileRoles)
    }
}
