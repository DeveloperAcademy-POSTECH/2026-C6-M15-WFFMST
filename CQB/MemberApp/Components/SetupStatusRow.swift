//
//  SetupStatusRow.swift
//  MemberApp
//
//  Created by YoonJung Kwak on 10/9/26.
//

import SwiftUI
import CQBDesignSystem

struct SetupStatusRow: View {
    let title: String
    let value: String
    let isSet: Bool

    init(_ title: String, value: String, isSet: Bool) {
        self.title = title
        self.value = value
        self.isSet = isSet
    }

    var body: some View {
        HStack {
            Text(title)
                .font(DSTypography.body)
                .foregroundStyle(DSColor.white)
            Spacer()
            Text(value).font(DSTypography.bodySmall)
                .foregroundStyle(isSet ? DSColor.main : DSColor.darkGreen)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(DSColor.area1)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSColor.area3))
    }
}

#Preview("Setup Status") {
    VStack(spacing: 24) {
        SetupStatusRow("출발 위치", value: "미지정", isSet: false)
        SetupStatusRow("출발 위치", value: "지정됨", isSet: true)
        SetupStatusRow("바라보는 방향", value: "미설정", isSet: false)
        SetupStatusRow("바라보는 방향", value: "설정됨", isSet: true)
    }
    .padding(24)
    .background(DSColor.background)
}
