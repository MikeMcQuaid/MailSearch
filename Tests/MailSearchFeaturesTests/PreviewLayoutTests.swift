import MailSearchDomain
@testable import MailSearchFeatures
import SwiftUI
import Testing

@MainActor @Test(.serialized, arguments: [false, true], [30, 8])
func `live search keeps the preview visible when newer results arrive`(
    arriveWhileLoading: Bool,
    lines: Int,
) async throws {
    _ = NSApplication.shared
    let client = Client(holdAfterBatch: true)
    let body = String(repeating: "A line of synthetic preview text.\n", count: lines)
    let previewer = Previewer(held: true, text: body)
    let model = SearchModel(
        source: Accounts([account("preview body")]), client: client,
        credentials: Credentials(), settings: Settings(), flagger: Flagger(), previewer: previewer,
    )
    await model.refresh()
    model.showFlagged()
    await client.waitFor("preview body")
    let host = NSHostingView(rootView: SearchView(model: model, showSettings: {}, quit: {}, copyText: { _ in })
        .frame(width: 420, height: 620))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 620)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    window.orderFront(nil)
    window.layoutIfNeeded()
    #expect(window.isVisible)
    #expect(host.bounds.size == NSSize(width: 420, height: 620))
    host.layoutSubtreeIfNeeded()
    let scroll = try #require(views(of: NSScrollView.self, in: host).first)
    scroll.scrollerStyle = .legacy
    try await Task.sleep(for: .milliseconds(50))
    let id = try #require(model.results.rows.first?.id)
    model.togglePreview(id)
    await previewer.wait()
    host.layoutSubtreeIfNeeded()
    if !arriveWhileLoading {
        await previewer.resume()
        await model.waitForPreview()
        try await expectVisiblePreview(body, in: window)
    }
    for uids in [UInt32(2) ... 101, 102 ... 201] {
        await client.addResults(uids.map { uid in
            SearchResult(
                id: MessageLocation(
                    accountID: id.accountID,
                    mailbox: id.mailbox,
                    uidValidity: id.uidValidity,
                    uid: uid,
                ),
                accountName: "Fixture", subject: "Newer result", sender: "Fixture",
                date: Date(timeIntervalSince1970: Double(uid)),
                messageID: nil,
            )
        }, accountID: id.accountID)
        if arriveWhileLoading, model.isPreviewing {
            await previewer.resume()
            await model.waitForPreview()
        }
        try await expectVisiblePreview(body, in: window)
        #expect(scroll.scrollerStyle == .legacy)
        #expect(model.isSearching && model.expanded == id && model.selection == id)
    }
    await client.release("preview body")
    await model.waitForSearch()
    window.contentView = nil
}

@MainActor private func expectVisiblePreview(
    _ body: String, in window: NSWindow, sourceLocation: SourceLocation = #_sourceLocation,
) async throws {
    let host = try #require(window.contentView, sourceLocation: sourceLocation)
    let deadline = ContinuousClock.now + .seconds(5)
    var text: NSTextView?
    repeat {
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        text = views(of: NSTextView.self, in: host).first { $0.string == body }
        if let text {
            let visible = text.visibleRect.intersection(text.bounds)
            if visible.height >= 100, visible.width >= 100 {
                return
            }
        }
        try await Task.sleep(for: .milliseconds(10))
    } while ContinuousClock.now < deadline
    #expect(
        text != nil,
        "Window visible: \(window.isVisible), host frame: \(host.frame)",
        sourceLocation: sourceLocation,
    )
    if let text {
        let visible = text.visibleRect.intersection(text.bounds)
        #expect(
            visible.height >= 100 && visible.width >= 100,
            "Preview frame: \(text.frame), bounds: \(text.bounds), visible: \(text.visibleRect), host: \(host.frame)",
            sourceLocation: sourceLocation,
        )
    }
}

@MainActor private func views<View: NSView>(of type: View.Type, in view: NSView) -> [View] {
    (view as? View).map { [$0] } ?? view.subviews.flatMap { views(of: type, in: $0) }
}
