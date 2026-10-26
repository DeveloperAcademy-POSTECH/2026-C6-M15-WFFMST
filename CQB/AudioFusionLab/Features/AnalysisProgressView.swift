import SwiftUI

struct AnalysisProgressView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("내장 Sound Classifier 분석 중")
                .font(.title3.weight(.semibold))
            Text("녹음 길이에 따라 시간이 걸릴 수 있습니다. 앱을 종료하지 마세요.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
