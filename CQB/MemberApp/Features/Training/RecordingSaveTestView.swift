import AVKit
import SwiftUI
import CQBDesignSystem

/// Confirms that the locally recorded video was finalized. Network upload is a later feature.
struct RecordingSaveTestView: View {
    let recordingURL: URL?
    var switchView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("훈련 종료").font(DSTypography.h2)

            if let recordingURL {
                VideoPlayer(player: AVPlayer(url: recordingURL))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("영상이 이 iPhone에 저장되었습니다.")
                    .font(DSTypography.bodySmall)
                    .foregroundStyle(DSColor.darkGreen)
                Text(recordingURL.lastPathComponent)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.darkGreen)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                ContentUnavailableView("저장된 영상을 찾을 수 없습니다", systemImage: "video.slash")
            }

            Spacer(minLength: 16)

            ActionButton("업로드", action: switchView)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .foregroundStyle(DSColor.white)
        .background(DSColor.background.ignoresSafeArea())
    }
}
