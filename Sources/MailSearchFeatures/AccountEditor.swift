// swiftlint:disable no_magic_numbers - SwiftUI layout values are points, spacing and opacity.
import MailSearchDomain
import SwiftUI

struct AccountEditor: View {
    // MARK: Lifecycle

    init(model: SearchModel, account: MailAccount) {
        self.model = model
        self.account = account
        var draft = model.connection(for: account)
        if draft.security == .startTLS {
            draft.security = .tls
            draft.port = 993
        }
        _connection = State(initialValue: draft)
    }

    // MARK: Internal

    let model: SearchModel
    let account: MailAccount

    // swiftlint:disable closure_body_length - Keep the declarative view hierarchy and accessibility order together.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect \(account.name)").font(.title2)
            Text("Mail’s account label and sending addresses do not choose the login below.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("IMAP login") {
                TextField("Primary mail address or username", text: $connection.username)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("IMAP login")
                    .disabled(isSaving)
            }
            .help("The username sent to the IMAP server; this can differ from the Apple Account login")
            switch MailProvider(account: account) {
            case .gmail:
                Text("Use a Google app password for this account.")
                Link(
                    "Create App Password",
                    destination: MailProvider.googleAppPasswordURL(email: connection.username),
                )
                Text(
                    """
                    The link requests this Google account. Check the selected account before creating the \
                    app password.
                    """,
                )
                .font(.caption)
                .foregroundStyle(.secondary)

            case .iCloud:
                Text(
                    """
                    Use your primary iCloud Mail address or its username, not an alias, custom-domain \
                    address or numeric Mail identifier.
                    """,
                ).fixedSize(horizontal: false, vertical: true)
                Link("Open Apple Account", destination: URL(string: "https://account.apple.com")!)

            case .other:
                Text("Use the password or app-specific password your provider permits for IMAP.")
            }
            SecureField(
                MailProvider(account: account).passwordLabel,
                text: $password,
            )
            .textContentType(.password)
            .privacySensitive()
            .textFieldStyle(.roundedBorder)
            .disabled(isSaving)
            Text("Saved securely in Keychain. Mail’s existing sign-in cannot be shared with another app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if MailProvider(account: account) == .other {
                Form {
                    TextField("IMAP server", text: $connection.host)
                    TextField("Port", value: $connection.port, format: .number.grouping(.never))
                    LabeledContent("Encryption", value: "TLS 1.2 or later")
                }.disabled(isSaving)
                if model.connection(for: account).security == .startTLS {
                    Text(SearchFailure.unsupportedTransport.rawValue)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.credentialAccounts.contains(account.id) {
                Text(
                    """
                    Leave the password blank to reuse it when changing the username on this server. A \
                    different server needs a password.
                    """,
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                SelectableText(text: error)
            }
            HStack {
                if isSaving {
                    ProgressView("Verifying and saving…").controlSize(.small)
                }
                Spacer()
                Button("Cancel") { saveTask?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    isSaving = true
                    error = nil
                    saveTask = Task {
                        defer { isSaving = false; saveTask = nil }
                        do {
                            try await model.configure(account, connection: connection, password: password)
                            password = ""
                            dismiss()
                        } catch {
                            guard Task.isCancelled == false else {
                                return
                            }

                            self.error = (error as? SearchFailure ?? .connection).rawValue
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(canConnect == false || isSaving)
                .help("Verify the login over TLS, then save it securely in Keychain")
            }
            .buttonStyle(.glass)
        }
        .padding(24)
        .frame(width: 530)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .onDisappear { saveTask?.cancel(); password = "" }
    }

    // swiftlint:enable closure_body_length

    // MARK: Private

    @State private var connection: ConnectionSettings
    @State private var password = ""
    @State private var error: String?
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private var canConnect: Bool {
        connection.isValid && (password.isEmpty == false ||
            (model.credentialAccounts.contains(account.id) && connection
                .hasSameServer(as: model.connection(for: account))))
    }
}

// swiftlint:enable no_magic_numbers
