// swiftlint:disable no_magic_numbers - SwiftUI layout values are points, spacing and opacity.
import MailSearchDomain
import SwiftUI

// MARK: - SearchView

public struct SearchView: View {
    // MARK: Lifecycle

    public init(
        model: SearchModel,
        showSettings: @escaping () -> Void,
        quit: @escaping () -> Void,
        copyText: @escaping (String) -> Void,
    ) {
        self.model = model
        self.showSettings = showSettings
        self.quit = quit
        self.copyText = copyText
    }

    // MARK: Public

    // swiftlint:disable closure_body_length - Keep the declarative view hierarchy and accessibility order together.
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField(
                    model.flaggedOnly ? "Narrow flagged mail by phrase" : "Search all mail for a phrase",
                    text: $model.queryText,
                )
                .accessibilityLabel(model.flaggedOnly ? "Search flagged mail" : "Search all mail")
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { model.submit() }
                .help("Search for this whole phrase in message headers and text. Gmail quoting is automatic.")
                Button("Search", systemImage: "magnifyingglass") { model.submit() }
                    .labelStyle(.iconOnly)
                    .help("Submit this search to the selected servers")
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.flaggedOnly == false && model.queryText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty)
                if model.isSearching || model.isStopping {
                    Button("Stop", systemImage: "xmark.circle") { model.cancel() }
                        .labelStyle(.iconOnly)
                        .help("Cancel the current search and keep partial results")
                        .disabled(model.isSearching == false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)
            HStack(spacing: 6) {
                GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach([false, true], id: \.self) { flagged in
                            Button {
                                if flagged {
                                    model.showFlagged()
                                } else {
                                    model.showAllMail(); searchFocused = true
                                }
                            } label: {
                                Label(
                                    flagged ? "Flagged" : "All Mail",
                                    systemImage: flagged ? "flag.fill" : "tray.fill",
                                )
                                .fontWeight(model.flaggedOnly == flagged ? .semibold : .regular)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular
                                .tint(model.flaggedOnly == flagged ? .accentColor.opacity(0.3) : .clear)
                                .interactive())
                            .accessibilityAddTraits(model.flaggedOnly == flagged ? .isSelected : [])
                            .help(flagged ? "Show flagged or starred mail immediately" :
                                "Search all selectable server mailboxes")
                        }
                    }
                }
                Menu {
                    ForEach(model.accounts) { account in
                        Toggle(account.name, isOn: Binding(
                            get: { model.isEnabled(account) },
                            set: { model.setEnabled($0, account: account) },
                        )).disabled(account.exclusion != nil)
                    }
                } label: { Label("Accounts", systemImage: "tray.2") }
                    .labelStyle(.iconOnly)
                    .help("Show or hide accounts now; deselecting cancels that account’s search")
                Spacer()
                Button(
                    model.expanded == nil ? "Show Preview" : "Hide Preview",
                    systemImage: "doc.text.magnifyingglass",
                ) {
                    if let id = model.selection {
                        model.togglePreview(id)
                    }
                }
                .labelStyle(.iconOnly)
                .help("Show or hide the selected message’s text preview, including while searching")
                .disabled(model.selectedResult == nil)
                Button(model.selectedResult?.isFlagged == true ? "Unflag" : "Flag", systemImage: "flag") {
                    Task { await model.toggleFlag(model.selection) }
                }
                .labelStyle(.iconOnly)
                .help("Add or remove this message’s server flag without marking it as read")
                .disabled(model.canFlag(model.selection) == false)
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            Divider()
            Group {
                if model.hasSearched {
                    ResultList(
                        results: model.results.rows,
                        selection: $model.selection,
                        canFlag: model.canFlag,
                        flag: { id in Task { await model.toggleFlag(id) } },
                        copyText: copyText,
                        preview: model.preview,
                        isPreviewing: model.isPreviewing,
                        previewError: model.previewError,
                        expanded: model.expanded,
                        togglePreview: model.togglePreview,
                    )
                    .frame(minHeight: 130)
                } else {
                    ContentUnavailableView(
                        "Search your mail",
                        systemImage: "magnifyingglass",
                        description: Text("Configure accounts in Settings, then search or choose Flagged."),
                    )
                    .frame(minHeight: 130)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if let notice = model.flagNotice {
                    Text(notice)
                }
                if let error = model.error {
                    SelectableText(text: error, caption: true)
                }
                if model.statuses.isEmpty == false {
                    DisclosureGroup("Account progress and details") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(model.accounts) { account in
                                    if let status = model.statuses[account.id] {
                                        Text(account.name).bold()
                                        AccountStatusView(status: status)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 130)
                    }
                }
                if model.statuses.values.contains(where: \.isCached) {
                    Text(model
                        .isSearching ? "Showing cached results while refreshing." :
                        "Some cached results could not be refreshed.")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Button("Settings…", systemImage: "gearshape") { showSettings(); openSettings() }
                        .labelStyle(.iconOnly)
                        .help("Configure accounts and app passwords")
                        .keyboardShortcut(",", modifiers: .command)
                    if model.isSearching || model.isStopping {
                        ProgressView().controlSize(.small).help("Search in progress")
                    }
                    Text(model.summary)
                        .accessibilityAddTraits(.updatesFrequently)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.flagging != nil {
                        ProgressView().controlSize(.small).help("Saving the server flag")
                    }
                    Button("Quit MailSearch", systemImage: "rectangle.portrait.and.arrow.forward", action: quit)
                        .labelStyle(.iconOnly)
                        .help("Quit MailSearch")
                        .keyboardShortcut("q", modifiers: .command)
                }
            }
            .font(.caption)
            .padding(8)
            .textSelection(.enabled)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .onChange(of: model.selection) { model.selectionDidChange() }
        .task {
            if model.accounts.isEmpty {
                await model.refresh()
            }
            if model.selectedResult != nil {
                model.loadPreview()
            }
            searchFocused = true
        }
    }

    // swiftlint:enable closure_body_length

    // MARK: Private

    @Bindable private var model: SearchModel
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool

    private let showSettings: () -> Void
    private let quit: () -> Void
    private let copyText: (String) -> Void
}

// MARK: - AccountStatusView

struct AccountStatusView: View {
    // MARK: Internal

    let status: AccountStatus

    var body: some View {
        SelectableText(text: details, caption: true)
    }

    // MARK: Private

    private var details: String {
        var lines = [status.label] + status.notices
        if status.isCached {
            lines.append("Cached results, not yet refreshed.")
        }
        if case .failed = status.outcome {
            lines += [
                "IMAP login used: \(status.connection.username)",
                "Server: \(status.connection.host):\(status.connection.port) (\(status.connection.security.rawValue))",
            ]
        }
        return lines.joined(separator: "\n\n")
    }
}

// swiftlint:enable no_magic_numbers
