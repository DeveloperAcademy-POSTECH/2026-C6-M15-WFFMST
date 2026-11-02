import SwiftUI
import CQBDesignSystem

struct RecordingUploadView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showsAbandonConfirmation = false
    var isDemo = false
    /// 0...1 전송 진행률. 완료 여부는 서버 저장 확인 이후 별도로 전달한다.
    let progress: Double
    let isComplete: Bool
    let isAbandoned: Bool
    let statusMessage: String
    let errorMessage: String?
    let isUploading: Bool
    var onRetry: () async -> Void
    var onAbandon: () async -> Void
    var onHome: () -> Void

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var progressMessage: String {
        if isAbandoned { return "전송 실패로 종료" }
        if isComplete { return isDemo ? "데모 처리 완료" : "전송 완료" }
        if isDemo { return "데모 결과 확인 중" }
        return isLandscape
            ? "전송 완료 전까지 앱을 종료하지 않고 대기해주세요"
            : "전송 완료 전까지\n앱을 종료하지 않고 대기해주세요"
    }

    var body: some View {
        GeometryReader { geometry in
            let topPadding = max(0, DSSpacing.s40 - geometry.safeAreaInsets.top)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("훈련 종료")
                        .dsTextStyle(DSTypography.headingBold32)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: DSSpacing.s60)
                    VStack(alignment: .leading, spacing: DSSpacing.s16) {
                        UploadProgressView(progress: progress, isComplete: isComplete, message: progressMessage)
                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .dsTextStyle(DSTypography.captionRegular14)
                                .foregroundStyle(DSColor.contentSecondary)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .dsTextStyle(DSTypography.captionRegular14)
                                .foregroundStyle(DSColor.statusError)
                            ActionButton("실패한 항목 다시 보내기") { Task { await onRetry() } }
                                .disabled(isUploading)
                                .accessibilityIdentifier("upload.retry")
                            if !isDemo {
                                ActionButton("이 기록의 업로드 종료") { showsAbandonConfirmation = true }
                                    .disabled(isUploading)
                                    .accessibilityIdentifier("upload.abandon")
                            }
                        }
                    }
                    Spacer(minLength: DSSpacing.s60)
                    VStack(spacing: DSSpacing.s12) {
                        if isAbandoned || isDemo {
                            Text(isAbandoned ? "완료된 자료만 AAR에 포함됩니다." : "서버에 전송하지 않는 데모입니다.")
                                .dsTextStyle(DSTypography.captionRegular14)
                                .foregroundStyle(DSColor.contentSecondary)
                        }
                        ActionButton(isDemo ? "데모 종료" : "홈으로", action: onHome)
                            .disabled(!isComplete && !isAbandoned)
                            .accessibilityIdentifier("upload.home")
                    }
                    .frame(maxWidth: isLandscape ? 362 : .infinity)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(minHeight: max(0, geometry.size.height - topPadding - DSSpacing.s8))
                .padding(.horizontal, isLandscape ? DSSpacing.s40 : DSSpacing.s20)
                .padding(.top, topPadding)
                .padding(.bottom, DSSpacing.s8)
            }
        }
        .foregroundStyle(DSColor.contentPrimary)
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
        .alert("업로드를 종료할까요?", isPresented: $showsAbandonConfirmation) {
            Button("업로드 종료", role: .destructive) { Task { await onAbandon() } }
            Button("계속 재시도", role: .cancel) {}
        } message: {
            Text("전송하지 못한 영상과 동선은 이번 AAR에 포함되지 않습니다. 기기에 저장된 파일은 삭제하지 않습니다.")
        }
    }
}

#Preview("업로드 중") {
    RecordingUploadView(progress: 0.8, isComplete: false, isAbandoned: false,
                        statusMessage: "영상 조각 업로드 중 · 3/5",
                        errorMessage: nil, isUploading: true, onRetry: {}, onAbandon: {}) {
        print("Preview 홈 이동")
    }
}

#Preview("업로드 완료") {
    RecordingUploadView(progress: 1, isComplete: true, isAbandoned: false,
                        statusMessage: "영상과 보정 동선 업로드 완료",
                        errorMessage: nil, isUploading: false, onRetry: {}, onAbandon: {}) {
        print("Preview 홈 이동")
    }
}

#Preview("05 업로드 중 · 가로", traits: .landscapeLeft) {
    RecordingUploadView(progress: 0.8, isComplete: false, isAbandoned: false,
                        statusMessage: "", errorMessage: nil, isUploading: true,
                        onRetry: {}, onAbandon: {}, onHome: {})
}

#Preview("05 업로드 완료 · 가로", traits: .landscapeLeft) {
    RecordingUploadView(progress: 1, isComplete: true, isAbandoned: false,
                        statusMessage: "", errorMessage: nil, isUploading: false,
                        onRetry: {}, onAbandon: {}, onHome: {})
}

#Preview("05 전송 실패 · 큰 글자") {
    RecordingUploadView(progress: 0.6, isComplete: false, isAbandoned: false,
                        statusMessage: "전송되지 않은 자료가 있습니다.",
                        errorMessage: "네트워크 연결을 확인하고 실패한 자료를 다시 보내주세요.", isUploading: false,
                        onRetry: {}, onAbandon: {}, onHome: {})
        .dynamicTypeSize(.accessibility3)
}
