import SwiftUI

struct CaptureReadyView: View {
    @Environment(ExperimentStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if store.phase == .preparing {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
            }
            Text(store.capture.statusMessage)
                .font(.title3.weight(.semibold))
            Text("기기를 실제 장착 위치에 고정한 뒤 시작하세요. 시작 직후와 종료 직전에 모든 기기가 들을 수 있는 동기화음을 남기는 것을 권장합니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            Button("녹음 시작", action: store.startRecording)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.phase != .ready)
            Button("취소", action: store.reset)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}
