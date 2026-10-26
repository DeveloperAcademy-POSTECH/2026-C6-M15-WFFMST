import SwiftUI

struct ExperimentSetupView: View {
    @Environment(ExperimentStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("실험 식별") {
                TextField("세션 ID", text: $store.sessionID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("대원 ID", text: $store.participantID)
                TextField("기기 ID", text: $store.deviceID)
                TextField("시나리오", text: $store.scenario, axis: .vertical)
            }

            Section("고정 설정") {
                LabeledContent("분류기", value: "Apple built-in v1")
                LabeledContent("Overlap", value: "50%")
                LabeledContent("분석", value: "녹음 종료 후")
                Text("임계값을 적용하기 전 모든 분류 confidence를 저장합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("ARKit 카메라·마이크 준비") {
                    Task { await store.prepare() }
                }
                .disabled(!store.canPrepare)
            }

            if let error = store.errorMessage {
                Section("오류") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }
}
