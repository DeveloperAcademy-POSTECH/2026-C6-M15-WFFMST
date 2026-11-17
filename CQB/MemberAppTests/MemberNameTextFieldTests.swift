import SwiftUI
import UIKit
import XCTest
@testable import MemberApp

@MainActor
final class MemberNameTextFieldTests: XCTestCase {
    func testJoinScreenKeepsNameFocusedWhileTypingAndSwitchingFields() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: SessionJoinView { _, _ in })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        await settleRendering()
        let name = try XCTUnwrap(textFields(in: host.view).first { $0.textContentType == .nickname })
        let pin = try XCTUnwrap(textFields(in: host.view).first { $0 !== name })

        // 한 번 얻은 포커스가 실제 SwiftUI 재렌더링 이후에도 유지되어야 한다.
        name.becomeFirstResponder()
        await settleRendering()
        XCTAssertTrue(name.isFirstResponder, "첫 번째 탭으로 얻은 포커스 유지")
        name.insertText("a")
        await settleRendering()
        XCTAssertEqual(name.text, "a")
        XCTAssertTrue(name.isFirstResponder, "입력으로 재렌더링되어도 키보드 유지")

        name.insertText(String(repeating: "b", count: 19))
        await settleRendering()
        XCTAssertEqual(name.text?.count, 20)
        XCTAssertTrue(name.isFirstResponder)
        name.insertText("c")
        await settleRendering()
        XCTAssertEqual(name.text?.count, 20)
        XCTAssertTrue(name.isFirstResponder, "제한 안내가 나타나도 포커스 유지")
        name.deleteBackward()
        await settleRendering()
        XCTAssertEqual(name.text?.count, 19)
        XCTAssertTrue(name.isFirstResponder)

        XCTAssertNil(name.inputAccessoryView, "대원명에 별도 UIKit 툴바를 추가하지 않는다")
        attachWindow(window, name: "대원명 키보드 툴바")
        pin.becomeFirstResponder()
        await settleRendering()
        attachWindow(window, name: "PIN 키보드 툴바")
        XCTAssertTrue(pin.isFirstResponder)
        XCTAssertFalse(name.isFirstResponder)

        name.becomeFirstResponder()
        await settleRendering()
        XCTAssertTrue(name.isFirstResponder)
        XCTAssertFalse(pin.isFirstResponder)
        name.insertText("z")
        await settleRendering()
        XCTAssertTrue(name.isFirstResponder)
        try await verifyPastePreservesUnselectedText(in: name)
        name.resignFirstResponder()
        await settleRendering()
        XCTAssertFalse(name.isFirstResponder)
    }

    private func verifyPastePreservesUnselectedText(in field: UITextField) async throws {
        for (initial, offset, length, pasted, expected) in [
            ("abcdefghij", 0, 0, "123456789012345", "1234567890abcdefghij"),
            ("abcdefghijklmnopqrst", 7, 3, "12345", "abcdefg123klmnopqrst"),
            ("abcdefghijklmnopqrst", 0, 20, "123456789012345678901", "12345678901234567890")
        ] {
            field.selectAll(nil)
            field.insertText(initial)
            await settleRendering()
            XCTAssertEqual(field.text, initial)
            let start = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: offset))
            let end = try XCTUnwrap(field.position(from: start, offset: length))
            field.selectedTextRange = field.textRange(from: start, to: end)
            field.paste(itemProviders: [NSItemProvider(object: pasted as NSString)])
            for _ in 0..<8 where field.text != expected { await settleRendering() }
            XCTAssertEqual(field.text, expected)
            XCTAssertTrue(field.isFirstResponder)
        }
    }

    private func settleRendering() async {
        try? await Task.sleep(for: .milliseconds(250))
    }

    private func attachWindow(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    func testExactlyTwentyCharactersDoesNotShowMessageButOverflowDoes() {
        let state = InputState()
        let coordinator = makeCoordinator(state)
        let field = UITextField()
        field.text = String(repeating: "가", count: 20)
        coordinator.editingChanged(field)
        XCTAssertEqual(state.text.count, 20)
        XCTAssertFalse(state.showsMessage)

        field.text! += "나"
        coordinator.editingChanged(field)
        XCTAssertEqual(field.text, String(repeating: "가", count: 20))
        XCTAssertEqual(state.text, field.text)
        XCTAssertTrue(state.showsMessage)

        field.text = String(repeating: "가", count: 19)
        coordinator.editingChanged(field)
        XCTAssertFalse(state.showsMessage)
    }

    func testPastedEmojiAreLimitedByCharactersRatherThanUTF16Units() {
        let state = InputState()
        let coordinator = makeCoordinator(state)
        let field = UITextField()
        let emoji = "👨‍👩‍👧‍👦"
        field.text = String(repeating: emoji, count: 25)
        coordinator.editingChanged(field)
        XCTAssertEqual(state.text, String(repeating: emoji, count: 20))
        XCTAssertTrue(state.showsMessage)
    }

    func testInsertionInMiddleOfFullNameDoesNotDiscardExistingCharacters() {
        let state = InputState()
        let coordinator = makeCoordinator(state)
        let field = UITextField()
        field.text = "abcdefghijklmnopqrst"
        coordinator.editingChanged(field)
        XCTAssertFalse(coordinator.textField(field, shouldChangeCharactersIn: NSRange(location: 5, length: 0),
                                             replacementString: "가"))
        XCTAssertEqual(state.text, "abcdefghijklmnopqrst")
        XCTAssertTrue(state.showsMessage)
        XCTAssertTrue(coordinator.textField(field, shouldChangeCharactersIn: NSRange(location: 5, length: 1),
                                            replacementString: "가"))
    }

    func testMarkedKoreanInputIsNotTruncatedUntilCommitted() {
        let state = InputState()
        let coordinator = makeCoordinator(state)
        let field = UITextField()
        field.text = String(repeating: "가", count: 19)
        coordinator.editingChanged(field)
        let end = field.endOfDocument
        field.selectedTextRange = field.textRange(from: end, to: end)
        field.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0))
        XCTAssertNotNil(field.markedTextRange)
        coordinator.editingChanged(field)
        XCTAssertTrue(field.text?.hasSuffix("ㅎ") == true)
        XCTAssertFalse(state.showsMessage)
        field.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0))
        field.unmarkText()
        coordinator.editingChanged(field)
        XCTAssertEqual(state.text, String(repeating: "가", count: 19) + "한")
        XCTAssertFalse(state.showsMessage)
    }

    private final class InputState {
        var text = ""
        var showsMessage = false
    }

    private func makeCoordinator(_ state: InputState) -> MemberNameInputObserver.Coordinator {
        MemberNameInputObserver(
            text: Binding(get: { state.text }, set: { state.text = $0 }),
            showsLimitMessage: Binding(get: { state.showsMessage }, set: { state.showsMessage = $0 })
        ).makeCoordinator()
    }
}
