import Foundation
import XCTest
@testable import MemberApp

@MainActor
final class MemberDemoCompletionTests: XCTestCase {
    func testDemoUploadProgressCompletesLocallyInOrder() async {
        let simulator = MemberDemoUploadSimulator(stepDelay: .zero)
        var received: [MemberDemoUploadStep] = []

        await simulator.run { step in received.append(step) }

        XCTAssertEqual(received, MemberDemoUploadSimulator.steps)
        XCTAssertEqual(received.last?.progress, 1)
        XCTAssertTrue(zip(received, received.dropFirst()).allSatisfy { $0.progress < $1.progress })
        XCTAssertTrue(received.last?.message.contains("서버로 전송하지 않았습니다") == true)
    }

    func testDemoCleanupPreservesOperationalRecordings() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("MemberDemoCompletionTests-(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: base) }

        let operationalStore = LocalRecordingFileStore(baseDirectory: base)
        let demoStore = LocalRecordingFileStore(scope: .demo(runID: UUID()), baseDirectory: base)
        let otherDemoStore = LocalRecordingFileStore(scope: .demo(runID: UUID()), baseDirectory: base)
        let operationalFiles = try operationalStore.makeFiles(recordingID: UUID())
        let demoFiles = try demoStore.makeFiles(recordingID: UUID())
        let otherDemoFiles = try otherDemoStore.makeFiles(recordingID: UUID())
        try Data("operational".utf8).write(to: operationalFiles.raw)
        try Data("demo".utf8).write(to: demoFiles.raw)
        try Data("other-demo".utf8).write(to: otherDemoFiles.raw)

        try demoStore.removeDemoRun()

        XCTAssertTrue(fileManager.fileExists(atPath: operationalFiles.raw.path))
        XCTAssertFalse(fileManager.fileExists(atPath: demoFiles.directory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: otherDemoFiles.raw.path))
        XCTAssertThrowsError(try operationalStore.removeDemoRun())
    }
}
