import Foundation

public struct MailAutomationFailure: Error, Sendable, LocalizedError {
    // MARK: Lifecycle

    public init(code: Int?) {
        self.code = code
    }

    // MARK: Public

    public let code: Int?

    // swiftlint:disable no_magic_numbers - Public AppleScript error codes are protocol values.
    public var errorDescription: String? {
        let advice: String =
            switch code {
            case -1_743:
                """
                macOS denied Mail automation. Allow MailSearch → Mail in System Settings → \
                Privacy & Security → Automation.
                If it is already enabled, quit MailSearch, switch that permission off and on, then reopen MailSearch.
                """

            case -1_712:
                """
                Mail timed out. Open Mail, let it finish synchronising and retry.
                Server searches and previews remain available.
                """

            case -10_004:
                """
                Mail rejected the automation request with a privilege error.
                Quit and reopen MailSearch from Finder in your normal Mac session, then retry with Mail open.
                If it persists with Automation enabled, report this error code.
                """

            case -600,
                 -609:
                "Mail could not be reached. Open Mail and retry. Server searches and previews remain available."

            case nil:
                SearchFailure.automation.rawValue

            default:
                """
                Mail could not complete the scripting request. Retry with Mail open and report this error \
                code if it persists.
                """
            }
        return advice + (code.map { "\nMail scripting error: \($0)." } ?? "")
    }
    // swiftlint:enable no_magic_numbers
}
