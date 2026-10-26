import SwiftUI

struct ExperimentResultView: View {
    @Environment(ExperimentStore.self) private var store
    @State private var showsShareSheet = false

    var body: some View {
        List {
            Section("분석 요약") {
                LabeledContent("분석 윈도", value: "\(store.classificationWindowCount)")
                LabeledContent("분류 행", value: "\(store.classifications.count)")
                LabeledContent("gunshot ≥ 0.1 윈도", value: "\(store.gunshotCandidateWindowCount)")
                LabeledContent("수동 마커", value: "\(store.markers.count)")
            }

            if !store.topClassifications.isEmpty {
                Section("최근 윈도의 1순위 분류") {
                    ForEach(Array(store.topClassifications.enumerated()), id: \.offset) { _, result in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(result.identifier)
                                Text(String(format: "기록 %.3fs", result.recordingTimeSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(result.confidence, format: .percent.precision(.fractionLength(1)))
                                .monospacedDigit()
                        }
                    }
                }
            }

            if let files = store.completedFiles {
                Section("저장 위치") {
                    Text(files.directory.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Section {
                    Button("결과 파일 공유") { showsShareSheet = true }
                }
            }

            Section {
                Button("새 실험", action: store.reset)
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            if let files = store.completedFiles {
                ShareSheet(items: files.shareURLs)
            }
        }
    }
}
