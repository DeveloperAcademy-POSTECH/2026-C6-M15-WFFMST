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

    @Test("원격 파일 없음 확인 뒤 취소되면 신규 업로드를 시작하지 않는다")
    func cancellationBeforeMissingFileUploadPreventsUpload() async {
        let remoteCheckGate = RemoteCheckGate()
        let recorder = UploadInvocationRecorder()
        let task = Task {
            try await StorageTransfer.uploadIfMissingOrMatching(
                Data("image".utf8),
                fileRole: "floorPlan.image",
                to: "floorPlans/test/image.png",
                contentType: "image/png",
                downloadOperation: { _, _ in
                    await remoteCheckGate.waitUntilReleased()
                    throw RepositoryError.notFound
                },
                uploadOperation: { _, _, _, _ in
                    await recorder.recordUpload()
                }
            )
        }

        await remoteCheckGate.waitUntilWaiting()

        task.cancel()
        await remoteCheckGate.release()

        do {
            try await task.value
            Issue.record("취소된 작업이 성공으로 완료되었습니다.")
        } catch is CancellationError {
            // 기대한 취소 경로다.
        } catch {
            Issue.record("CancellationError 대신 \(error)가 전달되었습니다.")
        }
        #expect(await recorder.uploadCount == 0)
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

private actor RemoteCheckGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var isWaiting = false

    func waitUntilReleased() async {
        isWaiting = true
        let pending = waitingContinuations
        waitingContinuations.removeAll()
        pending.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilWaiting() async {
        guard !isWaiting else { return }
        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor UploadInvocationRecorder {
    private(set) var uploadCount = 0

    func recordUpload() {
        uploadCount += 1
    }
}
