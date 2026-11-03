import Foundation

nonisolated extension AsyncThrowingStream where Element: Sendable, Failure == Error {
    /// 첫 값만 받고 스트림을 끝낸다. 값이 오기 전에 스트림이 끝나면 nil이다.
    ///
    /// 첫 값에서 반복을 멈추기만 하면 Firestore 리스너가 연속체를 잡고 있어 `onTermination`이 불리지 않고 구독이 남는다.
    /// 다음 값을 기다리는 중에 취소해야 스트림이 끝나고 서버 구독이 해제된다.
    func firstValue() async throws -> Element? {
        let consumer = Task<Element?, Error> {
            var iterator = makeAsyncIterator()
            let value = try await iterator.next()
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? await iterator.next()
            return value
        }
        return try await withTaskCancellationHandler {
            try await consumer.value
        } onCancel: {
            consumer.cancel()
        }
    }
}
