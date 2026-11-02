import CQBDesignSystem
import SwiftUI

struct SessionJoinView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pin: String
    @State private var memberName: String
    @FocusState private var focusedField: Field?
    /// 참가 요청 및 서버 검증은 호출부에서 처리한다.
    var isJoining: Bool
    var onStartDemo: (() -> Void)?
    var onJoin: (String, String) -> Void

    init(pin: String = "", memberName: String = "", isJoining: Bool = false,
         onStartDemo: (() -> Void)? = nil, onJoin: @escaping (String, String) -> Void) {
        _pin = State(initialValue: pin)
        _memberName = State(initialValue: memberName)
        self.isJoining = isJoining
        self.onStartDemo = onStartDemo
        self.onJoin = onJoin
    }

    private enum Field: Hashable { case pin, name }
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var canJoin: Bool {
        pin.count == 6 && !memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: isLandscape ? DSSpacing.s32 : DSSpacing.s60) {
                        Text("훈련 참가")
                            .dsTextStyle(DSTypography.headingBold32)
                            .accessibilityAddTraits(.isHeader)

                        let layout = isLandscape && !dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(HStackLayout(alignment: .top, spacing: DSSpacing.s32))
                            : AnyLayout(VStackLayout(alignment: .leading, spacing: DSSpacing.s20))
                        layout {
                            VStack(alignment: .leading, spacing: DSSpacing.s8) {
                                Text("PIN 번호").dsTextStyle(DSTypography.captionMedium14)
                                SwiftUI.TextField(
                                    "6자리 PIN 입력", text: $pin,
                                    prompt: Text("6자리 PIN 입력").foregroundStyle(DSColor.contentTertiary)
                                )
                                .textFieldStyle(.ds(isFocused: focusedField == .pin))
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .focused($focusedField, equals: .pin)
                                .accessibilityLabel("PIN 번호")
                                .accessibilityIdentifier("join.pin")
                                .onChange(of: pin) { _, value in
                                    pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(Field.pin)

                            VStack(alignment: .leading, spacing: DSSpacing.s8) {
                                Text("대원명").dsTextStyle(DSTypography.captionMedium14)
                                SwiftUI.TextField(
                                    "지휘관이 알아볼 수 있는 이름을 입력", text: $memberName,
                                    prompt: Text("지휘관이 알아볼 수 있는 이름을 입력").foregroundStyle(DSColor.contentTertiary)
                                )
                                .textFieldStyle(.ds(isFocused: focusedField == .name))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .name)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                                .accessibilityLabel("대원명")
                                .accessibilityIdentifier("join.name")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(Field.name)
                        }
                    }
                    .padding(.horizontal, isLandscape ? DSSpacing.s40 : DSSpacing.s20)
                    .padding(.top, focusedField == nil
                             ? max(0, DSSpacing.s40 - geometry.safeAreaInsets.top) : DSSpacing.s12)
                    .padding(.bottom, DSSpacing.s20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, field in
                    if let field { scroll.scrollTo(field, anchor: .center) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField == nil {
                VStack(spacing: DSSpacing.s12) {
                    ActionButton(isJoining ? "세션 도면 불러오는 중…" : "참가") {
                        focusedField = nil
                        onJoin(pin, memberName.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(!canJoin || isJoining)
                    .accessibilityIdentifier("join.submit")

                    if let onStartDemo {
                        Button(action: onStartDemo) {
                            Label("데모 모드 시작", systemImage: "testtube.2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dsSecondary)
                        .accessibilityHint("PIN과 별도 iPad 없이 Capture의 주요 기능을 체험합니다.")
                        .accessibilityIdentifier("join.demo")
                    }
                }
                .frame(maxWidth: isLandscape ? 381 : .infinity)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, isLandscape ? DSSpacing.s40 : DSSpacing.s20)
                .padding(.top, DSSpacing.s12)
                .padding(.bottom, DSSpacing.s8)
                .background(DSColor.backgroundPrimary)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("이전 입력란", systemImage: "chevron.up") { focusedField = .pin }
                    .labelStyle(.iconOnly)
                    .disabled(focusedField == .pin)
                Button("다음 입력란", systemImage: "chevron.down") { focusedField = .name }
                    .labelStyle(.iconOnly)
                    .disabled(focusedField == .name)
                Spacer()
                Button("완료") { focusedField = nil }
            }
        }
        .foregroundStyle(DSColor.contentPrimary)
        .tint(DSColor.actionPrimary)
        .background(DSColor.backgroundPrimary.ignoresSafeArea())
    }
}

#Preview("01 참가 · 세로") {
    SessionJoinView { pin, name in print("Preview 참가: \(pin), \(name)") }
}

#Preview("01 참가 · 가로 · 입력 완료", traits: .landscapeLeft) {
    SessionJoinView(pin: "123456", memberName: "강유키") { _, _ in print("Preview 참가") }
}

#Preview("01 참가 · 큰 글자") {
    SessionJoinView(onStartDemo: { print("Preview 데모") }) { _, _ in print("Preview 참가") }
        .dynamicTypeSize(.accessibility3)
}
