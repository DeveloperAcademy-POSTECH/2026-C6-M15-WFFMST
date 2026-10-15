import CQBCore
import Testing
@testable import CQBFirebase

@Test("훈련 시작 전(preparing, waiting)에만 입장할 수 있다")
func joinOnlyBeforeTraining() {
    #expect(FirestoreMemberRepository.canJoin(.preparing))
    #expect(FirestoreMemberRepository.canJoin(.waiting))
    #expect(!FirestoreMemberRepository.canJoin(.running))
    #expect(!FirestoreMemberRepository.canJoin(.ended))
}
