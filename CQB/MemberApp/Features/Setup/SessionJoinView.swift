import SwiftUI
import CQBDesignSystem

struct SessionJoinView: View {
    @State private var pin = ""
    @State private var memberName = ""
    @FocusState private var focusedField: Field?
    /// 참가 요청 및 서버 검증은 호출부에서 처리한다.
    var isJoining = false
    var onStartDemo: (() -> Void)?
    var onJoin: (String, String) -> Void

    private enum Field: Hashable { case pin, name }
    private var canJoin: Bool {
        pin.count == 6 && !memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("훈련 참가")
                        .font(DSTypography.h2)
                        .padding(.bottom, 68)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PIN 번호").font(DSTypography.h3)
                        TextField("6자리 PIN 입력", text: $pin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .pin)
                            .accessibilityLabel("PIN 번호")
                            .onChange(of: pin) { _, value in
                                pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                            }
                    }
                    .padding(.bottom, 52)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("대원명").font(DSTypography.h3)
                        TextField("예: 이름", text: $memberName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .name)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .accessibilityLabel("대원명")
                    }
                    
                    Text("지휘관이 알아볼 수 있는 이름을 입력해주세요.")
                        .font(DSTypography.bodySmall)
                        .foregroundStyle(DSColor.darkGreen)
                        .padding(.top, 24)
                    
                    Spacer(minLength: 28)
                    
                    ActionButton(isJoining ? "세션 도면 불러오는 중…" : "참가") {
                        focusedField = nil
                        onJoin(pin, memberName.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(!canJoin || isJoining)

                    if let onStartDemo {
                        HStack(spacing: 12) {
                            Rectangle().frame(height: 1)
                            Text("또는").font(DSTypography.caption)
                            Rectangle().frame(height: 1)
                        }
                        .foregroundStyle(DSColor.area3)
                        .padding(.vertical, 12)

                        Button(action: onStartDemo) {
                            Label("데모 모드 시작", systemImage: "testtube.2")
                                .font(DSTypography.body)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(DSColor.main)
                                .background(DSColor.area1)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DSColor.main))
                        }
                        .accessibilityHint("PIN과 별도 iPad 없이 Capture의 주요 기능을 체험합니다.")
                        .accessibilityIdentifier("join.demo")
                    }
                }
                .font(DSTypography.body)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(DSColor.white)
        .tint(DSColor.main)
        .background(DSColor.background.ignoresSafeArea())
    }
}

#Preview("세션 참가") {
    SessionJoinView(onStartDemo: {}) { pin, name in print("Preview 참가: \(pin), \(name)") }
}
