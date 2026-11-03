// 출처: DeveloperAcademy-POSTECH/2026-C6-M15-WFFMST-gunshot-lab
//       Packages/GunshotDetection/Sources/GunshotDetection/OnsetDetector.swift @ 713e743a0dc54745a650710156c83601bd837147
// 제품 통합(#172)을 위해 결합 방식에 필요한 파일만 복사했다. 내용은 고치지 않는다.
// 대원 앱의 기본 MainActor 격리를 피하려고 최상위 타입 선언에 nonisolated만 붙였다.
// 감지 로직을 바꿀 때는 연구 저장소에서 먼저 고친 뒤 다시 가져온다.

import AVFoundation

/// 급상승(onset) 감지 + 잔향 감쇠 시간 측정.
/// - 급상승: 5ms 프레임 최대 진폭(dBFS)이 직전 0.5초 중앙값보다 minRiseDB 이상 높고 minLevelDB 이상이면 후보.
/// - 감쇠: 후보 시작 뒤 20ms 안의 최고 에너지(5ms 창)보다 20dB 작아질 때까지 걸린 시간(10ms 창, 5ms 간격, 최대 0.5초).
///   폰 근처 충격음(폰 치기·박수)은 대부분 20~45ms였다. 실내 총성은 기기에 따라 60~205ms였다(GunshotBench reverb·methodbench, 노션 E14).
/// 후보는 감쇠 측정이 끝난 뒤(총성은 약 0.15초, 최대 0.5초 뒤) 내보낸다.
/// 오디오 탭 콜백처럼 한 스레드에서 순서대로 호출한다. 버퍼 크기와 무관하게 같은 결과를 낸다.
nonisolated public final class OnsetDetector: @unchecked Sendable {
    public struct Config: Sendable {
        public var minLevelDB: Double
        public var minRiseDB: Double
        /// 연발을 놓치지 않도록 짧게 둔다. 잔향 중복은 결합 판정의 묶기가 처리한다.
        public var refractorySeconds: Double
        public var maxDecaySeconds: Double

        public init(minLevelDB: Double = -20, minRiseDB: Double = 18,
                    refractorySeconds: Double = 0.15, maxDecaySeconds: Double = 0.5) {
            self.minLevelDB = minLevelDB
            self.minRiseDB = minRiseDB
            self.refractorySeconds = refractorySeconds
            self.maxDecaySeconds = maxDecaySeconds
        }

        /// GunshotBench 실탄 비교(노션 E14)에서 고른 값
        public static let standard = Config()
    }

    public struct Candidate: Sendable, Equatable {
        /// 분석에 넘긴 오디오 프레임 위치 기준 시간(초). 분류 결과 timeRange와 같은 시간축이다.
        public let audioSeconds: Double
        public let riseDB: Double
        public let levelDB: Double
        public let clipped: Bool
        public let decaySeconds: Double
    }

    public let config: Config
    private let sampleRate: Double
    private let frameLength: Int
    private let historyLength = 100   // 0.5초
    private var history: [Double] = []
    /// 5ms 프레임을 채우지 못하고 남은 샘플과 그 첫 샘플의 오디오 프레임 위치
    private var leftover: [Float] = []
    private var leftoverStart: AVAudioFramePosition = 0
    private var lastOnsetSeconds = -Double.infinity

    /// 감쇠 측정용 최근 샘플. store[0]의 오디오 프레임 위치가 storeStart다.
    private var store: [Float] = []
    private var storeStart: AVAudioFramePosition = 0
    private struct Pending {
        let onsetFrame: AVAudioFramePosition
        let riseDB: Double
        let levelDB: Double
        let clipped: Bool
        var peakDB: Double?
        var step = 0.02
    }
    private var pending: [Pending] = []

    public init(sampleRate: Double, config: Config = .standard) {
        self.sampleRate = sampleRate
        self.config = config
        frameLength = Int(sampleRate * 0.005)
    }

    /// 첫 채널만 본다.
    public func process(_ buffer: AVAudioPCMBuffer, startFrame: AVAudioFramePosition) -> [Candidate] {
        guard let data = buffer.floatChannelData else { return [] }
        return process(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)), startFrame: startFrame)
    }

    public func process(_ incoming: UnsafeBufferPointer<Float>, startFrame: AVAudioFramePosition) -> [Candidate] {
        if store.isEmpty { storeStart = startFrame }
        store.append(contentsOf: incoming)

        // 이전 버퍼에서 남은 샘플이 바로 앞에 이어진다고 보고 합친다.
        let base = leftover.isEmpty ? startFrame : leftoverStart
        let samples = leftover + incoming
        var offset = 0
        while offset + frameLength <= samples.count {
            var peak: Float = 0
            for i in offset..<(offset + frameLength) { peak = max(peak, abs(samples[i])) }
            let levelDB = 20 * log10(Double(max(peak, 1e-6)))
            if history.count == historyLength {
                let background = history.sorted()[historyLength / 2]
                let rise = levelDB - background
                let frameSeconds = Double(base + AVAudioFramePosition(offset)) / sampleRate
                if levelDB >= config.minLevelDB, rise >= config.minRiseDB,
                   frameSeconds - lastOnsetSeconds >= config.refractorySeconds {
                    // 프레임 안에서 프레임 최대값의 절반을 처음 넘는 샘플을 시작 시각으로 잡는다.
                    let half = peak * 0.5
                    var s = offset
                    while s < offset + frameLength - 1 && abs(samples[s]) < half { s += 1 }
                    pending.append(Pending(onsetFrame: base + AVAudioFramePosition(s), riseDB: rise,
                                           levelDB: levelDB, clipped: peak >= 0.99))
                    lastOnsetSeconds = frameSeconds
                }
                history.removeFirst()
            }
            history.append(levelDB)
            offset += frameLength
        }
        leftover = Array(samples[offset...])
        leftoverStart = base + AVAudioFramePosition(offset)

        let done = measureDecays()
        trimStore()
        return done
    }

    /// 데이터가 들어온 만큼 감쇠 측정을 진행하고, 끝난 후보를 내보낸다.
    private func measureDecays() -> [Candidate] {
        let available = storeStart + AVAudioFramePosition(store.count)
        var done: [Candidate] = []
        for i in pending.indices {
            var p = pending[i]
            if p.peakDB == nil {
                guard p.onsetFrame + frames(0.02) <= available else { continue }
                p.peakDB = (0..<4).map { energyDB(from: p.onsetFrame + frames(Double($0) * 0.005), seconds: 0.005) }.max()
            }
            var decay: Double?
            while decay == nil && p.onsetFrame + frames(p.step + 0.01) <= available {
                if energyDB(from: p.onsetFrame + frames(p.step), seconds: 0.01) < p.peakDB! - 20 {
                    decay = p.step
                } else {
                    p.step += 0.005
                    if p.step >= config.maxDecaySeconds { decay = config.maxDecaySeconds }
                }
            }
            pending[i] = p
            if let decay {
                done.append(Candidate(audioSeconds: Double(p.onsetFrame) / sampleRate, riseDB: p.riseDB,
                                      levelDB: p.levelDB, clipped: p.clipped, decaySeconds: decay))
            }
        }
        let finished = Set(done.map(\.audioSeconds))
        pending.removeAll { finished.contains(Double($0.onsetFrame) / sampleRate) }
        return done
    }

    /// 아직 측정 중인 후보보다 오래된 샘플은 버린다. 후보가 없으면 0.1초만 남긴다.
    private func trimStore() {
        let end = storeStart + AVAudioFramePosition(store.count)
        let keepFrom = pending.map(\.onsetFrame).min() ?? (end - frames(0.1))
        let drop = min(Int(max(0, keepFrom - storeStart)), store.count)
        guard drop > 0 else { return }
        store.removeFirst(drop)
        storeStart += AVAudioFramePosition(drop)
    }

    private func frames(_ seconds: Double) -> AVAudioFramePosition {
        AVAudioFramePosition((seconds * sampleRate).rounded(.down))
    }

    private func energyDB(from frame: AVAudioFramePosition, seconds: Double) -> Double {
        let a = max(0, Int(frame - storeStart))
        let b = min(store.count, a + Int(seconds * sampleRate))
        guard b > a else { return -120 }
        var e: Double = 0
        for i in a..<b { e += Double(store[i]) * Double(store[i]) }
        return 10 * log10(max(e / Double(b - a), 1e-12))
    }
}
