import MailSearchData
import MailSearchFeatures
import SwiftUI

@main
struct MailSearchApp: App {
    @State private var model: SearchModel
    private static let icon = NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns")!)!

    init() {
        NSApplication.shared.applicationIconImage = Self.icon
        let credentials = KeychainCredentials()
        let client = SwiftMailSearchClient(credentials: credentials)
        _model = State(initialValue: SearchModel(
            source: MailAutomation(), client: client,
            credentials: credentials, settings: DefaultsSettings(), flagger: client, previewer: client,
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            SearchView(model: model, showSettings: {
                NSApp.keyWindow?.orderOut(nil)
                NSApp.activate()
            }, quit: { model.close(); NSApp.terminate(nil) }, copyText: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            })
            .frame(width: 420, height: 620)
            .onDisappear { model.cancelPreview() }
        } label: {
            Image(systemName: "envelope")
                .accessibilityLabel("MailSearch")
                .help("MailSearch: search and flag server mail")
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(
                model: model,
                icon: Image(nsImage: Self.icon),
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            )
        }
    }
}
