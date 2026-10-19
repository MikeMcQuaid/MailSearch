// swiftlint:disable no_magic_numbers - SwiftUI layout values are points, spacing and opacity.
import MailSearchData
import MailSearchFeatures
import SwiftUI

@main
struct MailSearchApp: App {
    // MARK: Lifecycle

    init() {
        NSApplication.shared.applicationIconImage = Self.icon
        let credentials = KeychainCredentials()
        let client = SwiftMailSearchClient(credentials: credentials)
        _model = State(initialValue: SearchModel(
            source: MailAutomation(),
            client: client,
            credentials: credentials,
            settings: DefaultsSettings(),
            flagger: client,
            previewer: client,
        ))
    }

    // MARK: Internal

    var body: some Scene {
        MenuBarExtra {
            SearchView(
                model: model,
                showSettings: {
                    NSApp.keyWindow?.orderOut(nil)
                    NSApp.activate()
                },
                quit: { model.close(); NSApp.terminate(nil) },
                copyText: { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                },
            )
            .frame(width: 420, height: 620)
            .onDisappear { model.cancelPreview() }
        } label: {
            // swiftlint:disable:next prefer_asset_symbols - SwiftPM checks this file without the app's asset symbols.
            Image("MenuBarIcon")
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

    // MARK: Private

    private static let icon: NSImage = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url)
        else {
            preconditionFailure("The app bundle must contain AppIcon.icns")
        }

        return image
    }()

    @State private var model: SearchModel
}

// swiftlint:enable no_magic_numbers
