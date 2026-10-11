@testable import MailSearchFeatures
import SwiftUI
import Testing

@MainActor @Test func `account details provide native text selection without editing`() throws {
    _ = NSApplication.shared
    let status = AccountStatus(connection: testConnection, notices: ["Fixture details"])
    let host = NSHostingView(rootView: AccountStatusView(status: status))
    host.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
    host.layoutSubtreeIfNeeded()
    let text = try #require(textView(in: host))
    #expect(text.isSelectable && !text.isEditable && !text.isRichText)
    #expect(text.string.contains("Fixture details"))
    text.setSelectedRange(NSRange(location: 0, length: 7))
    host.rootView = AccountStatusView(status: status)
    host.layoutSubtreeIfNeeded()
    #expect(textView(in: host)?.selectedRange() == NSRange(location: 0, length: 7))
}

@MainActor private func textView(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView {
        return text
    }
    return view.subviews.lazy.compactMap { textView(in: $0) }.first
}
