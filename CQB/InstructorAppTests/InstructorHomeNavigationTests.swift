import XCTest
@testable import InstructorApp

@MainActor
final class InstructorHomeNavigationTests: XCTestCase {
    // iOS 26 Simulator의 MainActor 격리 객체 deinit 런타임 오류를 피해
    // 각 Store를 테스트 프로세스 수명 동안 유지한다.
    private static var retainedStores: [InstructorStore] = []

    func testTrainingHistoryCanOpenFromHomeAndReturn() {
        let store = InstructorStore()
        Self.retainedStores.append(store)

        XCTAssertEqual(store.phase, .home)

        store.openTrainingHistory()

        XCTAssertEqual(store.phase, .trainingHistory)
        XCTAssertTrue(store.canGoBack)

        store.goBack()

        XCTAssertEqual(store.phase, .home)
    }

    func testSessionCreationRequiresARegisteredFloorPlan() {
        let store = InstructorStore(floorPlans: [])
        Self.retainedStores.append(store)

        store.openSessionCreation()

        XCTAssertEqual(store.phase, .home)
        XCTAssertFalse(store.canOpenSessionCreation)
    }
}
