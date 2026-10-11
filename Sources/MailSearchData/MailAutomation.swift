import Foundation
import MailSearchDomain

public actor MailAutomation: MailAccountSource {
    public init() {}

    public func accounts() throws -> [MailAccount] {
        try Task.checkCancellation()
        guard let script = NSAppleScript(source: Self.discoveryScript) else { throw SearchFailure.automation }
        var error: NSDictionary?
        let result = unsafe script.executeAndReturnError(&error)
        if let error {
            throw Self.failure(error)
        }
        try Task.checkCancellation()
        return Self.decodeAccounts(result)
    }

    static func decodeAccounts(_ result: NSAppleEventDescriptor) -> [MailAccount] {
        (1 ... max(1, result.numberOfItems)).compactMap { index in
            guard let row = result.atIndex(index), row.numberOfItems == 10,
                  let id = row.atIndex(1)?.stringValue else { return nil }
            let kind = AccountKind(rawValue: row.atIndex(4)?.stringValue ?? "") ?? .unsupported
            let addresses = row.atIndex(3)
            return MailAccount(
                id: id, name: row.atIndex(2)?.stringValue ?? "Unavailable account",
                addresses: (1 ... max(1, addresses?.numberOfItems ?? 0))
                    .compactMap { addresses?.atIndex($0)?.stringValue },
                kind: kind,
                connection: ConnectionSettings(
                    host: row.atIndex(5)?.stringValue ?? "", port: Int(row.atIndex(6)?.int32Value ?? 993),
                    username: row.atIndex(7)?.stringValue ?? "",
                    security: row.atIndex(8)?.booleanValue == true ? .tls : .startTLS,
                ),
                unavailableReason: row.atIndex(9)?.booleanValue == true ? nil : "This account is disabled in Mail.",
                discoveryWarnings: (1 ... max(1, row.atIndex(10)?.numberOfItems ?? 0))
                    .compactMap { row.atIndex(10)?.atIndex($0)?.stringValue },
            )
        }
    }

    static func failure(_ error: NSDictionary) -> MailAutomationFailure {
        MailAutomationFailure(code: (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue)
    }

    static let discoveryScript = """
    on run
        with timeout of 20 seconds
            tell application "Mail"
                set output to {}
                repeat with a in every account
                    set accountID to id of a
                    set accountName to name of a
                    set fieldWarnings to {}
                    set discoveredType to "unsupported"
                    try
                        set accountKind to get account type of a
                        if accountKind is imap then set discoveredType to "imap"
                        if accountKind is iCloud then set discoveredType to "iCloud"
                        if accountKind is pop then set discoveredType to "pop"
                    on error number code
                        set end of fieldWarnings to "account type (error " & code & ")"
                        try
                            set accountClass to class of a
                            if accountClass is imap account then set discoveredType to "imap"
                            if accountClass is iCloud account then set discoveredType to "iCloud"
                            if accountClass is pop account then set discoveredType to "pop"
                        end try
                    end try
                    set discoveredAddresses to {}
                    try
                        set fieldValue to get email addresses of a
                        if fieldValue is missing value then error number -1728
                        set discoveredAddresses to fieldValue as list
                    on error number code
                        set end of fieldWarnings to "email addresses (error " & code & ")"
                    end try
                    set discoveredHost to ""
                    try
                        set fieldValue to get server name of a
                        if fieldValue is missing value then error number -1728
                        set discoveredHost to fieldValue as text
                    on error number code
                        set end of fieldWarnings to "server name (error " & code & ")"
                    end try
                    set discoveredPort to 0
                    try
                        set fieldValue to get port of a
                        if fieldValue is missing value then error number -1728
                        set discoveredPort to fieldValue as integer
                    on error number code
                        set end of fieldWarnings to "port (error " & code & ")"
                    end try
                    set discoveredUsername to ""
                    try
                        set fieldValue to get user name of a
                        if fieldValue is missing value then error number -1728
                        set discoveredUsername to fieldValue as text
                    on error number code
                        set end of fieldWarnings to "user name (error " & code & ")"
                    end try
                    set discoveredTLS to true
                    try
                        set fieldValue to get uses ssl of a
                        if fieldValue is missing value then error number -1728
                        set discoveredTLS to fieldValue as boolean
                    on error number code
                        set end of fieldWarnings to "uses ssl (error " & code & ")"
                    end try
                    set discoveredEnabled to true
                    try
                        set fieldValue to get enabled of a
                        if fieldValue is missing value then error number -1728
                        set discoveredEnabled to fieldValue as boolean
                    on error number code
                        set end of fieldWarnings to "enabled (error " & code & ")"
                    end try
                    set end of output to {accountID, accountName, discoveredAddresses, discoveredType, ¬
                        discoveredHost, discoveredPort, discoveredUsername, discoveredTLS, discoveredEnabled, fieldWarnings}
                end repeat
                return output
            end tell
        end timeout
    end run
    """
}
