import CQBCore
import CryptoKit
import Foundation

/// 검증을 통과한 도면 파일을 메모리와 앱 Caches 영역에서 재사용한다.
actor CachedFloorPlanFileRepository: FloorPlanFileRepository {
    struct Configuration: Sendable {
        static let defaultDiskLimit = 250 * 1_024 * 1_024
        static let defaultMemoryLimit = 40 * 1_024 * 1_024

        let directory: URL
        let diskLimitBytes: Int
        let memoryLimitBytes: Int

        init(
            directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FloorPlanFiles", isDirectory: true),
            diskLimitBytes: Int = defaultDiskLimit,
            memoryLimitBytes: Int = defaultMemoryLimit
        ) {
            self.directory = directory
            self.diskLimitBytes = max(0, diskLimitBytes)
            self.memoryLimitBytes = max(0, memoryLimitBytes)
        }
    }

    private struct MemoryEntry: Sendable {
        let files: FloorPlanFiles
        let byteCount: Int
        let access: UInt64
    }

    private struct InFlight: Sendable {
        let id: UUID
        let task: Task<FloorPlanFiles, Error>
    }

    private enum FileName {
        static let image = "original.png"
        static let navigationMap = "navigation-map.json"
        static let mask = "resolved-mask.bin"
        static let stagingPrefix = ".staging-"
    }

    private let remote: any FloorPlanFileRepository
    private let configuration: Configuration
    private let fileManager: FileManager
    private var memory: [String: MemoryEntry] = [:]
    private var inFlight: [String: InFlight] = [:]
    private var accessCounter: UInt64 = 0

    init(
        remote: any FloorPlanFileRepository,
        configuration: Configuration = Configuration(),
        fileManager: FileManager = .default
    ) {
        self.remote = remote
        self.configuration = configuration
        self.fileManager = fileManager
    }

    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {
        _ = try LocalFloorPlanFileValidator.validate(files: files, reference: reference)
        try await remote.upload(files, for: reference)
        storeInMemory(files, key: Self.cacheKey(for: reference))
        try? storeOnDisk(files, reference: reference)
    }

    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles {
        let key = Self.cacheKey(for: reference)
        if let files = loadFromMemory(key: key) {
            return files
        }
        if let files = loadFromDisk(reference: reference, key: key) {
            storeInMemory(files, key: key)
            return files
        }

        let request: InFlight
        if let existing = inFlight[key] {
            request = existing
        } else {
            let remote = remote
            let task = Task.detached {
                let files = try await remote.download(reference)
                _ = try LocalFloorPlanFileValidator.validate(files: files, reference: reference)
                return files
            }
            request = InFlight(id: UUID(), task: task)
            inFlight[key] = request
        }

        do {
            let files = try await request.task.value
            clearInFlight(key: key, id: request.id)
            if let cached = loadFromMemory(key: key) {
                try Task.checkCancellation()
                return cached
            }
            storeInMemory(files, key: key)
            try? storeOnDisk(files, reference: reference)
            try Task.checkCancellation()
            return files
        } catch {
            clearInFlight(key: key, id: request.id)
            throw error
        }
    }

    private func clearInFlight(key: String, id: UUID) {
        guard inFlight[key]?.id == id else { return }
        inFlight[key] = nil
    }

    private func loadFromMemory(key: String) -> FloorPlanFiles? {
        guard let entry = memory[key] else { return nil }
        accessCounter &+= 1
        memory[key] = MemoryEntry(files: entry.files, byteCount: entry.byteCount, access: accessCounter)
        return entry.files
    }

    private func storeInMemory(_ files: FloorPlanFiles, key: String) {
        accessCounter &+= 1
        let byteCount = Self.byteCount(of: files)
        memory[key] = MemoryEntry(files: files, byteCount: byteCount, access: accessCounter)

        var total = memory.values.reduce(0) { $0 + $1.byteCount }
        while total > configuration.memoryLimitBytes,
              let oldest = memory.min(by: { $0.value.access < $1.value.access }) {
            memory.removeValue(forKey: oldest.key)
            total -= oldest.value.byteCount
        }
    }

    private func loadFromDisk(reference: FloorPlanReference, key: String) -> FloorPlanFiles? {
        try? removeAbandonedStagingDirectories()
        let directory = configuration.directory.appendingPathComponent(key, isDirectory: true)
        do {
            let files = try Self.readFiles(at: directory)
            _ = try LocalFloorPlanFileValidator.validate(files: files, reference: reference)
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: directory.path)
            return files
        } catch {
            try? fileManager.removeItem(at: directory)
            return nil
        }
    }

    private func storeOnDisk(_ files: FloorPlanFiles, reference: FloorPlanReference) throws {
        let root = configuration.directory
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try removeAbandonedStagingDirectories()

        let key = Self.cacheKey(for: reference)
        let destination = root.appendingPathComponent(key, isDirectory: true)
        let staging = root.appendingPathComponent("\(FileName.stagingPrefix)\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        try files.imagePNG.write(to: staging.appendingPathComponent(FileName.image), options: .atomic)
        try files.navigationMapJSON.write(to: staging.appendingPathComponent(FileName.navigationMap), options: .atomic)
        try files.resolvedMask.write(to: staging.appendingPathComponent(FileName.mask), options: .atomic)
        _ = try LocalFloorPlanFileValidator.validate(
            files: Self.readFiles(at: staging),
            reference: reference
        )

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        try pruneDiskCache(keeping: key)
    }

    private func pruneDiskCache(keeping currentKey: String) throws {
        let root = configuration.directory
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .totalFileAllocatedSizeKey]
        let directories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ).compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory == true else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Self.directorySize(at: url))
        }

        var total = directories.reduce(0) { $0 + $1.size }
        for entry in directories.sorted(by: { $0.date < $1.date })
        where total > configuration.diskLimitBytes && entry.url.lastPathComponent != currentKey {
            do {
                try fileManager.removeItem(at: entry.url)
                total -= entry.size
            } catch {
                continue
            }
        }

        if total > configuration.diskLimitBytes,
           let current = directories.first(where: { $0.url.lastPathComponent == currentKey }) {
            try? fileManager.removeItem(at: current.url)
        }
    }

    private func removeAbandonedStagingDirectories() throws {
        let root = configuration.directory
        guard fileManager.fileExists(atPath: root.path) else { return }
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for child in children where child.lastPathComponent.hasPrefix(FileName.stagingPrefix) {
            try fileManager.removeItem(at: child)
        }
    }

    private static func readFiles(at directory: URL) throws -> FloorPlanFiles {
        FloorPlanFiles(
            imagePNG: try Data(contentsOf: directory.appendingPathComponent(FileName.image)),
            navigationMapJSON: try Data(contentsOf: directory.appendingPathComponent(FileName.navigationMap)),
            resolvedMask: try Data(contentsOf: directory.appendingPathComponent(FileName.mask))
        )
    }

    static func cacheKey(for reference: FloorPlanReference) -> String {
        let source = Data("\(reference.floorPlanID.uuidString.lowercased())|\(reference.navigationSHA256.lowercased())".utf8)
        return "\(reference.floorPlanID.uuidString.lowercased())-\(sha256(source))"
    }

    private static func byteCount(of files: FloorPlanFiles) -> Int {
        files.imagePNG.count + files.navigationMapJSON.count + files.resolvedMask.count
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func directorySize(at directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        return enumerator.compactMap { item -> Int? in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
                return nil
            }
            return values.totalFileAllocatedSize ?? values.fileAllocatedSize
        }.reduce(0, +)
    }
}
