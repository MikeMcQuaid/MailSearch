import Foundation

public enum MailProvider: Sendable {
    case gmail, iCloud, other

    public var passwordLabel: String {
        switch self {
        case .gmail: "App password"
        case .iCloud: "App-specific password"
        case .other: "Password or app-specific password"
        }
    }

    public init(account: MailAccount) {
        let host = account.connection.host.lowercased()
        if Self.isGoogleHost(host) {
            self = .gmail
        } else if account.kind == .iCloud || Self.isICloudHost(host) {
            self = .iCloud
        } else if host.isEmpty, account.kind == .imap,
                  account.addresses
                  .contains(where: {
                      $0.lowercased().hasSuffix("@gmail.com") || $0.lowercased().hasSuffix("@googlemail.com")
                  })
        {
            self = .gmail
        } else {
            self = .other
        }
    }

    public static func isGoogleHost(_ host: String) -> Bool {
        ["imap.gmail.com", "imap.googlemail.com"].contains(host.lowercased())
    }

    public static func isICloudHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "imap.mail.me.com" || host.hasSuffix(".imap.mail.me.com") || host.hasSuffix("-imap.mail.me.com")
    }

    public static func isICloudAddress(_ address: String) -> Bool {
        ["@icloud.com", "@me.com", "@mac.com"].contains { address.lowercased().hasSuffix($0) }
    }

    public static func googleAppPasswordURL(email: String) -> URL {
        var url = URLComponents(string: "https://myaccount.google.com/apppasswords")!
        url.queryItems = [URLQueryItem(name: "authuser", value: email)]
        return url.url!
    }

    public func fixedEndpoint(_ connection: ConnectionSettings) -> ConnectionSettings {
        guard self != .other else { return connection }
        return ConnectionSettings(
            host: self == .gmail ? "imap.gmail.com" : "imap.mail.me.com",
            port: 993, username: connection.username, security: .tls,
        )
    }

    public func suggestedConnection(for account: MailAccount) -> ConnectionSettings {
        var connection = account.connection
        guard self != .other else { return connection }
        connection = fixedEndpoint(connection)
        if self == .iCloud, connection.username.isEmpty || connection.username.allSatisfy(\.isNumber)
            || (connection.username.contains("@") && !Self.isICloudAddress(connection.username))
        {
            connection.username = account.addresses.first(where: Self.isICloudAddress) ?? ""
        } else if connection.username.isEmpty {
            connection.username = account.addresses.first ?? ""
        }
        return connection
    }
}
