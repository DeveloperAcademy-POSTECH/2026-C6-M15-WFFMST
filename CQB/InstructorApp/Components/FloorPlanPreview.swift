import SwiftUI

// 실제 도면 파일이 없는 프로토타입용 개략도. 좌표 계산·도면 분석은 수행하지 않는다.
struct FloorPlanPreview: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            HStack(spacing: 12) {
                rooms(["Room 1", "Room 2", "Room 3"])
                Text("통로").frame(maxHeight: .infinity)
                rooms(["Room 4", "Room 5", "Room 6"])
            }
            Text("샘플 개략도 · 실제 도면 아님").font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func rooms(_ names: [String]) -> some View {
        VStack(spacing: 12) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .overlay(Rectangle().stroke(.secondary))
            }
        }
    }
}
