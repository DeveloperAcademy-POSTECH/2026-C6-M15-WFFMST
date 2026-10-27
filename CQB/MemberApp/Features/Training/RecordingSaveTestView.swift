import AVKit
import SwiftUI
import CQBCore
import CQBDesignSystem

/// 로컬 기록과 보정 결과 확인 화면. 영상은 녹화 중 조각 단위로 전송한다.
struct RecordingSaveTestView: View {
    let recordingURLs: [URL]
    var isDemo = false
    var raw: RawTrackDocument? = nil
    var correction: RouteCorrectionOutput? = nil
    var mapImage: UIImage? = nil
    var files: LocalRecordingFiles? = nil
    var filesSaved = false
    var onHome: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDiscardDemo: () -> Void = {}
    var switchView: () -> Void
    @State private var player: AVQueuePlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("훈련 종료").font(DSTypography.h2)
                if !recordingURLs.isEmpty {
                    VideoPlayer(player: player)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .onAppear {
                            player = AVQueuePlayer(items: recordingURLs.map { AVPlayerItem(url: $0) })
                        }
                        .onDisappear { player?.pause() }
                    ForEach(Array(recordingURLs.enumerated()), id: \.offset) { index, url in
                        ShareLink("영상 조각 \(index + 1) 내보내기", item: url)
                    }
                } else {
                    Text("영상 저장에 실패했습니다. 남아 있는 동선은 별도로 보존합니다.")
                }
                if let raw, let mapImage {
                    RoutePreviewView(image: mapImage, raw: raw, correction: correction)
                    Text("원본 샘플 \(raw.samples.count)개 · 23.11 px/m")
                        .font(.caption)
                }
                if let correction {
                    let result = correction.document
                    Text(result.status == .done ? "동선 보정 완료" : result.status == .partial ? "일부 구간 보정 미완료" : "동선을 보정하지 못했습니다")
                        .font(.headline)
                    if result.searchIncomplete { Text("탐색 한도에 도달했습니다. 결과를 확인해주세요.") }
                    if result.warnings.contains(.headingAmbiguous) { Text("출발 방향 후보가 모호합니다.") }
                    if result.warnings.contains(.trackingLost) { Text("추적이 끊긴 구간은 연결하지 않았습니다.") }
                    if let failure = result.failureReason { Text("실패 사유: \(failure.rawValue)").font(.caption) }
                    DisclosureGroup("미해결 구간 \(result.unresolvedIntervals.count)개") {
                        ForEach(Array(result.unresolvedIntervals.enumerated()), id: \.offset) { _, interval in
                            Text(String(format: "%.1f–%.1f초 · %@", interval.from, interval.to,
                                        interval.sourceReason ?? interval.reason.rawValue))
                                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let diagnostics = correction.diagnostics {
                        DisclosureGroup("보정 후보 \(diagnostics.candidates.count)개 · 첫 후보를 저장") {
                            ForEach(Array(diagnostics.candidates.enumerated()), id: \.offset) { i, candidate in
                                Text(String(format: "후보 %d · 점수 %.2f · 방향 보정 %.1f° · 미해결 %d개",
                                    i + 1, candidate.score, candidate.initialHeading?.offsetDegrees ?? 0, candidate.unresolved.count))
                                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                if let files {
                    if FileManager.default.fileExists(atPath: files.raw.path) {
                        ShareLink("원본 JSON 내보내기", item: files.raw)
                    }
                    if filesSaved {
                        ShareLink("보정 JSON 내보내기", item: files.result)
                    } else {
                        ActionButton("동선 파일 저장 재시도", action: onRetry)
                    }
                }
                Text(isDemo
                    ? "데모 영상과 보정 동선은 기기 안에서만 확인하며 서버로 전송하지 않습니다."
                    : "영상 조각은 녹화 중 전송하고, 종료 후 보정 동선을 전송합니다.")
                    .font(.caption)
                ActionButton(isDemo ? "데모 처리 계속" : "업로드 상태 확인", action: switchView)
                    .disabled(!filesSaved || recordingURLs.isEmpty)
                if isDemo && (!filesSaved || recordingURLs.isEmpty) {
                    Button("데모 종료하고 다시 시작", action: onDiscardDemo)
                        .foregroundStyle(DSColor.darkGreen)
                } else if filesSaved, !isDemo {
                    Button("처음으로", action: onHome)
                }
            }
            .padding(24)
        }
        .foregroundStyle(DSColor.white)
        .background(DSColor.background.ignoresSafeArea())
    }
}
