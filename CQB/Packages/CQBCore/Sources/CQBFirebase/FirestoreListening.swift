//
//  FirestoreListening.swift
//  CQB
//

import FirebaseFirestore
import Foundation

/// Firestore 실시간 구독을 `AsyncThrowingStream`으로 바꾼다.
/// 스트림을 그만 받으면(`for try await`를 빠져나오거나 Task 취소) 구독도 해제한다.
enum FirestoreListening {
    static func stream<Value: Sendable>(
        _ listen: @escaping @Sendable (Firestore, AsyncThrowingStream<Value, Error>.Continuation) -> any ListenerRegistration
    ) -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream { continuation in
            let handle = ListenerHandle()
            continuation.onTermination = { _ in handle.cancel() }
            Task {
                do {
                    let (db, _) = try await FirebaseAccess.firestore()
                    handle.set(listen(db, continuation))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// 로그인을 기다리는 사이에 스트림이 먼저 끝나도 구독이 남지 않게 한다.
private final class ListenerHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var registration: (any ListenerRegistration)?
    private var isCancelled = false

    func set(_ registration: any ListenerRegistration) {
        lock.withLock {
            if isCancelled {
                registration.remove()
            } else {
                self.registration = registration
            }
        }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            registration?.remove()
            registration = nil
        }
    }
}
