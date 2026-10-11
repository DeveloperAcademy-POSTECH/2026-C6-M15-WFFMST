//
//  StorageTransfer.swift
//  CQB
//

import CQBCore
import CryptoKit
import FirebaseStorage
import Foundation

/// Storage 구현이 같이 쓰는 크기 제한, 에러 변환, 지문 계산.
enum StorageTransfer {
    /// Storage 개발용 규칙과 같은 파일 크기 제한
    static let maxFileBytes: Int64 = 20 * 1024 * 1024

    static func reference(_ path: String) async throws -> StorageReference {
        let (storage, _) = try await FirebaseAccess.storage()
        return storage.reference(withPath: path)
    }

    static func upload(_ data: Data, to path: String, contentType: String) async throws {
        guard Int64(data.count) <= maxFileBytes else { throw RepositoryError.fileTooLarge }
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        let ref = try await reference(path)
        _ = try await ref.putDataAsync(data, metadata: metadata)
    }

    static func download(_ path: String) async throws -> Data {
        let ref = try await reference(path)
        do {
            return try await ref.data(maxSize: maxFileBytes)
        } catch {
            throw mapNotFound(error)
        }
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
}
