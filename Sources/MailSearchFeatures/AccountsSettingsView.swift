import MailSearchDomain
import SwiftUI

struct AccountsSettingsView: View {
    let model: SearchModel
    @State private var editingAccount: MailAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Accounts from Mail.app", systemImage: "person.crop.circle").font(.title2)
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small).help("Reading account settings from Mail")
                }
                Button("Refresh Accounts", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .help("Refresh account names and settings through Mail’s public interface")
                    .disabled(model.isRefreshing || model.isSearching || model.isStopping)
            }
            Text("Discovered from Mail.app. MailSearch uses separate credentials for server searches.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(model.accounts) { account in
                        let connection = model.connection(for: account)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle(account.name, isOn: Binding(
                                    get: { model.isEnabled(account) }, set: { model.setEnabled($0, account: account) },
                                )).toggleStyle(.checkbox)
                                    .disabled(account.exclusion != nil)
                                Spacer()
                                if account.exclusion == nil {
                                    Button(model.credentialAccounts
                                        .contains(account.id) ? "Account Settings…" : "Connect…")
                                    {
                                        editingAccount = account
                                    }
                                    .help(
                                        "Set the IMAP username and \(MailProvider(account: account).passwordLabel.lowercased())",
                                    )
                                    .disabled(model.isSearching || model.isStopping || model.isRefreshing)
                                }
                            }
                            Text(account.addresses.joined(separator: ", ")).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if account.exclusion == nil, !account.addresses.contains(connection.username) {
                                LabeledContent(
                                    "IMAP login",
                                    value: connection.username.isEmpty ? "Not configured" : connection.username,
                                )
                            }
                            if let exclusion = account.exclusion {
                                Text(exclusion).font(.caption)
                            } else if !model.credentialAccounts.contains(account.id) {
                                Text("\(MailProvider(account: account).passwordLabel) required").font(.caption)
                            }
                            if !account.discoveryWarnings.isEmpty {
                                DisclosureGroup("Imported settings need review") {
                                    Text(account.discoveryWarnings.joined(separator: ", ")).font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            Text(
                """
                Local ‘On My Mac’ folders and non-IMAP accounts are excluded.
                Searches include selectable server folders, including sent, archive, junk and trash.
                """,
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 640).buttonStyle(.glass).textSelection(.enabled)
        .navigationTitle("MailSearch Settings")
        .task {
            if model.accounts.isEmpty {
                await model.refresh()
            }
        }
        .sheet(item: $editingAccount) { AccountEditor(model: model, account: $0) }
    }
}
