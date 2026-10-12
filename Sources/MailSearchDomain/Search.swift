import Foundation

// MARK: - SearchQuery

public struct SearchQuery: Sendable, Equatable {
    // MARK: Lifecycle

    // swiftlint:disable no_magic_numbers - The query limit is 1 KiB of UTF-8, independent of character count.
    public init(_ text: String, flaggedOnly: Bool = false) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false || flaggedOnly, trimmed.utf8.count <= 1_024,
              trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) == false
        else {
            throw SearchFailure.invalidQuery
        }

        self.text = trimmed
        self.flaggedOnly = flaggedOnly
    }

    // swiftlint:enable no_magic_numbers

    // MARK: Public

    public let text: String
    public let flaggedOnly: Bool

    public var gmailPhrase: String? {
        guard text.isEmpty == false, text.contains("\"") == false, text.contains("\\") == false else {
            return nil
        }

        return "\"\(text)\""
    }
}

// MARK: - MessageLocation

public struct MessageLocation: Sendable, Hashable {
    // MARK: Lifecycle

    public init(accountID: String, mailbox: String, uidValidity: UInt32, uid: UInt32) {
        self.accountID = accountID
        self.mailbox = mailbox
        self.uidValidity = uidValidity
        self.uid = uid
    }

    // MARK: Public

    public let accountID: String
    public let mailbox: String
    public let uidValidity: UInt32
    public let uid: UInt32
}

// MARK: - SearchResult

public struct SearchResult: Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: MessageLocation,
        accountName: String,
        subject: String,
        sender: String,
        date: Date?,
        messageID: String?,
        isFlagged: Bool = false,
    ) {
        self.id = id
        self.accountName = accountName
        self.subject = subject
        self.sender = sender
        self.date = date
        self.messageID = MessageIdentity.normalise(messageID)
        self.isFlagged = isFlagged
    }

    // MARK: Public

    public let id: MessageLocation
    public let accountName: String
    public let subject: String
    public let sender: String
    public let date: Date?
    public let messageID: String?
    public var isFlagged: Bool
}

// MARK: - MessageIdentity

/// Validation of diagnostic Message-ID headers.
public enum MessageIdentity {
    // swiftlint:disable no_magic_numbers - RFC 5322 limits each header line to 998 octets.
    /// Returns a bounded, normalised Message-ID or nil for invalid input.
    public static func normalise(_ value: String?) -> String? {
        guard var value else {
            return nil
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<"), value.hasSuffix(">") {
            value = String(value.dropFirst().dropLast())
        }
        guard value.contains("@"), value.hasPrefix("@") == false, value.hasSuffix("@") == false,
              value.utf8.count <= 998,
              value.unicodeScalars.contains(where: { scalar in
                  CharacterSet.whitespacesAndNewlines.contains(scalar) || CharacterSet.controlCharacters
                      .contains(scalar)
                      || "<>".unicodeScalars.contains(scalar)
              }) == false
        else {
            return nil
        }

        return value
    }
    // swiftlint:enable no_magic_numbers
}

// MARK: - ResultCollection

public struct ResultCollection: Sendable, Equatable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public private(set) var rows: [SearchResult] = []

    public mutating func setFlag(_ flagged: Bool, for id: MessageLocation) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else {
            return
        }

        rows[index].isFlagged = flagged
    }

    public mutating func append(_ batch: [SearchResult]) {
        for result in batch where identities.insert(result.id).inserted {
            rows.append(result)
        }
        rows.sort { first, second in
            if (first.date ?? .distantPast) != (second.date ?? .distantPast) {
                return (first.date ?? .distantPast) > (second.date ?? .distantPast)
            }
            return (first.id.accountID, first.id.mailbox, first.id.uidValidity, first.id.uid) <
                (second.id.accountID, second.id.mailbox, second.id.uidValidity, second.id.uid)
        }
    }

    // MARK: Private

    private var identities: Set<MessageLocation> = []
}

// MARK: - SearchLimits

/// Explicit resource budgets for server searches.
public enum SearchLimits {
    /// Maximum simultaneous account searches, including those draining cancellation.
    public static let concurrentAccounts = 2
    /// Maximum messages per metadata fetch.
    public static let metadataBatch = 50
    /// Maximum displayed results from one account.
    public static let resultsPerAccount = 2_000
    /// Maximum selectable mailboxes visited per account.
    public static let mailboxesPerAccount = 500
    /// Maximum UID search windows visited per account.
    public static let windowsPerAccount = 2_000
    /// Number of UIDs in each search window.
    public static let uidWindow: UInt32 = 10_000

    /// Clamps a search window to the server’s UIDNEXT snapshot.
    public static func window(start: UInt32, uidNext: UInt32) -> ClosedRange<UInt32>? {
        guard start > 0, start < uidNext else {
            return nil
        }

        return start ... UInt32(min(UInt64(start) + UInt64(uidWindow) - 1, UInt64(uidNext) - 1))
    }
}

// MARK: - AccountOutcome

public enum AccountOutcome: Sendable, Equatable {
    case complete
    case incomplete
    case cancelled
    case failed(SearchFailure)
}

// MARK: - SearchUpdate

public enum SearchUpdate: Sendable, Equatable {
    case progress(String)
    case batch([SearchResult])
    case notice(String)
}

// MARK: - SearchFailure

public enum SearchFailure: String, Error, Sendable, LocalizedError {
    case invalidQuery = "Enter up to 1,024 bytes of plain text without control characters, or choose Flagged only."
    case settings = "Correct the server, port, username and TLS settings before searching."
    case unsupportedTransport = """
    STARTTLS is no longer supported. In Account Settings, enter your provider’s implicit TLS port
    (usually 993) and save the password again.
    """
    case credentials = "Enter this account’s password in Settings before connecting."
    case verificationInProgress = "A connection test is already running. Wait for it to finish before testing again."
    case iCloudAuthentication = """
    iCloud rejected the login. Try the primary mail username before @ in Account Settings.
    If that also fails, save a newly generated app-specific password from the same Apple Account.
    """
    case gmailAuthentication = """
    Gmail rejected the login. Use the full Google account email and its app password in Settings.
    A regular Google password will not work.
    """
    case authentication = """
    Authentication failed or expired. Check your credentials and whether your provider permits IMAP.
    """
    case connection = """
    The server disconnected or could not establish a verified TLS connection. Check the server settings \
    and network.
    """
    case timeout = "The server timed out. Results are incomplete; submit again to retry."
    case server = "The server rejected the request or returned unsupported data. Results are incomplete."
    case charset = "The server does not support this search character set. Try ASCII text."
    case readOnly = "The mailbox did not confirm read-only access for EXAMINE. It was not searched."
    case uidValidity = "The mailbox did not provide a valid UIDVALIDITY value. It was not searched."
    case uidNext = "The mailbox did not provide a valid UIDNEXT value. It was not searched."
    case automation = "Mail could not complete the scripting request. Open Mail and retry."
    case keychain = """
    Keychain could not access MailSearch’s saved passwords. Check MailSearch’s access in Keychain Access.
    """
    case keychainAccess = """
    Keychain access was denied or cancelled. No account will prompt again automatically this session.
    Quit and reopen MailSearch to retry, or save credentials in Settings. The macOS prompt requests your login
    keychain password. If it is rejected, choose Deny; do not reset your keychain.
    """
    case staleMessage = """
    This message’s server identity has changed or it no longer exists.
    Search again before previewing or changing flags.
    """
    case flagUnavailable = "This mailbox does not confirm support for persistent flags. Nothing was changed."
    case flagUnconfirmed = "The flag could not be confirmed. It may have changed on the server; search again to check."
    case previewUnavailable = "No previewable text was returned for this message."

    // MARK: Public

    public var errorDescription: String? {
        rawValue
    }
}
