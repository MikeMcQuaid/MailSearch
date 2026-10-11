import MailSearchDomain
import SwiftUI

struct ResultList: View {
    let results: [SearchResult]
    @Binding var selection: MessageLocation?
    let canFlag: (MessageLocation?) -> Bool
    let flag: (MessageLocation) -> Void
    let copyText: (String) -> Void
    let preview: MessagePreview?
    let isPreviewing: Bool
    let previewError: String?
    let expanded: MessageLocation?
    let togglePreview: (MessageLocation) -> Void
    @State private var scrollPosition = ScrollPosition(idType: MessageLocation.self)
    @FocusState private var resultsFocused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            resultsFocused = true
                            togglePreview(result.id)
                        } label: {
                            ResultRow(result: result)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == result.id ? .isSelected : [])
                        .help(expanded == result.id ? "Hide text preview" : "Show text preview")
                        if expanded == result.id {
                            MessagePreviewView(preview: preview, isLoading: isPreviewing, error: previewError)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                                    scrollPosition.scrollTo(id: result.id, anchor: .top)
                                }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(selection == result.id ? Color.accentColor.opacity(0.15) : .clear)
                    .contextMenu {
                        Button(result.isFlagged ? "Unflag" : "Flag") { flag(result.id) }
                            .disabled(!canFlag(result.id))
                        Button("Copy Message Details") {
                            copyText("""
                            Subject: \(result.subject)
                            From: \(result.sender)
                            Date: \(result.date?.formatted(date: .complete, time: .shortened) ?? "Unknown")
                            Account: \(result.accountName)
                            Mailbox: \(result.id.mailbox)
                            Message-ID: \(result.messageID ?? "Unavailable")
                            """)
                        }
                    }
                    .overlay(alignment: .bottom) { Divider() }
                    .id(result.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPosition)
        .focusable().focused($resultsFocused)
        .onChange(of: expanded) {
            if let expanded {
                scrollPosition.scrollTo(id: expanded, anchor: .top)
            }
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { key in
            guard !results.isEmpty else { return .ignored }
            let step = key.key == .downArrow ? 1 : -1
            let index = results.firstIndex { $0.id == selection } ?? (step == 1 ? -1 : results.count)
            let id = results[min(max(index + step, 0), results.count - 1)].id
            selection = id
            scrollPosition.scrollTo(id: id)
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            guard let id = selection else { return .ignored }
            togglePreview(id)
            return .handled
        }
        .accessibilityLabel("Search results")
        .accessibilityHint("Click, Return or Space toggles the text preview without marking the message as read.")
        .transaction { $0.animation = nil }
    }
}

struct ResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.sender).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if let date = result.date {
                    Text(date, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(result.subject).lineLimit(1)
                Spacer(minLength: 4)
                if result.isFlagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Flagged or starred")
                        .help("Flagged or starred on the server")
                }
            }
            Text("\(result.accountName) · \(mailboxDisplayName(result.id.mailbox))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
