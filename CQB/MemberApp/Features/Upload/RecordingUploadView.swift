import SwiftUI
import CQBDesignSystem

struct RecordingUploadView: View {
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

    private var progressMessage: String {
        if isAbandoned { return "전송 실패로 종료" }
        if isComplete { return isDemo ? "데모 처리 완료" : "전송 완료" }
        if isDemo { return "데모 결과 확인 중" }
        return "전송 완료 전까지\n앱을 종료하지 않고 대기해주세요"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("훈련 종료").font(DSTypography.h2)
                    Spacer(minLength: 80)
                    VStack(alignment: .leading, spacing: 24) {
                        UploadProgressView(progress: progress, isComplete: isComplete, message: progressMessage)
                        Text(statusMessage)
                            .font(DSTypography.bodySmall)
                            .foregroundStyle(DSColor.darkGreen)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(DSTypography.bodySmall)
                                .foregroundStyle(.red)
                            ActionButton("실패한 항목 다시 보내기") {
                                Task { await onRetry() }
                            }
                            .disabled(isUploading)
                            if !isDemo {
                                ActionButton("이 기록의 업로드 종료") {
                                    showsAbandonConfirmation = true
                                }
                                .disabled(isUploading)
                                .accessibilityIdentifier("upload.abandon")
                            }
                        }
                    }
                    Spacer(minLength: 100)
                    VStack(spacing: 24) {
                        Text(isAbandoned
                            ? "완료된 자료만 AAR에 포함됩니다."
                            : isComplete
                            ? (isDemo ? "서버에 전송하지 않고 완료했습니다." : "완료되었습니다.")
                            : "완료되면 종료할 수 있습니다.")
                            .font(DSTypography.bodySmall)
                            .foregroundStyle(DSColor.darkGreen)
                        ActionButton(isDemo ? "데모 종료" : "홈으로", action: onHome)
                            .disabled(!isComplete && !isAbandoned)
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
