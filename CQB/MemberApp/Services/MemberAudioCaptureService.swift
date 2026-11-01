@preconcurrency import AVFoundation
import Foundation

/// Session configuration, callbacks and shutdown all run on one background queue.
nonisolated final class MemberAudioCaptureService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.cqb.member.audio-capture", qos: .userInitiated)
    private var delivery: MemberAudioSampleDelivery?
    private var startup: AsyncStream<Double>.Continuation?
    private var observers: [NSObjectProtocol] = []
    private var isConfigured = false
    private var generation = UUID()

    /// Wait for the first real microphone buffer, so the encoder uses the device sample rate.
    /// A denied/unavailable microphone is represented by nil, as permitted by the contract.
    func start(onSampleBuffer: @escaping @Sendable (CMSampleBuffer) -> Void,
               onInterruption: @escaping @Sendable () -> Void,
               onResume: @escaping @Sendable () -> Void) async -> Double? {
        guard !Task.isCancelled else { return nil }
        let requestID = UUID()
        let responses = AsyncStream<Double>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.onTermination = { [weak self] reason in
                guard case .cancelled = reason, let self else { return }
                self.queue.async { [self] in
                    guard self.generation == requestID else { return }
                    self.stopOnQueue()
                }
            }
            // Enqueue startup before iteration begins, so cancellation's cleanup is ordered
            // after it. The request ID prevents an old cleanup from stopping a new capture.
            queue.async { [self] in
                stopOnQueue()
                generation = requestID
                delivery = MemberAudioSampleDelivery(onSampleBuffer: onSampleBuffer,
                                                     onInterruption: onInterruption, onResume: onResume)
                startup = continuation
                do {
                    try configure()
                    observeInterruptions()
                    session.startRunning()
                    guard session.isRunning else { stopOnQueue(); return }
                } catch {
                    stopOnQueue()
                    return
                }
                queue.asyncAfter(deadline: .now() + 2) { [self] in
                    guard generation == requestID, startup != nil else { return }
                    stopOnQueue()
                }
            }
        }
        var iterator = responses.makeAsyncIterator()
        return await iterator.next()
    }

    /// Waiting for this queue drains previously delivered buffers before the writer finishes.
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopOnQueue()
                continuation.resume()
            }
        }
    }

    private func configure() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else { throw CocoaError(.featureUnsupported) }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        isConfigured = true
    }

    private func observeInterruptions() {
        let currentGeneration = generation
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [self] in
                    guard self.generation == currentGeneration else { return }
                    if self.startup != nil { self.stopOnQueue() }
                    else {
                        self.delivery?.interrupt()
                    }
                }
            })
        }
    }

    private func stopOnQueue() {
        generation = UUID()
        delivery = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if session.isRunning { session.stopRunning() }
        let continuation = startup
        startup = nil
        continuation?.finish()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let clock = session.synchronizationClock,
              let hostBuffer = RecordingAudioSamples.retime(sampleBuffer, convert: {
                  CMSyncConvertTime($0, from: clock, to: CMClockGetHostTimeClock())
              }), let rate = delivery?.append(hostBuffer) else { return }
        if let continuation = startup {
            startup = nil
            continuation.yield(rate)
            continuation.finish()
        }
    }
}

/// Processes host-clock samples on the capture queue, independently of microphone hardware.
nonisolated struct MemberAudioSampleDelivery {
    let onSampleBuffer: @Sendable (CMSampleBuffer) -> Void
    let onInterruption: @Sendable () -> Void
    let onResume: @Sendable () -> Void
    private(set) var isInterrupted = false
    private var lastSampleTimestamp = -Double.infinity

    init(onSampleBuffer: @escaping @Sendable (CMSampleBuffer) -> Void,
         onInterruption: @escaping @Sendable () -> Void,
         onResume: @escaping @Sendable () -> Void) {
        self.onSampleBuffer = onSampleBuffer
        self.onInterruption = onInterruption
        self.onResume = onResume
    }

    mutating func interrupt() {
        isInterrupted = true
        onInterruption()
    }

    @discardableResult
    mutating func append(_ buffer: CMSampleBuffer) -> Double? {
        guard CMSampleBufferDataIsReady(buffer), CMSampleBufferGetNumSamples(buffer) > 0,
              let rate = RecordingAudioSamples.sampleRate(of: buffer) else { return nil }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard timestamp.isFinite, timestamp > lastSampleTimestamp else { return nil }
        lastSampleTimestamp = timestamp
        onSampleBuffer(buffer)
        // A notification ending an interruption does not prove that samples are flowing.
        if isInterrupted {
            isInterrupted = false
            onResume()
        }
        return rate
    }
}
