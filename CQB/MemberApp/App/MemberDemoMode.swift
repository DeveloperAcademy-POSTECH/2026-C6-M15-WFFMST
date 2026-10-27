import Foundation
import Observation

/// 운영 화면과 데모 화면을 서로 다른 Store로 전환한다.
/// 실행마다 새로운 Store를 만들기 때문에 데모 상태가 운영 세션으로 전달되지 않는다.
@MainActor
@Observable
final class MemberDemoMode {
    private(set) var isActive = false
    private(set) var runID = UUID()

    func start() {
        runID = UUID()
        isActive = true
    }

    func stop() {
        isActive = false
    }
}
