import Observation
import SwiftUI
import UIKit

/// UI-only coordination. Never owns or resets the registration draft.
@MainActor
@Observable
final class FloorPlanImportPresentation: NSObject {
    var isPresented = false
    private(set) var isPreparing = false
    private(set) var message: String?
    @ObservationIgnored weak var canvas: LocalFloorPlanCanvasView?
    @ObservationIgnored weak var anchor: UIView?
    @ObservationIgnored private var keyboardVisible = false
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var timeout: DispatchWorkItem?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    deinit {
        timeout?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func request(dismissFocus: () -> Void) {
        guard !isPreparing, !isPresented else { return }
        message = nil
        guard let window = anchor?.window else { return }
        guard canvas?.prepareForFileSelection() != false else {
            message = "편집 중인 획이 끝난 뒤 다시 선택해주세요."
            return
        }
        isPreparing = true
        requestID = UUID()
        let token = requestID
        dismissFocus()
        guard window.endEditing(true) else {
            fail("입력을 종료하지 못했습니다. 키보드를 닫고 다시 선택해주세요.")
            return
        }
        // A missing keyboard callback must not leave all controls disabled forever.
        // This is a failure timeout, not a guessed delay before presenting the picker.
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.requestID == token, self.isPreparing else { return }
            self.fail("키보드 전환이 끝나지 않았습니다. 다시 선택해주세요.")
        }
        timeout = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: expiry)
        schedulePresentation()
    }

    func finish() {
        requestID = UUID()
        timeout?.cancel()
        timeout = nil
        isPreparing = false
        isPresented = false
        canvas?.resumeAfterFileSelection()
    }

    private func fail(_ text: String) {
        finish()
        message = text
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        keyboardVisible = true
    }

    @objc private func keyboardDidHide(_ notification: Notification) {
        keyboardVisible = false
        schedulePresentation()
    }

    private func schedulePresentation() {
        let token = requestID
        // Keep presentation out of the responder/keyboard callback and SwiftUI update stack.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.requestID == token, self.isPreparing,
                  !self.keyboardVisible else { return }
            guard self.anchor?.window != nil else { self.finish(); return }
            self.timeout?.cancel()
            self.timeout = nil
            self.isPreparing = false
            self.isPresented = true
        }
    }
}

/// Finds only this screen's window; never dismisses editing in a different scene.
struct FloorPlanInputAnchor: UIViewRepresentable {
    let presentation: FloorPlanImportPresentation
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        presentation.anchor = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
