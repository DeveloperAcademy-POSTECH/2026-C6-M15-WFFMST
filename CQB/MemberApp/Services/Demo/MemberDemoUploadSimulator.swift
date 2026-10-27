import Foundation

nonisolated struct MemberDemoUploadStep: Equatable, Sendable {
    let progress: Double
    let message: String
}

/// 서버 전송 없이 심사자가 완료 흐름을 확인할 수 있도록 로컬 처리 단계를 재현한다.
nonisolated struct MemberDemoUploadSimulator: Sendable {
    let stepDelay: Duration

    init(stepDelay: Duration = .milliseconds(350)) {
        self.stepDelay = stepDelay
    }

    static let steps = [
        MemberDemoUploadStep(progress: 0.25, message: "로컬 영상 확인 중"),
        MemberDemoUploadStep(progress: 0.65, message: "보정 동선 확인 중"),
        MemberDemoUploadStep(progress: 1, message: "데모 처리 완료 · 서버로 전송하지 않았습니다.")
    ]

    func run(onStep: @MainActor @Sendable (MemberDemoUploadStep) -> Void) async {
        for step in Self.steps {
            guard !Task.isCancelled else { return }
            if stepDelay > .zero {
                do { try await Task.sleep(for: stepDelay) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            await onStep(step)
        }
    }
}
