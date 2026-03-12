import SwiftUI

// Used only by ZenModeView — normal reader uses WebView JS highlighting
extension AttributedString {
    static func highlighted(text: String, wordRange: Range<String.Index>?) -> AttributedString {
        guard let wordRange else {
            return AttributedString(text)
        }
        let ns = NSMutableAttributedString(string: text)
        let full = NSRange(text.startIndex..., in: text)
        let active = NSRange(wordRange, in: text)
        ns.addAttribute(.foregroundColor, value: UIColor.label.withAlphaComponent(0.2), range: full)
        ns.addAttribute(.foregroundColor, value: UIColor.label, range: active)
        ns.addAttribute(.font, value: UIFont.systemFont(ofSize: 18, weight: .semibold), range: active)
        return AttributedString(ns)
    }
}
