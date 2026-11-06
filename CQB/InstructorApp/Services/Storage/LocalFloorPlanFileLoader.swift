import CQBCore
import Foundation

nonisolated struct LocalFloorPlanSnapshot: Sendable {
    let registration: LocalRegisteredFloorPlan
    let maskPNGData: Data
}

/// Storage의 불변 도면 묶음을 상세 표시와 마스크 재편집에 쓰는 앱 내부 상태로 복원한다.
nonisolated enum LocalFloorPlanFileLoader {
    static func load(
        files: FloorPlanFiles,
        reference: FloorPlanReference,
        catalog: InstructorFloorPlan
    ) throws -> LocalFloorPlanSnapshot {
        let validated = try LocalFloorPlanFileValidator.validate(files: files, reference: reference)
        let manifest = validated.manifest

        let registration = LocalRegisteredFloorPlan(
            id: manifest.floorPlanID,
            name: catalog.name,
            image: LocalImportedImage(
                pngData: files.imagePNG,
                width: manifest.imageWidth,
                height: manifest.imageHeight,
                fileName: catalog.fileName
            ),
            baseGrid: validated.grid,
            edits: [],
            outline: validated.outline,
            scale: validated.scale,
            resolvedGrid: validated.grid,
            extractionAlgorithm: validated.extractionAlgorithm
        )
        return try snapshot(from: registration)
    }

    static func snapshot(from registration: LocalRegisteredFloorPlan) throws -> LocalFloorPlanSnapshot {
        LocalFloorPlanSnapshot(
            registration: registration,
            maskPNGData: try LocalFloorPlanMaskRenderer.pngData(grid: registration.resolvedGrid)
        )
    }
}
