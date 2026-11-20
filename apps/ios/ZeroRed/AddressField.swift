import SwiftUI
import UIKit

/// 地址输入框：点进来就全选已有内容，直接输入即可替换旧地址。
/// SwiftUI 的 TextField 没有这个行为，所以这里用 UITextField 承载，
/// 同时保留占位文案、Go 键、无障碍标识与外部程序化聚焦。
struct SelectAllAddressField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder: String
    var identifier: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.accessibilityIdentifier = identifier
        field.keyboardType = .webSearch
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .go
        field.clearButtonMode = .never
        field.adjustsFontForContentSizeCategory = true
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        field.addGestureRecognizer(tap)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        if focused && !field.isFirstResponder { field.becomeFirstResponder() }
        else if !focused && field.isFirstResponder { field.resignFirstResponder() }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllAddressField
        init(_ parent: SelectAllAddressField) { self.parent = parent }

        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let field = gesture.view as? UITextField, !(field.text ?? "").isEmpty else { return }
            field.selectAll(nil)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.focused = true
            // 先让系统完成聚焦，再全选，否则选区会被光标重置。
            DispatchQueue.main.async { textField.selectAll(nil) }
        }

        func textFieldDidEndEditing(_ textField: UITextField) { parent.focused = false }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }
}