import SwiftUI

// 등록 이미지는 그대로 표시하고, 기존 Mock 항목만 샘플 개략도를 사용한다.
struct FloorPlanPreview: View {
    let title: String
    var image: UIImage? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("등록한 도면 이미지")
            } else {
            HStack(spacing: 12) {
                rooms(["Room 1", "Room 2", "Room 3"])
                Text("통로").frame(maxHeight: .infinity)
                rooms(["Room 4", "Room 5", "Room 6"])
            }
            Text("샘플 개략도 · 실제 도면 아님").font(.caption).foregroundStyle(.secondary)
            }
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
