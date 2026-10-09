import SwiftUI
import CQBDesignSystem

struct RecordingUploadView: View {
    /// 0...1 전송 진행률. 완료 여부는 서버 저장 확인 이후 별도로 전달한다.
    let progress: Double
    let isComplete: Bool
    var onHome: () -> Void

    private var normalizedProgress: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("훈련 종료").font(DSTypography.h2)
                    Spacer(minLength: 80)
                    VStack(alignment: .leading, spacing: 24) {
                        ProgressView(value: normalizedProgress)
                            .tint(DSColor.main)
                            .background(DSColor.area3, in: Capsule())
                            .accessibilityLabel("데이터 전송 진행률")
                            .padding(.bottom, 8)
                        HStack {
                            Text(isComplete ? "전송 완료" : "서버로 데이터 보내는 중")
                                .font(DSTypography.h3)
                            Spacer(minLength: 12)
                            Text("\(Int(normalizedProgress * 100))%")
                                .font(DSTypography.body1)
                                .monospacedDigit()
                        }
                        Text("완료 전까지 앱을 종료하지 않고 대기해주세요.")
                            .font(DSTypography.body2)
                            .foregroundStyle(DSColor.darkGreen)
                    }
                    Spacer(minLength: 100)
                    VStack(spacing: 24) {
                        Text(isComplete ? "완료되었습니다." : "완료되면 종료할 수 있습니다.")
                            .font(DSTypography.body2)
                            .foregroundStyle(DSColor.darkGreen)
                        Button("홈으로", action: onHome)
                            .buttonStyle(MemberPrimaryButtonStyle())
                            .disabled(!isComplete)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .foregroundStyle(DSColor.white)
        .background(DSColor.background.ignoresSafeArea())
    }
}

#Preview("업로드 중") {
    RecordingUploadView(progress: 0.8, isComplete: false) { print("Preview 홈 이동") }
}

#Preview("업로드 완료") {
    RecordingUploadView(progress: 1, isComplete: true) { print("Preview 홈 이동") }
}
