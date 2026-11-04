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
}
