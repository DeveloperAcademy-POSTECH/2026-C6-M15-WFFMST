//
//  SetupStatusRow.swift
//  MemberApp
//
//  Created by YoonJung Kwak on 10/9/26.
//

import SwiftUI
import CQBDesignSystem

struct SetupStatusRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.s8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DSSpacing.s12))

        layout {
            Text(title)
                .dsTextStyle(DSTypography.bodyRegular12)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .dsTextStyle(DSTypography.captionMedium14)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(DSColor.contentPrimary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Setup Status Row · 미설정") {
    VStack(spacing: DSSpacing.s24) {
        SetupStatusRow("출발 위치", value: "지정 안 됨")
        SetupStatusRow("바라보는 방향", value: "설정 전")
    }
    .padding(DSSpacing.s24)
    .background(DSColor.backgroundPrimary)
}

#Preview("Setup Status Row · 설정 완료") {
    VStack(spacing: DSSpacing.s24) {
        SetupStatusRow("출발 위치", value: "지정됨")
        SetupStatusRow("바라보는 방향", value: "설정됨")
    }
    .padding(DSSpacing.s24)
    .background(DSColor.backgroundPrimary)
}

#Preview("Setup Status Row · 긴 문구 · Dynamic Type") {
    SetupStatusRow("훈련 도면에서 선택한 출발 위치", value: "출발 위치가 아직 지정되지 않음")
        .padding(DSSpacing.s24)
        .background(DSColor.backgroundPrimary)
        .dynamicTypeSize(.accessibility3)
}
