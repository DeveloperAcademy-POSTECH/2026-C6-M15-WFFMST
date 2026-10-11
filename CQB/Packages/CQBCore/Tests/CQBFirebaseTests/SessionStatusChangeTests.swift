import CQBCore
import Testing
@testable import CQBFirebase

@Test("상태는 앞으로 바뀌고, 중간 단계는 건너뛸 수 있다")
func statusMovesForward() {
    #expect(FirestoreSessionRepository.statusChange(from: .preparing, to: .waiting) == .forward)
    #expect(FirestoreSessionRepository.statusChange(from: .waiting, to: .running) == .forward)
    #expect(FirestoreSessionRepository.statusChange(from: .running, to: .ended) == .forward)
    #expect(FirestoreSessionRepository.statusChange(from: .waiting, to: .ended) == .forward)
}

@Test("같은 상태로 다시 요청하면 아무것도 바꾸지 않는다")
func sameStatusIsUnchanged() {
    #expect(FirestoreSessionRepository.statusChange(from: .running, to: .running) == .unchanged)
    #expect(FirestoreSessionRepository.statusChange(from: .ended, to: .ended) == .unchanged)
}

@Test("이전 단계로는 되돌릴 수 없다")
func statusCannotMoveBackward() {
    #expect(FirestoreSessionRepository.statusChange(from: .ended, to: .running) == .backward)
    #expect(FirestoreSessionRepository.statusChange(from: .running, to: .waiting) == .backward)
}
