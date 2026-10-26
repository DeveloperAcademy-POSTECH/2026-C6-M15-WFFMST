import Foundation
import Observation

/// 운영 화면과 데모 화면의 구성을 전환한다.
/// 각 화면은 별도의 Store를 사용하므로 데모 상태가 운영 Repository로 전달되지 않는다.
@MainActor
@Observable
final class InstructorDemoMode {
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
