//
//  StorageTransfer.swift
//  CQB
//

import CQBCore
import CryptoKit
import FirebaseStorage
import Foundation
import OSLog

protocol StorageTransferTask: AnyObject {
    func cancel()
}

extension StorageDownloadTask: StorageTransferTask {}
extension StorageUploadTask: StorageTransferTask {}

/// Storage 구현이 같이 쓰는 크기 제한, 에러 변환, 지문 계산.
enum StorageTransfer {
    struct UploadRequest: Sendable {
        let data: Data
        let fileRole: String
        let path: String
        let contentType: String
        let maxBytes: Int64

        init(
            data: Data,
            fileRole: String,
            path: String,
            contentType: String,
            maxBytes: Int64 = StorageTransfer.maxFileBytes
        ) {
            self.data = data
            self.fileRole = fileRole
            self.path = path
            self.contentType = contentType
            self.maxBytes = maxBytes
        }
    }

    private static let floorPlanSaveLogger = Logger(
        subsystem: "com.wffmst.cqb",
        category: "FloorPlanSave"
    )

    /// Storage 규칙과 같은 기본 파일 크기 제한이다.
    static let maxFileBytes: Int64 = 20 * 1024 * 1024
    static let maxWorldMapBytes: Int64 = 50 * 1024 * 1024
    static let maxWorldMapSetupBytes: Int64 = 1 * 1024 * 1024

    static func reference(_ path: String) async throws -> StorageReference {
        let (storage, _) = try await FirebaseAccess.storage()
        return storage.reference(withPath: path)
    }

    static func upload(
        _ data: Data,
        to path: String,
        contentType: String,
        maxBytes: Int64 = maxFileBytes
    ) async throws {
        try Task.checkCancellation()
        guard Int64(data.count) <= maxBytes else { throw RepositoryError.fileTooLarge }
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        let ref = try await reference(path)
        try Task.checkCancellation()
        let _: Void = try await performCancellableTransfer { completion in
            ref.putData(data, metadata: metadata) { _, error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// 사전 검증이 끝난 한 묶음의 독립적인 불변 파일을 동시에 처리한다.
    static func uploadConcurrently(_ requests: [UploadRequest]) async throws {
        try await uploadConcurrently(requests) { request in
            try await uploadIfMissingOrMatching(
                request.data,
                fileRole: request.fileRole,
                to: request.path,
                contentType: request.contentType,
                maxBytes: request.maxBytes
            )
        }
    }

    /// 실제 Storage 요청 없이 동시 실행을 검증할 수 있도록 작업 실행부만 주입한다.
    static func uploadConcurrently(
        _ requests: [UploadRequest],
        operation: @escaping @Sendable (UploadRequest) async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTask {
                    try Task.checkCancellation()
                    try await operation(request)
                }
            }
            do {
                while let _ = try await group.next() {}
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// 불변 파일 업로드가 일부 성공한 뒤 재시도돼도 같은 바이트는 덮어쓰지 않고 성공으로 처리한다.
    static func uploadIfMissingOrMatching(
        _ data: Data,
        fileRole: String,
        to path: String,
        contentType: String,
        maxBytes: Int64 = maxFileBytes
    ) async throws {
        try await uploadIfMissingOrMatching(
            data,
            fileRole: fileRole,
            to: path,
            contentType: contentType,
            maxBytes: maxBytes,
            downloadOperation: { path, maxBytes in
                try await download(path, maxBytes: maxBytes)
            },
            uploadOperation: { data, path, contentType, maxBytes in
                try await upload(data, to: path, contentType: contentType, maxBytes: maxBytes)
            }
        )
    }

    /// 테스트에서 원격 확인과 업로드 경계의 취소를 검증할 수 있도록 작업 실행부를 주입한다.
    static func uploadIfMissingOrMatching(
        _ data: Data,
        fileRole: String,
        to path: String,
        contentType: String,
        maxBytes: Int64 = maxFileBytes,
        downloadOperation: @escaping @Sendable (String, Int64) async throws -> Data,
        uploadOperation: @escaping @Sendable (Data, String, String, Int64) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        guard Int64(data.count) <= maxBytes else { throw RepositoryError.fileTooLarge }
        let remoteCheckStarted = ContinuousClock.now
        let existing: Data
        do {
            existing = try await downloadOperation(path, maxBytes)
        } catch let error as RepositoryError where error == .notFound {
            logTransferDuration(
                "remote.check",
                fileRole: fileRole,
                byteCount: data.count,
                since: remoteCheckStarted,
                result: "missing"
            )
            try Task.checkCancellation()
            let uploadStarted = ContinuousClock.now
            do {
                try await uploadOperation(data, path, contentType, maxBytes)
                logTransferDuration(
                    "remote.upload",
                    fileRole: fileRole,
                    byteCount: data.count,
                    since: uploadStarted,
                    result: "success"
                )
                return
            } catch {
                logTransferDuration(
                    "remote.upload",
                    fileRole: fileRole,
                    byteCount: data.count,
                    since: uploadStarted,
                    result: "failure"
                )
                throw error
            }
        } catch {
            logTransferDuration(
                "remote.check",
                fileRole: fileRole,
                byteCount: data.count,
                since: remoteCheckStarted,
                result: "failure"
            )
            throw error
        }

        let result = existing == data ? "matched" : "mismatch"
        logTransferDuration(
            "remote.check",
            fileRole: fileRole,
            byteCount: data.count,
            since: remoteCheckStarted,
            result: result
        )
        guard existing == data else { throw RepositoryError.integrityMismatch }
    }

    static func download(_ path: String, maxBytes: Int64 = maxFileBytes) async throws -> Data {
        let ref = try await reference(path)
        do {
            return try await performCancellableTransfer { completion in
                ref.getData(maxSize: maxBytes) { data, error in
                    if let error {
                        completion(.failure(error))
                    } else if let data {
                        completion(.success(data))
                    } else {
                        completion(.failure(StorageTransferError.missingDownloadData))
                    }
                }
            }
        } catch {
            throw mapDownloadError(error)
        }
    }

    /// Swift 작업 취소를 Firebase가 반환한 실제 전송 작업까지 전달한다.
    static func performCancellableTransfer<Value: Sendable>(
        _ start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> any StorageTransferTask
    ) async throws -> Value {
        let cancellation = StorageTransferCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = start { result in
                    let wasCancelled = cancellation.finish()
                    if wasCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(with: result)
                    }
                }
                cancellation.register(task)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// SDK가 데이터를 반환하기 전에 감지한 다운로드 크기 초과도 앱의 용량 오류로 전달한다.
    static func mapDownloadError(_ error: Error) -> Error {
        if let storageError = error as? StorageError, case .downloadSizeExceeded = storageError {
            return RepositoryError.fileTooLarge
        }
        return mapNotFound(error)
    }

    /// 없는 파일 에러를 앱이 아는 `RepositoryError.notFound`로 바꾼다.
    static func mapNotFound(_ error: Error) -> Error {
        if let storageError = error as? StorageError, case .objectNotFound = storageError {
            return RepositoryError.notFound
        }
        return error
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func logTransferDuration(
        _ stage: String,
        fileRole: String,
        byteCount: Int,
        since start: ContinuousClock.Instant,
        result: String
    ) {
#if DEBUG
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000
            + Double(duration.attoseconds) / 1_000_000_000_000_000
        floorPlanSaveLogger.info(
            "event=floor-plan-save stage=\(stage, privacy: .public) file=\(fileRole, privacy: .public) bytes=\(byteCount, privacy: .public) result=\(result, privacy: .public) duration_ms=\(milliseconds, privacy: .public)"
        )
#endif
    }
}

private enum StorageTransferError: Error {
    case missingDownloadData
}

private final class StorageTransferCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: (any StorageTransferTask)?
    private var isCancellationRequested = false
    private var isFinished = false

    func register(_ task: any StorageTransferTask) {
        lock.lock()
        if isFinished {
            lock.unlock()
            return
        }
        if isCancellationRequested {
            lock.unlock()
            task.cancel()
            return
        }
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        guard !isFinished, !isCancellationRequested else {
            lock.unlock()
            return
        }
        isCancellationRequested = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func finish() -> Bool {
        lock.lock()
        isFinished = true
        task = nil
        let wasCancelled = isCancellationRequested
        lock.unlock()
        return wasCancelled
    }
}
