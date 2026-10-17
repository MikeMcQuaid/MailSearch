import Foundation

public enum MailProvider: Sendable {
    case gmail
    case iCloud
    case other

    // MARK: Lifecycle

    public init(account: MailAccount) {
        let host = account.connection.host.lowercased()
        if Self.isGoogleHost(host) {
            self = .gmail
        } else if account.kind == .iCloud || Self.isICloudHost(host) {
            self = .iCloud
        } else if host.isEmpty, account.kind == .imap,
                  account.addresses
                      .contains(where: { address in
                          address.lowercased().hasSuffix("@gmail.com") || address.lowercased()
                              .hasSuffix("@googlemail.com")
                      })
        {
            self = .gmail
        } else {
            self = .other
        }
    }

    // MARK: Public

    public var passwordLabel: String {
        switch self {
        case .gmail:
            "App password"

        case .iCloud:
            "App-specific password"

        case .other:
            "Password or app-specific password"
        }
    }

    public static func isGoogleHost(_ host: String) -> Bool {
        ["imap.gmail.com", "imap.googlemail.com"].contains(host.lowercased())
    }

    public static func isICloudHost(_ host: String) -> Bool {
        let hostname = host.lowercased()
        return hostname == "imap.mail.me.com" || hostname.hasSuffix(".imap.mail.me.com") || hostname
            .hasSuffix("-imap.mail.me.com")
    }

    public static func isICloudAddress(_ address: String) -> Bool {
        ["@icloud.com", "@me.com", "@mac.com"].contains { address.lowercased().hasSuffix($0) }
    }

    public static func googleAppPasswordURL(email: String) -> URL {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "myaccount.google.com"
        url.path = "/apppasswords"
        url.queryItems = [URLQueryItem(name: "authuser", value: email)]
        guard let result = url.url else {
            preconditionFailure("Static app-password URL components must form a URL")
        }

        return result
    }

    public func fixedEndpoint(_ connection: ConnectionSettings) -> ConnectionSettings {
        guard self != .other else {
            return connection
        }

        return ConnectionSettings(
            host: self == .gmail ? "imap.gmail.com" : "imap.mail.me.com",
            // swiftlint:disable:next no_magic_numbers - 993 is the registered implicit-TLS IMAP port.
            port: 993,
            username: connection.username,
            security: .tls,
        )
    }

    public func suggestedConnection(for account: MailAccount) -> ConnectionSettings {
        var connection = account.connection
        guard self != .other else {
            return connection
        }

        connection = fixedEndpoint(connection)
        if self == .iCloud, connection.username.isEmpty || connection.username.allSatisfy(\.isNumber)
            || (connection.username.contains("@") && Self.isICloudAddress(connection.username) == false)
        {
            connection.username = account.addresses.first(where: Self.isICloudAddress) ?? ""
        } else if connection.username.isEmpty {
            connection.username = account.addresses.first ?? ""
        }
        return connection
    }
}
