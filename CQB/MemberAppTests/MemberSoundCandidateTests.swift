import AVFoundation
import CQBCore
import XCTest
@testable import MemberApp

final class MemberSoundCandidateScoringTests: XCTestCase {
    func testScoresUseHighestWindowCoveringProbePerLabel() {
        let windows = [
            LabeledWindow(start: 0.0, end: 0.5, confidences: ["gunshot_gunfire": 0.2, "artillery_fire": 0.1]),
            LabeledWindow(start: 0.05, end: 0.55, confidences: ["gunshot_gunfire": 0.7]),
            LabeledWindow(start: 0.6, end: 1.1, confidences: ["gunshot_gunfire": 0.99]),
        ]

        let scores = MemberSoundCandidateRecorder.scores(
            at: 0.3, windows: windows, labels: ["gunshot_gunfire", "artillery_fire"])

        XCTAssertEqual(scores, ["gunshot_gunfire": 0.7, "artillery_fire": 0.1])
    }

    func testScoresAreZeroWhenNoWindowCoversProbe() {
        let scores = MemberSoundCandidateRecorder.scores(at: 2, windows: [], labels: ["gunshot_gunfire"])

        XCTAssertEqual(scores, ["gunshot_gunfire": 0])
    }

    func testOldUploadManifestReadsSoundCandidatesAsNotUploaded() throws {
        let identity = TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID())
        let old = """
        {"identity":{"sessionID":"\(identity.sessionID)","memberID":"\(identity.memberID)","recordingID":"\(identity.recordingID)"},
         "uploadedVideoChunkIndexes":[0],"uploadedTrackResult":true}
        """

        let manifest = try JSONDecoder().decode(RecordingUploadManifest.self, from: Data(old.utf8))

        XCTAssertTrue(manifest.uploadedTrackResult)
        XCTAssertFalse(manifest.uploadedSoundCandidates)
    }
}

/// 합성한 마이크 버퍼(16비트 정수, 48kHz)를 흘려 실제 감지기·분류기 경로를 확인한다.
final class MemberSoundCandidateRecorderTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let recordingStart = 1_000.0

    func testImpulseBecomesCandidateOnRecordingTimeline() async throws {
        let recorder = MemberSoundCandidateRecorder()
        recorder.begin(recordingStart: recordingStart)
        // 녹화 시작 0.5초 전부터 3초 동안 녹음. 1.5초(기록 시간)에 큰 소리.
        let samples = makeSignal(seconds: 3, impulseAt: 2.0)
        append(samples, startingAt: recordingStart - 0.5, to: recorder)

        let finished = await recorder.finish()
        let result = try XCTUnwrap(finished)

        XCTAssertEqual(result.analyzedRanges.count, 1)
        XCTAssertEqual(result.analyzedRanges[0].start, 0, accuracy: 0.001, "녹화 시작 전은 0초로 자른다")
        XCTAssertEqual(result.analyzedRanges[0].end, 2.5, accuracy: 0.01)
        let candidate = try XCTUnwrap(result.candidates.first { abs($0.time - 1.5) < 0.02 })
        XCTAssertGreaterThan(candidate.peakLevelDBFS, -6)
        XCTAssertEqual(Set(candidate.classifierScores.keys), ["gunshot_gunfire", "artillery_fire"])
        XCTAssertTrue(result.candidates.allSatisfy { result.analyzedRanges[0].contains($0.time) })
    }

    func testInterruptionSplitsAnalyzedRanges() async throws {
        let recorder = MemberSoundCandidateRecorder()
        recorder.begin(recordingStart: recordingStart)
        append(makeSignal(seconds: 2, impulseAt: 1.0), startingAt: recordingStart, to: recorder)
        recorder.interrupt()
        append(makeSignal(seconds: 2, impulseAt: 1.0), startingAt: recordingStart + 5, to: recorder)

        let finished = await recorder.finish()
        let result = try XCTUnwrap(finished)

        XCTAssertEqual(result.analyzedRanges.count, 2)
        XCTAssertEqual(result.analyzedRanges[1].start, 5, accuracy: 0.001)
        XCTAssertTrue(result.candidates.contains { abs($0.time - 1.0) < 0.02 })
        XCTAssertTrue(result.candidates.contains { abs($0.time - 6.0) < 0.02 })
        XCTAssertFalse(result.candidates.contains { $0.time > 2.1 && $0.time < 5 }, "끊긴 동안에는 후보가 없다")
    }

    func testGapWithoutInterruptionCallbackAlsoSplitsRanges() async throws {
        let recorder = MemberSoundCandidateRecorder()
        recorder.begin(recordingStart: recordingStart)
        append(makeSignal(seconds: 1, impulseAt: nil), startingAt: recordingStart, to: recorder)
        append(makeSignal(seconds: 1, impulseAt: nil), startingAt: recordingStart + 3, to: recorder)

        let finished = await recorder.finish()
        let result = try XCTUnwrap(finished)

        XCTAssertEqual(result.analyzedRanges.count, 2)
    }

    func testSoundJustBeforeSegmentEndIsKeptWithoutDecay() async throws {
        let recorder = MemberSoundCandidateRecorder()
        recorder.begin(recordingStart: recordingStart)
        // 전화로 끊기기 0.03초 전과 녹화 종료 0.03초 전에 큰 소리. 잔향을 다 재기 전에 구간이 닫힌다.
        append(makeSignal(seconds: 2, impulseAt: 1.97), startingAt: recordingStart, to: recorder)
        recorder.interrupt()
        append(makeSignal(seconds: 2, impulseAt: 1.97), startingAt: recordingStart + 5, to: recorder)

        let finished = await recorder.finish()
        let result = try XCTUnwrap(finished)

        let beforeInterruption = try XCTUnwrap(result.candidates.first { abs($0.time - 1.97) < 0.02 })
        let beforeFinish = try XCTUnwrap(result.candidates.first { abs($0.time - 6.97) < 0.02 })
        XCTAssertNil(beforeInterruption.decaySeconds, "잔향을 잴 수 없으면 nil로 남긴다")
        XCTAssertNil(beforeFinish.decaySeconds)
        XCTAssertGreaterThan(beforeFinish.peakLevelDBFS, -6)
        let document = SoundCandidateDocument(
            identity: TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID()),
            detector: MemberSoundCandidateRecorder.detector,
            analyzedRanges: result.analyzedRanges,
            candidates: result.candidates
        )
        XCTAssertNoThrow(try document.validate())
    }

    func testInterruptionWithoutGapKeepsOneValidRange() async throws {
        let recorder = MemberSoundCandidateRecorder()
        recorder.begin(recordingStart: recordingStart)
        append(makeSignal(seconds: 1, impulseAt: nil), startingAt: recordingStart, to: recorder)
        // 끊김 알림만 오고 버퍼는 끊기지 않고 이어진다. 새 구간이 앞 구간 끝에서 시작한다.
        recorder.interrupt()
        append(makeSignal(seconds: 1, impulseAt: 0.5), startingAt: recordingStart + 1, to: recorder)

        let finished = await recorder.finish()
        let result = try XCTUnwrap(finished)

        XCTAssertEqual(result.analyzedRanges.count, 1)
        XCTAssertEqual(result.analyzedRanges[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(result.analyzedRanges[0].end, 2, accuracy: 0.01)
        let document = SoundCandidateDocument(
            identity: TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID()),
            detector: MemberSoundCandidateRecorder.detector,
            analyzedRanges: result.analyzedRanges,
            candidates: result.candidates
        )
        XCTAssertNoThrow(try document.validate(), "맞닿는 구간은 합쳐 업로드 검증을 통과한다")
    }

    func testAppendingMergesTouchingOrOverlappingRanges() {
        let ranges = [SoundTimeRange(start: 0, end: 10)]

        XCTAssertEqual(
            MemberSoundCandidateRecorder.appending(SoundTimeRange(start: 10, end: 20), to: ranges),
            [SoundTimeRange(start: 0, end: 20)]
        )
        XCTAssertEqual(
            MemberSoundCandidateRecorder.appending(SoundTimeRange(start: 9.98, end: 15), to: ranges),
            [SoundTimeRange(start: 0, end: 15)]
        )
        XCTAssertEqual(
            MemberSoundCandidateRecorder.appending(SoundTimeRange(start: 12, end: 15), to: ranges),
            [SoundTimeRange(start: 0, end: 10), SoundTimeRange(start: 12, end: 15)]
        )
        XCTAssertEqual(
            MemberSoundCandidateRecorder.appending(SoundTimeRange(start: 1, end: 2), to: []),
            [SoundTimeRange(start: 1, end: 2)]
        )
    }

    func testNoMicrophoneGivesEmptyResult() async throws {
        let recorder = MemberSoundCandidateRecorder()
        recorder.begin(recordingStart: recordingStart)

        let finished = await recorder.finish()
        let result = try XCTUnwrap(finished)

        XCTAssertEqual(result, MemberSoundCandidateRecorder.Result(analyzedRanges: [], candidates: []))
    }

    func testBuffersBeforeBeginAreIgnored() async throws {
        let recorder = MemberSoundCandidateRecorder()
        append(makeSignal(seconds: 1, impulseAt: 0.5), startingAt: recordingStart, to: recorder)
        recorder.begin(recordingStart: recordingStart)

        let finished = await recorder.finish()
        let result = try XCTUnwrap(finished)

        XCTAssertTrue(result.analyzedRanges.isEmpty)
    }

    /// 낮은 잡음 위에 급격히 커졌다가 0.15초 동안 줄어드는 큰 소리를 넣는다.
    private func makeSignal(seconds: Double, impulseAt: Double?) -> [Int16] {
        let count = Int(seconds * sampleRate)
        var generator = SystemRandomNumberGenerator()
        var samples = (0..<count).map { _ in Int16.random(in: -60...60, using: &generator) }
        if let impulseAt {
            let start = Int(impulseAt * sampleRate)
            let length = Int(0.15 * sampleRate)
            for i in 0..<length where start + i < count {
                let envelope = exp(-Double(i) / (0.03 * sampleRate))
                let value = envelope * Double(Int.random(in: -30_000...30_000, using: &generator))
                samples[start + i] = Int16(clamping: Int(value))
            }
        }
        return samples
    }

    private func append(_ samples: [Int16], startingAt hostTime: Double, to recorder: MemberSoundCandidateRecorder) {
        let chunk = 4_096
        var offset = 0
        while offset < samples.count {
            let slice = Array(samples[offset..<min(offset + chunk, samples.count)])
            recorder.append(makeSampleBuffer(slice, hostTime: hostTime + Double(offset) / sampleRate))
            offset += chunk
        }
    }

    private func makeSampleBuffer(_ samples: [Int16], hostTime: Double) -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let byteCount = samples.count * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount,
                                           blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                           dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
                                           blockBufferOut: &block)
        samples.withUnsafeBytes { bytes in
            _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block!,
                                              offsetIntoDestination: 0, dataLength: byteCount)
        }
        var sampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: format!, sampleCount: samples.count,
            presentationTimeStamp: CMTime(seconds: hostTime, preferredTimescale: 48_000),
            packetDescriptions: nil, sampleBufferOut: &sampleBuffer)
        return sampleBuffer!
    }
}

@MainActor
final class MemberSoundCandidateUploadTests: XCTestCase {
    func testCandidatesUploadAfterTrackResultBeforeDone() async throws {
        let log = UploadOrderLog()
        let (store, identity, document) = try await makeStore(log: log, candidateFailure: .none)

        await store.retryUploading()

        XCTAssertTrue(store.isUploadComplete)
        let uploaded = await log.uploadedCandidates
        XCTAssertEqual(uploaded, [document])
        let events = await log.events
        XCTAssertEqual(events, ["track", "candidates", "done"])
        _ = identity
    }

    func testTransientCandidateFailureKeepsRecordingRetryable() async throws {
        let log = UploadOrderLog()
        let (store, _, document) = try await makeStore(log: log, candidateFailure: .networkOnce)

        await store.retryUploading()

        XCTAssertFalse(store.isUploadComplete, "후보를 못 올렸으면 done으로 넘기지 않는다")
        XCTAssertNotNil(store.uploadErrorMessage)
        var events = await log.events
        XCTAssertEqual(events, ["track", "candidates-failed"])

        await store.retryUploading()

        XCTAssertTrue(store.isUploadComplete)
        events = await log.events
        XCTAssertEqual(events, ["track", "candidates-failed", "candidates", "done"], "재시도는 보정 결과를 다시 올리지 않는다")
        let uploaded = await log.uploadedCandidates
        XCTAssertEqual(uploaded, [document])
    }

    func testInvalidCandidateDocumentStillCompletesRecording() async throws {
        let log = UploadOrderLog()
        let (store, _, _) = try await makeStore(log: log, candidateFailure: .invalidDocument)

        await store.retryUploading()

        XCTAssertTrue(store.isUploadComplete, "다시 올려도 실패할 문서 때문에 기록을 막지 않는다")
        XCTAssertNil(store.uploadErrorMessage)
        let events = await log.events
        XCTAssertEqual(events, ["track", "candidates-invalid", "done"])
    }

    private func makeStore(
        log: UploadOrderLog,
        candidateFailure: CandidateFailure
    ) async throws -> (MemberStore, TrackIdentity, SoundCandidateDocument) {
        let identity = TrackIdentity(sessionID: UUID(), memberID: UUID(), recordingID: UUID())
        let store = MemberStore(
            sessionRepository: SoundTestSessionRepository(),
            memberRepository: SoundTestMemberRepository(),
            floorPlanFileRepository: SoundTestFloorPlanRepository(),
            recordingRepository: SoundTestRecordingRepository(log: log),
            videoChunkRepository: SoundTestVideoRepository(),
            trackResultRepository: SoundTestTrackRepository(log: log),
            soundCandidateRepository: SoundTestCandidateRepository(log: log, failure: candidateFailure)
        )
        let fileStore = LocalRecordingFileStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("MemberSoundCandidateTests-\(UUID().uuidString)", isDirectory: true)
        )
        let files = try fileStore.makeFiles(recordingID: identity.recordingID)
        addTeardownBlock { try? FileManager.default.removeItem(at: files.directory.deletingLastPathComponent()) }
        let chunkURL = files.videoChunk(index: 0)
        try FileManager.default.createDirectory(at: chunkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("video".utf8).write(to: chunkURL)
        let correction = RouteCorrectionOutput(
            document: TrackResultDocument(
                identity: identity,
                floorPlan: FloorPlanReference(floorPlanID: UUID(), navigationSHA256: "floor-plan"),
                sourceRawSHA256: "raw",
                algorithm: TrackAlgorithmIdentity(name: "test", version: "1", settingsID: "test"),
                status: .failed, vertices: [], sampleCoverage: [], unresolvedIntervals: [],
                searchIncomplete: false, warnings: [], failureReason: .insufficientMovement
            ),
            diagnostics: nil
        )
        let document = SoundCandidateDocument(
            identity: identity,
            detector: MemberSoundCandidateRecorder.detector,
            analyzedRanges: [SoundTimeRange(start: 0, end: 10)],
            candidates: [SoundCandidate(time: 3, peakLevelDBFS: -2, decaySeconds: 0.12,
                                        classifierScores: ["gunshot_gunfire": 0.8, "artillery_fire": 0.1])]
        )
        try await store.prepareUploadFailureRaceTest(
            identity: identity, correction: correction, files: files, chunkURL: chunkURL, soundCandidates: document)
        return (store, identity, document)
    }
}

private enum CandidateFailure {
    case none
    /// 첫 시도만 네트워크 오류
    case networkOnce
    /// 계약 검증 실패. 다시 올려도 실패한다
    case invalidDocument
}

private actor UploadOrderLog {
    private(set) var events: [String] = []
    private(set) var uploadedCandidates: [SoundCandidateDocument] = []
    private(set) var candidateAttempts = 0

    func nextCandidateAttempt() -> Int {
        candidateAttempts += 1
        return candidateAttempts
    }

    func add(_ event: String) { events.append(event) }
    func addCandidates(_ document: SoundCandidateDocument) {
        uploadedCandidates.append(document)
        events.append("candidates")
    }
}

private struct SoundTestCandidateRepository: SoundCandidateRepository {
    let log: UploadOrderLog
    let failure: CandidateFailure

    func upload(_ document: SoundCandidateDocument) async throws {
        let attempt = await log.nextCandidateAttempt()
        switch failure {
        case .networkOnce where attempt == 1:
            await log.add("candidates-failed")
            throw URLError(.notConnectedToInternet)
        case .invalidDocument:
            await log.add("candidates-invalid")
            throw SoundCandidateValidationError.invalidCandidates
        default:
            await log.addCandidates(document)
        }
    }

    func download(_ identity: TrackIdentity) async throws -> SoundCandidateDocument { throw RepositoryError.notFound }
}

private struct SoundTestTrackRepository: TrackResultRepository {
    let log: UploadOrderLog
    func upload(_ result: TrackResultDocument) async throws { await log.add("track") }
    func download(_ identity: TrackIdentity) async throws -> TrackResultDocument { throw RepositoryError.notFound }
}

private struct SoundTestRecordingRepository: RecordingRepository {
    let log: UploadOrderLog
    func startRecording(_ recording: Recording) async throws {}
    func updateRecording(_ recording: Recording) async throws {
        if recording.state == .done { await log.add("done") }
    }
    func observeRecordings(sessionID: UUID) -> AsyncThrowingStream<[Recording], Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct SoundTestVideoRepository: VideoChunkRepository {
    func upload(fileURL: URL, identity: TrackIdentity, index: Int) async throws {}
    func downloadVideo(_ identity: TrackIdentity, chunkCount: Int, to directory: URL) async throws -> [URL] {
        throw RepositoryError.notFound
    }
    func deleteVideo(_ identity: TrackIdentity, chunkCount: Int) async throws {}
}

private struct SoundTestSessionRepository: SessionRepository {
    func createSession(_ session: Session) async throws {}
    func session(forPin pin: String) async throws -> Session { throw RepositoryError.notFound }
    func updateStatus(of session: Session, to status: SessionStatus) async throws {}
    func observeSession(id: UUID) -> AsyncThrowingStream<Session, Error> { AsyncThrowingStream { $0.finish() } }
}

private struct SoundTestMemberRepository: MemberRepository {
    func join(_ member: Member, pin: String) async throws {}
    func updateReadiness(of member: Member) async throws {}
    func observeMembers(sessionID: UUID) -> AsyncThrowingStream<[Member], Error> { AsyncThrowingStream { $0.finish() } }
}

private struct SoundTestFloorPlanRepository: FloorPlanFileRepository {
    func upload(_ files: FloorPlanFiles, for reference: FloorPlanReference) async throws {}
    func download(_ reference: FloorPlanReference) async throws -> FloorPlanFiles { throw RepositoryError.notFound }
}
