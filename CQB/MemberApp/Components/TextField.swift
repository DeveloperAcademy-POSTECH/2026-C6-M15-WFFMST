//
//  TextField.swift
//  MemberApp
//
//  Created by YoonJung Kwak on 10/9/26.
//

import SwiftUI
import CQBDesignSystem

/// 입력값과 안내 문구를 받는 MemberApp 공통 입력 필드.
/// 키보드, 포커스, 입력 검증은 호출부에서 설정한다.
struct TextField: View {
    private let placeholder: String
    @Binding private var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        SwiftUI.TextField(
            placeholder,
            text: $text,
            prompt: Text(placeholder).foregroundStyle(DSColor.white)
        )
        .textFieldStyle(.plain)
        .font(DSTypography.body)
        .foregroundStyle(DSColor.white)
        .tint(DSColor.main)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(DSColor.area1)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSColor.area3))
    }
}

#Preview("TextField") {
    VStack(spacing: 24) {
        TextField("6자리 PIN 입력", text: .constant(""))
        TextField("예: 이름", text: .constant(""))
    }
    .padding(24)
    .background(DSColor.background)
}
