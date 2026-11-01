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
    static let defaultMemoryLimit = 32 * 1_024 * 1_024

    private struct MemoryEntry: Sendable {
        let snapshot: FloorPlanListPreviewSnapshot
        let byteCount: Int
        let access: UInt64
    }

    private struct InFlight: Sendable {
        let id: UUID
        let task: Task<FloorPlanListPreviewSnapshot, Error>
        var waiters: Set<UUID>
    }

    private let repository: any FloorPlanFileRepository
    private let maximumPixelSize: Int
    private let memoryLimitBytes: Int
    private var memory: [String: MemoryEntry] = [:]
    private var inFlight: [String: InFlight] = [:]
    private var accessCounter: UInt64 = 0

    init(
        repository: any FloorPlanFileRepository,
        maximumPixelSize: Int = 1_600,
        memoryLimitBytes: Int = defaultMemoryLimit
    ) {
        self.repository = repository
        self.maximumPixelSize = max(1, maximumPixelSize)
        self.memoryLimitBytes = max(0, memoryLimitBytes)
    }

    func load(_ floorPlan: InstructorFloorPlan) async throws -> FloorPlanListPreviewSnapshot {
        let key = CachedFloorPlanFileRepository.cacheKey(for: floorPlan.reference)
        if let cached = loadFromMemory(key: key) { return cached }

        let waiterID = UUID()
        let request: InFlight
        if var existing = inFlight[key] {
            existing.waiters.insert(waiterID)
            inFlight[key] = existing
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
            request = InFlight(id: UUID(), task: task, waiters: [waiterID])
            inFlight[key] = request
        }

        return try await withTaskCancellationHandler {
            do {
                let snapshot = try await request.task.value
                try Task.checkCancellation()
                finishWaiter(key: key, requestID: request.id, waiterID: waiterID)
                storeInMemory(snapshot, key: key)
                return snapshot
            } catch {
                finishWaiter(key: key, requestID: request.id, waiterID: waiterID)
                throw error
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(
                    key: key,
                    requestID: request.id,
                    waiterID: waiterID
                )
            }
        }
    }

    private func finishWaiter(key: String, requestID: UUID, waiterID: UUID) {
        guard var request = inFlight[key], request.id == requestID,
              request.waiters.remove(waiterID) != nil else { return }
        if request.waiters.isEmpty {
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }

    private func cancelWaiter(key: String, requestID: UUID, waiterID: UUID) {
        guard var request = inFlight[key], request.id == requestID,
              request.waiters.remove(waiterID) != nil else { return }
        if request.waiters.isEmpty {
            inFlight[key] = nil
            request.task.cancel()
        } else {
            inFlight[key] = request
        }
    }

    private func loadFromMemory(key: String) -> FloorPlanListPreviewSnapshot? {
        guard let entry = memory[key] else { return nil }
        accessCounter &+= 1
        memory[key] = MemoryEntry(
            snapshot: entry.snapshot,
            byteCount: entry.byteCount,
            access: accessCounter
        )
        return entry.snapshot
    }

    private func storeInMemory(_ snapshot: FloorPlanListPreviewSnapshot, key: String) {
        accessCounter &+= 1
        let byteCount = snapshot.imagePNGData.count + snapshot.maskPNGData.count
        memory[key] = MemoryEntry(snapshot: snapshot, byteCount: byteCount, access: accessCounter)

        var total = memory.values.reduce(0) { $0 + $1.byteCount }
        while total > memoryLimitBytes,
              let oldest = memory.min(by: { $0.value.access < $1.value.access }) {
            memory.removeValue(forKey: oldest.key)
            total -= oldest.value.byteCount
        }
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
