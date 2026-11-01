import CQBFirebase
import os
import SwiftData
import SwiftUI

@main
struct InstructorApp: App {
    private static let logger = Logger(subsystem: "com.wffmst.cqb", category: "InstructorApp")
    private let floorPlanFileRepository: CachedFloorPlanFileRepository
    private let floorPlanCatalogRepository: any FloorPlanCatalogRepository

    init() {
        floorPlanFileRepository = CachedFloorPlanFileRepository(
            remote: StorageFloorPlanFileRepository()
        )
        do {
            let container = try ModelContainer(for: StoredFloorPlan.self)
            floorPlanCatalogRepository = SwiftDataFloorPlanCatalogRepository(container: container)
        } catch {
            Self.logger.error("도면 목록 저장소 초기화 실패: \(error.localizedDescription, privacy: .private)")
            floorPlanCatalogRepository = UnavailableFloorPlanCatalogRepository(error: error)
        }
        CQBFirebaseModule.configure()
        Task {
            do {
                try await CQBFirebaseModule.signInAnonymously()
            } catch {
                Self.logger.error("익명 로그인 실패: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppContainer(
                floorPlanFileRepository: floorPlanFileRepository,
                worldMapFileRepository: StorageWorldMapFileRepository(),
                floorPlanCatalogRepository: floorPlanCatalogRepository
            )
        }
    }
}
