@preconcurrency import AVFoundation
import Foundation

/// Session configuration, callbacks and shutdown all run on one background queue.
nonisolated final class MemberAudioCaptureService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.cqb.member.audio-capture", qos: .userInitiated)
    private var onSampleBuffer: (@Sendable (CMSampleBuffer) -> Void)?
    private var onInterruption: (@Sendable () -> Void)?
    private var startup: CheckedContinuation<Double?, Never>?
    private var observers: [NSObjectProtocol] = []
    private var isConfigured = false
    private var generation = UUID()

    /// Wait for the first real microphone buffer, so the encoder uses the device sample rate.
    /// A denied/unavailable microphone is represented by nil, as permitted by the contract.
    func start(onSampleBuffer: @escaping @Sendable (CMSampleBuffer) -> Void,
               onInterruption: @escaping @Sendable () -> Void) async -> Double? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopOnQueue()
                self.onSampleBuffer = onSampleBuffer
                self.onInterruption = onInterruption
                startup = continuation
                let currentGeneration = generation
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
                    guard generation == currentGeneration, startup != nil else { return }
                    stopOnQueue()
                }
            }
        }
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
                    else { self.onInterruption?() }
                }
            })
        }
    }

    private func stopOnQueue() {
        generation = UUID()
        onSampleBuffer = nil
        onInterruption = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if session.isRunning { session.stopRunning() }
        let continuation = startup
        startup = nil
        continuation?.resume(returning: nil)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let callback = onSampleBuffer, let clock = session.synchronizationClock,
              let rate = RecordingAudioSamples.sampleRate(of: sampleBuffer),
              let hostBuffer = RecordingAudioSamples.retime(sampleBuffer, convert: {
                  CMSyncConvertTime($0, from: clock, to: CMClockGetHostTimeClock())
              }) else { return }
        if let continuation = startup {
            startup = nil
            continuation.resume(returning: rate)
        }
        callback(hostBuffer)
    }
}
