import SwiftUI
import UIKit

/// SwiftUI가 입력 필드·포커스·키보드 툴바를 관리하고, 이 관찰자는 대원명의 입력 규칙을 적용한다.
struct MemberNameInputObserver: UIViewRepresentable {
    static let maximumLength = 20
    @Binding var text: String
    @Binding var showsLimitMessage: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.onAttach = { [weak coordinator = context.coordinator] view in
            coordinator?.attach(from: view)
        }
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            if let view { coordinator?.attach(from: view) }
        }
    }

    static func dismantleUIView(_ view: AttachmentView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class AttachmentView: UIView {
        var onAttach: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                if let self { self.onAttach?(self) }
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MemberNameInputObserver
        private weak var field: UITextField?
        private weak var originalDelegate: (any UITextFieldDelegate)?

        init(_ parent: MemberNameInputObserver) { self.parent = parent }

        func attach(from view: UIView) {
            // nickname이 지정된 대원명만 찾아 PIN에는 연결하지 않는다.
            var ancestor = view.superview
            while let container = ancestor {
                if let target = nameField(in: container) {
                    target.smartInsertDeleteType = .no
                    if field !== target {
                        detach()
                        field = target
                        target.addTarget(self, action: #selector(editingChanged(_:)), for: .editingChanged)
                    }
                    if target.delegate !== self {
                        originalDelegate = target.delegate
                        target.delegate = self
                    }
                    return
                }
                ancestor = container.superview
            }
        }

        func detach() {
            field?.removeTarget(self, action: #selector(editingChanged(_:)), for: .editingChanged)
            if field?.delegate === self { field?.delegate = originalDelegate }
            field = nil
            originalDelegate = nil
        }

        private func nameField(in view: UIView) -> UITextField? {
            if let field = view as? UITextField, field.textContentType == .nickname { return field }
            for child in view.subviews {
                if let field = nameField(in: child) { return field }
            }
            return nil
        }

        // SwiftUI의 포커스·submit 처리는 원래 delegate로 전달한다.
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (originalDelegate?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if originalDelegate?.responds(to: selector) == true { return originalDelegate }
            return super.forwardingTarget(for: selector)
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            if textField.markedTextRange == nil {
                let current = textField.text ?? ""
                guard let replacementRange = Range(range, in: current) else { return false }
                let proposed = current.replacingCharacters(in: replacementRange, with: string)
                if current.count == MemberNameInputObserver.maximumLength,
                   proposed.count > MemberNameInputObserver.maximumLength {
                    parent.showsLimitMessage = true
                    return false
                }
            }
            return originalDelegate?.textField?(textField, shouldChangeCharactersIn: range,
                                                replacementString: string) ?? true
        }

        @objc func editingChanged(_ field: UITextField) {
            guard field.markedTextRange == nil else { return }
            let value = field.text ?? ""
            if value.count > MemberNameInputObserver.maximumLength {
                let cursor = field.selectedTextRange.map { field.offset(from: field.beginningOfDocument, to: $0.start) }
                let limited = String(value.prefix(MemberNameInputObserver.maximumLength))
                field.text = limited
                if let cursor, let position = field.position(from: field.beginningOfDocument,
                                                             offset: min(cursor, limited.utf16.count)) {
                    field.selectedTextRange = field.textRange(from: position, to: position)
                }
                parent.showsLimitMessage = true
            } else if value.count < MemberNameInputObserver.maximumLength, parent.showsLimitMessage {
                parent.showsLimitMessage = false
            }
            if parent.text != (field.text ?? "") { parent.text = field.text ?? "" }
        }
    }
}
