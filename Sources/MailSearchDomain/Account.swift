import Foundation

public enum AccountKind: String, Sendable {
    case imap, iCloud, pop, unsupported
}

public enum TransportSecurity: String, Sendable, Codable {
    case tls = "TLS"
    case startTLS = "STARTTLS" // Retained to reject older saved settings explicitly.
}

public struct ConnectionSettings: Sendable, Equatable, Codable {
    public var host: String
    public var port: Int
    public var username: String
    public var security: TransportSecurity

    public init(host: String, port: Int, username: String, security: TransportSecurity) {
        self.host = host
        self.port = port
        self.username = username
        self.security = security
    }

    public var isValid: Bool {
        !host.isEmpty && host.utf8.count <= 253 && (1 ... 65535).contains(port)
            && host.unicodeScalars
            .allSatisfy { CharacterSet.alphanumerics.contains($0) || ".-:".unicodeScalars.contains($0) }
            && !username.isEmpty && username.utf8.count <= 1024
            && !username.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    public func hasSameServer(as other: Self) -> Bool {
        host.lowercased() == other.host.lowercased() && port == other.port && security == other.security
    }

    public func credentialKey(accountID: String) -> String {
        [accountID, host.lowercased(), String(port), security.rawValue, username]
            .map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
    }

    public func normalisedPassword(_ password: String) -> String {
        MailProvider.isGoogleHost(host) ? password.filter { !$0.isWhitespace } :
            MailProvider.isICloudHost(host) ? password.trimmingCharacters(in: .whitespacesAndNewlines) : password
    }
}

public func mailboxDisplayName(_ mailbox: String) -> String {
    for prefix in ["[Gmail]/", "[Google Mail]/"] where mailbox.hasPrefix(prefix) && mailbox.count > prefix.count {
        return String(mailbox.dropFirst(prefix.count))
    }
    return mailbox
}

public struct MailAccount: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let addresses: [String]
    public let kind: AccountKind
    public let connection: ConnectionSettings
    public let unavailableReason: String?
    public let discoveryWarnings: [String]

    public init(
        id: String, name: String, addresses: [String], kind: AccountKind,
        connection: ConnectionSettings, unavailableReason: String? = nil, discoveryWarnings: [String] = [],
    ) {
        self.id = id
        self.name = name
        self.addresses = addresses
        self.kind = kind
        self.connection = connection
        self.unavailableReason = unavailableReason
        self.discoveryWarnings = discoveryWarnings
    }

    public var exclusion: String? {
        if let unavailableReason {
            return unavailableReason
        }
        switch kind {
        case .imap, .iCloud: return nil
        case .pop: return "POP accounts cannot be searched on an IMAP server."
        case .unsupported: return "Mail did not expose this account as IMAP. Exchange and local folders are unsupported."
        }
    }
}

public struct AccountSettings: Sendable, Equatable, Codable {
    public var enabled: Bool
    public var connection: ConnectionSettings?

    public init(enabled: Bool = true, connection: ConnectionSettings? = nil) {
        self.enabled = enabled
        self.connection = connection
    }
}
