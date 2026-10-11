import SwiftUI

public struct SettingsView: View {
    private let model: SearchModel
    private let icon: Image
    private let version: String
    private let build: String

    public init(model: SearchModel, icon: Image, version: String, build: String) {
        self.model = model
        self.icon = icon
        self.version = version
        self.build = build
    }

    public var body: some View {
        TabView {
            Tab("Accounts", systemImage: "person.crop.circle") {
                AccountsSettingsView(model: model)
            }
            Tab("About", systemImage: "info.circle") {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            icon.resizable().frame(width: 64, height: 64)
                                .accessibilityHidden(true).help("MailSearch app icon")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("MailSearch").font(.title2.bold())
                                Text("Version \(version) (\(build))").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Text("Search, preview and flag mail on your IMAP servers.")
                        Text("Credentials stay in Keychain. Search results and previews stay in memory.")
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 640, height: 520)
    }
}
