import SwiftUI

struct ExperimentRecordingView: View {
    @Environment(ExperimentStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Text(duration(store.elapsedSeconds))
                    .font(.system(size: 48, weight: .semibold, design: .monospaced))
            }

            Label("오디오 기록 중", systemImage: "waveform.circle.fill")
                .foregroundStyle(.red)
                .font(.headline)

            HStack(spacing: 12) {
                markerButton(.sync, systemImage: "dot.radiowaves.left.and.right")
                markerButton(.shotCandidate, systemImage: "scope")
                markerButton(.other, systemImage: "flag")
            }

            List {
                Section("수동 마커 \(store.markers.count)개") {
                    ForEach(store.markers.reversed()) { marker in
                        HStack {
                            Text(marker.kind.title)
                            Spacer()
                            Text(String(format: "%.3fs", marker.recordingTimeSeconds))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)

            Button(role: .destructive) {
                Task { await store.stopRecording() }
            } label: {
                Label("녹음 종료 및 분석", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private func markerButton(_ kind: ManualMarkerKind, systemImage: String) -> some View {
        Button {
            store.addMarker(kind)
        } label: {
            Label(kind.title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, remainder)
    }
}
