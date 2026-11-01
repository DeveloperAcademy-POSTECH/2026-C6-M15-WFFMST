import AVFoundation
import XCTest
@testable import MemberApp

@MainActor
final class RecordingAudioTests: XCTestCase {
    func testAudioWarningClearsOnFirstNormalSampleAfterInterruption() async throws {
        let service = ARRecordingService()
        defer { service.stop() }
        let status = service.startAudioStatusUpdates()
        var delivery = MemberAudioSampleDelivery(onSampleBuffer: { _ in },
            onInterruption: { status.yield(true) }, onResume: { status.yield(false) })
        let initial = try audioBuffer(start: 1000, count: 1024, rate: 48_000)
        XCTAssertNotNil(delivery.append(initial))
        XCTAssertNil(service.audioWarning)

        delivery.interrupt()
        await waitForAudioWarning(service, interrupted: true)
        XCTAssertEqual(service.audioWarning, "소리 녹음이 중단되었습니다. 영상과 동선은 계속 기록합니다.")
        XCTAssertTrue(delivery.isInterrupted)

        // Replayed/out-of-order samples must not announce recovery.
        XCTAssertNil(delivery.append(initial))
        XCTAssertNil(delivery.append(try audioBuffer(start: 999, count: 1024, rate: 48_000)))
        XCTAssertTrue(delivery.isInterrupted)
        XCTAssertNotNil(service.audioWarning)

        XCTAssertNotNil(delivery.append(try audioBuffer(start: 1001, count: 1024, rate: 48_000)))
        await waitForAudioWarning(service, interrupted: false)
        XCTAssertFalse(delivery.isInterrupted)
        XCTAssertNil(service.audioWarning)

        // A second interruption must independently display and clear the warning.
        delivery.interrupt()
        await waitForAudioWarning(service, interrupted: true)
        delivery.append(try audioBuffer(start: 1002, count: 1024, rate: 48_000))
        await waitForAudioWarning(service, interrupted: false)
    }

    func testResumeCallbackOccursOncePerInterruptionAndNeverOnInitialSample() throws {
        let events = AudioResumeCounter()
        var delivery = MemberAudioSampleDelivery(onSampleBuffer: { _ in }, onInterruption: {},
                                                 onResume: { events.increment() })
        delivery.append(try audioBuffer(start: 1000, count: 1024, rate: 48_000))
        XCTAssertEqual(events.value, 0)
        delivery.interrupt()
        delivery.append(try audioBuffer(start: 1001, count: 1024, rate: 48_000))
        delivery.append(try audioBuffer(start: 1002, count: 1024, rate: 48_000))
        XCTAssertEqual(events.value, 1)
        delivery.interrupt()
        delivery.append(try audioBuffer(start: 1003, count: 1024, rate: 48_000))
        XCTAssertEqual(events.value, 2)
    }

    func testStoppedRecordingResumeCannotClearNextRecordingsWarning() async throws {
        let service = ARRecordingService()
        defer { service.stop() }
        let oldStatus = service.startAudioStatusUpdates()
        var oldDelivery = MemberAudioSampleDelivery(onSampleBuffer: { _ in },
            onInterruption: { oldStatus.yield(true) }, onResume: { oldStatus.yield(false) })
        oldDelivery.interrupt()
        await waitForAudioWarning(service, interrupted: true)
        service.stop()
        XCTAssertNil(service.audioWarning)

        let newStatus = service.startAudioStatusUpdates()
        newStatus.yield(true)
        await waitForAudioWarning(service, interrupted: true)
        // This invokes the real onResume callback, but its old consumer is cancelled.
        oldDelivery.append(try audioBuffer(start: 1001, count: 1024, rate: 48_000))
        XCTAssertFalse(oldDelivery.isInterrupted)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNotNil(service.audioWarning)
        newStatus.yield(false)
        await waitForAudioWarning(service, interrupted: false)
    }

    private func waitForAudioWarning(_ service: ARRecordingService, interrupted: Bool,
                                     file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if (service.audioWarning != nil) == interrupted { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Audio interruption warning did not update", file: file, line: line)
    }

    func testSplittingAtFractionalBoundaryPreservesEveryPCMSample() throws {
        for rate in [44_100.0, 48_000.0] {
            let original = try audioBuffer(start: 1000, count: 4096, rate: rate)
            let boundary = 1000 + 1500.25 / rate
            let left = try XCTUnwrap(RecordingAudioSamples.slice(original, from: 1000, to: boundary))
            let right = try XCTUnwrap(RecordingAudioSamples.slice(original, from: boundary,
                                                                 to: RecordingAudioSamples.endTime(of: original)))
            XCTAssertEqual(CMSampleBufferGetNumSamples(left), 1501)
            XCTAssertEqual(CMSampleBufferGetNumSamples(left) + CMSampleBufferGetNumSamples(right), 4096)
            XCTAssertEqual(try bytes(left) + bytes(right), try bytes(original))
            XCTAssertEqual(RecordingAudioSamples.sampleRate(of: right), rate)
            XCTAssertEqual(RecordingAudioSamples.endTime(of: left),
                           CMSampleBufferGetPresentationTimeStamp(right).seconds, accuracy: 0.0000001)
        }
    }

    func testRetimingPreservesDurationAndUsesChunkOrigin() throws {
        let original = try audioBuffer(start: 1000.125, count: 4800, rate: 48_000)
        let shifted = try XCTUnwrap(RecordingAudioSamples.retime(original) {
            CMTimeSubtract($0, CMTime(seconds: 1000, preferredTimescale: 1_000_000_000))
        })
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(shifted).seconds, 0.125, accuracy: 0.0000001)
        XCTAssertEqual(RecordingAudioSamples.endTime(of: shifted), 0.225, accuracy: 0.0000001)
        XCTAssertEqual(try bytes(original), try bytes(shifted))
    }

    func testLateBufferCrossingChunkBoundaryProducesSynchronizedAACInBothChunks() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ARFrameVideoWriter(chunkDuration: 0.2)
        let frame = try pixelBuffer()
        try writer.start(firstFrame: frame, timestamp: 1000, outputDirectory: directory,
                         orientation: .landscapeRight, audioSampleRate: 48_000) { _, _ in }
        // Audio may lead the latest video frame; it must wait until its chunk is known.
        writer.append(audioSampleBuffer: try audioBuffer(start: 1000, count: 4800, rate: 48_000))
        for offset in [0.05, 0.10, 0.15, 0.20] { await append(frame, at: 1000 + offset, to: writer) }
        // This buffer arrives after the .2-second video boundary and straddles it.
        writer.append(audioSampleBuffer: try audioBuffer(start: 1000.1, count: 9600, rate: 48_000))
        for offset in [0.25, 0.30, 0.35] { await append(frame, at: 1000 + offset, to: writer) }
        writer.append(audioSampleBuffer: try audioBuffer(start: 1000.3, count: 4800, rate: 48_000))
        let urls = try await finish(writer, at: 1000.4)
        XCTAssertEqual(urls.count, 2)
        for url in urls {
            let asset = AVURLAsset(url: url)
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(video.count, 1)
            XCTAssertEqual(audio.count, 1)
            let track = try XCTUnwrap(audio.first)
            let formats = try await track.load(.formatDescriptions)
            let format = try XCTUnwrap(formats.first)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kAudioFormatMPEG4AAC)
            let stream = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(format))
            XCTAssertEqual(stream.pointee.mChannelsPerFrame, 1)
            XCTAssertEqual(stream.pointee.mSampleRate, 48_000)
            let range = try await track.load(.timeRange)
            XCTAssertLessThanOrEqual(abs(range.start.seconds), 0.025)
            XCTAssertGreaterThan(range.duration.seconds, 0.17)
            XCTAssertLessThan(range.duration.seconds, 0.23)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, 0.2, accuracy: 0.025)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertLessThanOrEqual(size, ARFrameVideoWriter.maximumChunkBytes)
        }
    }

    func testContinuousRecordingUsesAACLCAndTargetBitrateAtDeviceSampleRate() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ARFrameVideoWriter()
        let frame = try pixelBuffer()
        try writer.start(firstFrame: frame, timestamp: 100, outputDirectory: directory,
                         orientation: .landscapeRight, audioSampleRate: 48_000) { _, _ in }
        writer.append(audioSampleBuffer: try audioBuffer(start: 100, count: 96_000, rate: 48_000))
        for index in 1..<60 { await append(frame, at: 100 + Double(index) / 30, to: writer) }
        let urls = try await finish(writer, at: 102)
        let tracks = try await AVURLAsset(url: try XCTUnwrap(urls.first)).loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let formats = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)
        let stream = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(format))
        XCTAssertEqual(stream.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(try audioObjectType(in: Data(contentsOf: urls[0])), 2, "MP4 AudioSpecificConfig must identify AAC-LC.")
        XCTAssertEqual(stream.pointee.mSampleRate, 48_000)
        XCTAssertEqual(stream.pointee.mChannelsPerFrame, 1)
        let bitrate = try await track.load(.estimatedDataRate)
        XCTAssertGreaterThan(bitrate, 48_000)
        XCTAssertLessThan(bitrate, 80_000)
    }

    func testThirtySecondChunksPreserveAudioWithCaptureTimestampJitter() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ARFrameVideoWriter()
        let frame = try pixelBuffer()
        let origin = 1000.0
        let rate = 48_000.0
        try writer.start(firstFrame: frame, timestamp: origin, outputDirectory: directory,
                         orientation: .landscapeRight, audioSampleRate: rate) { _, _ in }
        var lastFrame = 0
        // Real capture delivers many small buffers. Converting the device clock to host
        // time may put their timestamps a few microseconds on either side of the PCM grid.
        for index in 0..<1500 {
            let jitter = [0.0, 0.000004, 0.000002][index % 3]
            writer.append(audioSampleBuffer: try audioBuffer(
                start: origin + Double(index * 1024) / rate + jitter,
                count: 1024, rate: rate, firstSample: index * 1024))
            let frameIndex = Int(Double((index + 1) * 1024) / rate * 30)
            if frameIndex > lastFrame {
                await append(frame, at: origin + Double(frameIndex) / 30, to: writer)
                lastFrame = frameIndex
            }
            await writer.waitForPendingWrites()
        }
        let urls = try await finish(writer, at: origin + 32)
        XCTAssertEqual(urls.count, 2)
        for (index, url) in urls.enumerated() {
            let expectedDuration = index == 0 ? 30.0 : 2.0
            let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
            let track = try XCTUnwrap(tracks.first)
            let range = try await track.load(.timeRange)
            XCTAssertEqual(range.duration.seconds, expectedDuration, accuracy: 0.05,
                           "A full video chunk must retain the same amount of microphone audio.")
            let decoded = try await decodedAudio(url)
            XCTAssertEqual(Double(decoded.samples) / rate, expectedDuration, accuracy: 0.05)
            XCTAssertEqual(decoded.frequency, 1000, accuracy: 5, "The original tone must retain its playback pitch.")
        }
    }

    func testDuplicateAndOutOfOrderBuffersDoNotDuplicateAudioSamples() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ARFrameVideoWriter()
        let frame = try pixelBuffer()
        try writer.start(firstFrame: frame, timestamp: 100, outputDirectory: directory,
                         orientation: .landscapeRight, audioSampleRate: 48_000) { _, _ in }
        let first = try audioBuffer(start: 100, count: 24_000, rate: 48_000)
        let second = try audioBuffer(start: 100.5, count: 24_000, rate: 48_000, firstSample: 24_000)
        writer.append(audioSampleBuffer: first)
        writer.append(audioSampleBuffer: second)
        writer.append(audioSampleBuffer: second) // duplicate callback
        writer.append(audioSampleBuffer: first) // stale callback
        for index in 1..<30 { await append(frame, at: 100 + Double(index) / 30, to: writer) }
        let urls = try await finish(writer, at: 101)
        let decoded = try await decodedAudio(try XCTUnwrap(urls.first))
        XCTAssertEqual(Double(decoded.samples) / 48_000, 1, accuracy: 0.05)
        XCTAssertEqual(decoded.frequency, 1000, accuracy: 5)
    }

    func testUnavailableMicrophoneStillProducesValidVideoOnlyRecording() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ARFrameVideoWriter()
        let frame = try pixelBuffer()
        try writer.start(firstFrame: frame, timestamp: 10, outputDirectory: directory,
                         orientation: .landscapeRight) { _, _ in }
        await append(frame, at: 10.05, to: writer)
        let urls = try await finish(writer, at: 10.1)
        let asset = AVURLAsset(url: try XCTUnwrap(urls.first))
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(video.count, 1)
        XCTAssertTrue(audio.isEmpty)
    }

    func testAudioInterruptionKeepsVideoChunkingAndCanResumeWithGap() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ARFrameVideoWriter(chunkDuration: 0.2)
        let frame = try pixelBuffer()
        try writer.start(firstFrame: frame, timestamp: 20, outputDirectory: directory,
                         orientation: .landscapeRight, audioSampleRate: 44_100) { _, _ in }
        writer.append(audioSampleBuffer: try audioBuffer(start: 20, count: 4410, rate: 44_100))
        await append(frame, at: 20.1, to: writer)
        writer.markAudioInterrupted()
        for offset in [0.2, 0.3, 0.4, 0.5] { await append(frame, at: 20 + offset, to: writer) }
        writer.append(audioSampleBuffer: try audioBuffer(start: 20.5, count: 4410, rate: 44_100))
        let urls = try await finish(writer, at: 20.6)
        XCTAssertEqual(urls.count, 3)
        for url in urls {
            let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
            XCTAssertEqual(tracks.count, 1)
        }
        let resumed = try await AVURLAsset(url: try XCTUnwrap(urls.last)).loadTracks(withMediaType: .audio)
        XCTAssertEqual(resumed.count, 1)
    }

    func testCancellationDoesNotPublishIncompleteChunkAndAllowsRetry() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let callbacks = CallbackCounter()
        let writer = ARFrameVideoWriter()
        let frame = try pixelBuffer()
        try writer.start(firstFrame: frame, timestamp: 1, outputDirectory: directory,
                         orientation: .landscapeRight) { _, _ in callbacks.increment() }
        writer.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("chunk_0000.mp4").path))
        XCTAssertEqual(callbacks.value, 0)
        try writer.start(firstFrame: frame, timestamp: 2, outputDirectory: directory,
                         orientation: .landscapeRight) { _, _ in callbacks.increment() }
        await append(frame, at: 2.05, to: writer)
        _ = try await finish(writer, at: 2.1)
        XCTAssertEqual(callbacks.value, 1)
    }

    private func append(_ frame: CVPixelBuffer, at time: Double, to writer: ARFrameVideoWriter) async {
        writer.append(pixelBuffer: frame, timestamp: time)
        await writer.waitForPendingWrites()
    }

    private func finish(_ writer: ARFrameVideoWriter, at time: Double) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            writer.finish(at: time) { continuation.resume(with: $0) }
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RecordingAudioTests-\(UUID().uuidString)")
    }

    private func pixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA,
                                          [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let result = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(result, [])
        memset(try XCTUnwrap(CVPixelBufferGetBaseAddress(result)), 0, CVPixelBufferGetDataSize(result))
        CVPixelBufferUnlockBaseAddress(result, [])
        return result
    }

    private func audioBuffer(start: Double, count: Int, rate: Double, firstSample: Int = 0) throws -> CMSampleBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate,
                                                channels: 1, interleaved: true))
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: count * 2, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: count * 2, flags: 0, blockBufferOut: &block), noErr)
        let data = try XCTUnwrap(block)
        let values = (0..<count).map { Int16(sin(Double(firstSample + $0) * 2 * .pi * 1000 / rate) * 10_000) }
        values.withUnsafeBytes { raw in
            XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: data,
                                                         offsetIntoDestination: 0, dataLength: raw.count), noErr)
        }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(rate)),
            presentationTimeStamp: CMTime(seconds: start, preferredTimescale: 1_000_000_000), decodeTimeStamp: .invalid)
        var size = 2
        var result: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
            formatDescription: format.formatDescription, sampleCount: count, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &result), noErr)
        return try XCTUnwrap(result)
    }

    private func decodedAudio(_ url: URL) async throws -> (samples: Int, frequency: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var sampleCount = 0
        var crossings = 0
        var previous: Int16 = 0
        while let buffer = output.copyNextSampleBuffer() {
            let data = try bytes(buffer)
            data.withUnsafeBytes { raw in
                for value in raw.bindMemory(to: Int16.self) {
                    if previous < 0, value >= 0 { crossings += 1 }
                    previous = value
                }
            }
            sampleCount += CMSampleBufferGetNumSamples(buffer)
        }
        XCTAssertEqual(reader.status, .completed)
        return (sampleCount, Double(crossings) / (Double(sampleCount) / 48_000))
    }

    /// Read the AAC profile from MP4's esds descriptor; ASBD flags may legitimately be 0.
    private func audioObjectType(in data: Data) throws -> UInt8 {
        let atom = try XCTUnwrap(data.range(of: Data("esds".utf8)))
        var cursor = atom.upperBound + 4 // full-box version and flags
        func descriptor() throws -> (UInt8, Range<Int>) {
            guard cursor < data.count else { throw CocoaError(.fileReadCorruptFile) }
            let tag = data[cursor]
            cursor += 1
            var size = 0
            for _ in 0..<4 {
                guard cursor < data.count else { throw CocoaError(.fileReadCorruptFile) }
                let byte = data[cursor]
                cursor += 1
                size = (size << 7) | Int(byte & 0x7f)
                if byte & 0x80 == 0 {
                    guard cursor + size <= data.count else { throw CocoaError(.fileReadCorruptFile) }
                    return (tag, cursor..<(cursor + size))
                }
            }
            throw CocoaError(.fileReadCorruptFile)
        }
        let es = try descriptor()
        XCTAssertEqual(es.0, 3)
        guard es.1.count >= 3 else { throw CocoaError(.fileReadCorruptFile) }
        let flags = data[es.1.lowerBound + 2]
        cursor = es.1.lowerBound + 3
        if flags & 0x80 != 0 { cursor += 2 }
        if flags & 0x40 != 0 { cursor += 1 + Int(data[cursor]) }
        if flags & 0x20 != 0 { cursor += 2 }
        let decoder = try descriptor()
        XCTAssertEqual(decoder.0, 4)
        cursor = decoder.1.lowerBound + 13
        let config = try descriptor()
        XCTAssertEqual(config.0, 5)
        return data[config.1.lowerBound] >> 3
    }

    private func bytes(_ buffer: CMSampleBuffer) throws -> Data {
        let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(buffer))
        var data = Data(count: CMBlockBufferGetDataLength(block))
        let status = data.withUnsafeMutableBytes { pointer in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: pointer.count, destination: pointer.baseAddress!)
        }
        XCTAssertEqual(status, noErr)
        return data
    }
}

private final class CallbackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

private final class AudioResumeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
