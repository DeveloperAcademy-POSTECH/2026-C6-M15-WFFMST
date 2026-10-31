import CQBCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct FloorPlanListPreviewSnapshot: Sendable {
    let imagePNGData: Data
    let maskPNGData: Data
    let maskScale: Double
}

nonisolated protocol FloorPlanListPreviewLoading: Sendable {
    func load(_ floorPlan: InstructorFloorPlan) async throws -> FloorPlanListPreviewSnapshot
}

/// 목록에서 사용할 축소 도면과 최종 마스크를 reference 단위로 한 번만 준비한다.
actor LocalFloorPlanListPreviewLoader: FloorPlanListPreviewLoading {
    private struct InFlight: Sendable {
        let id: UUID
        let task: Task<FloorPlanListPreviewSnapshot, Error>
    }

    private let repository: any FloorPlanFileRepository
    private let maximumPixelSize: Int
    private var memory: [String: FloorPlanListPreviewSnapshot] = [:]
    private var inFlight: [String: InFlight] = [:]

    init(repository: any FloorPlanFileRepository, maximumPixelSize: Int = 1_600) {
        self.repository = repository
        self.maximumPixelSize = max(1, maximumPixelSize)
    }

    func load(_ floorPlan: InstructorFloorPlan) async throws -> FloorPlanListPreviewSnapshot {
        let key = CachedFloorPlanFileRepository.cacheKey(for: floorPlan.reference)
        if let cached = memory[key] { return cached }

        let request: InFlight
        if let existing = inFlight[key] {
            request = existing
        } else {
            let repository = repository
            let maximumPixelSize = maximumPixelSize
            let task = Task.detached(priority: .userInitiated) {
                let imagePNG: Data
                let grid: LocalObstacleGrid
                if let registration = floorPlan.registeredPlan {
                    imagePNG = registration.image.pngData
                    grid = registration.resolvedGrid
                } else {
                    let files = try await repository.download(floorPlan.reference)
                    let validated = try LocalFloorPlanFileValidator.validate(
                        files: files,
                        reference: floorPlan.reference
                    )
                    imagePNG = files.imagePNG
                    grid = validated.grid
                }
                return try LocalFloorPlanListPreviewRenderer.render(
                    imagePNG: imagePNG,
                    grid: grid,
                    maximumPixelSize: maximumPixelSize
                )
            }
            request = InFlight(id: UUID(), task: task)
            inFlight[key] = request
        }

        do {
            let snapshot = try await request.task.value
            clearInFlight(key: key, id: request.id)
            memory[key] = snapshot
            try Task.checkCancellation()
            return snapshot
        } catch {
            clearInFlight(key: key, id: request.id)
            throw error
        }
    }

    private func clearInFlight(key: String, id: UUID) {
        guard inFlight[key]?.id == id else { return }
        inFlight[key] = nil
    }
}

nonisolated enum LocalFloorPlanListPreviewRenderer {
    static func render(
        imagePNG: Data,
        grid: LocalObstacleGrid,
        maximumPixelSize: Int
    ) throws -> FloorPlanListPreviewSnapshot {
        try Task.checkCancellation()
        let imagePNGData = try thumbnailPNGData(from: imagePNG, maximumPixelSize: maximumPixelSize)
        try Task.checkCancellation()
        return FloorPlanListPreviewSnapshot(
            imagePNGData: imagePNGData,
            maskPNGData: try LocalFloorPlanMaskRenderer.pngData(grid: grid),
            maskScale: 1 / Double(grid.cellSizePixels)
        )
    }

    private static func thumbnailPNGData(from data: Data, maximumPixelSize: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw LocalFloorPlanError.invalid("목록용 도면 이미지를 읽지 못했습니다.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LocalFloorPlanError.invalid("목록용 도면 이미지를 생성하지 못했습니다.")
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw LocalFloorPlanError.invalid("목록용 도면 이미지 형식을 생성하지 못했습니다.")
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw LocalFloorPlanError.invalid("목록용 도면 이미지를 저장하지 못했습니다.")
        }
        return output as Data
    }
}
