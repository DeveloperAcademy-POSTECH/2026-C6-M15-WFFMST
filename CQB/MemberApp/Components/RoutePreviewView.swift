import SwiftUI
import CQBCore

struct RoutePreviewView: View {
    let image: UIImage
    let raw: RawTrackDocument
    let correction: RouteCorrectionOutput?
    @State private var showsRaw = true
    @State private var showsCorrected = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("원본", isOn: $showsRaw).tint(.orange)
                Toggle("보정", isOn: $showsCorrected).tint(.cyan)
            }
            Image(uiImage: image).resizable().scaledToFit()
                .overlay {
                    Canvas { context, size in
                        let width = Double(image.cgImage?.width ?? 2172)
                        let height = Double(image.cgImage?.height ?? 724)
                        func screen(_ point: MapPoint) -> CGPoint {
                            CGPoint(x: point.x / width * size.width, y: point.y / height * size.height)
                        }
                        if showsRaw {
                            var path = Path()
                            var previousSegment: Int?
                            for sample in raw.samples {
                                guard let meters = sample.relative else { previousSegment = nil; continue }
                                let point = screen(AnchoredMapMatcher.transformed(meters, anchor: raw.start,
                                    scale: raw.pixelsPerMeter, rotation: raw.rotationDegrees, factor: 1))
                                if previousSegment == sample.segment { path.addLine(to: point) }
                                else { path.move(to: point) }
                                previousSegment = sample.segment
                            }
                            context.stroke(path, with: .color(.orange), lineWidth: 2)
                        }
                        if showsCorrected, let document = correction?.document {
                            var path = Path()
                            var previousPart: Int?
                            for vertex in document.vertices {
                                let point = screen(MapPoint(x: vertex.point.x, y: vertex.point.y))
                                if previousPart == vertex.part { path.addLine(to: point) }
                                else { path.move(to: point) }
                                previousPart = vertex.part
                            }
                            context.stroke(path, with: .color(.cyan), lineWidth: 2)
                        }
                        let start = screen(raw.start)
                        context.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)), with: .color(.green))
                    }
                }
                .clipped()
            Text("주황: 원본 · 하늘색: 보정 · 초록: 출발점")
                .font(.caption)
        }
    }
}
