import MailSearchDomain

public struct AccountStatus: Equatable {
    public let connection: ConnectionSettings
    public var progress = "Waiting"
    public var notices: [String] = []
    public var resultCount = 0
    public var isCached = false
    public var outcome: AccountOutcome?

    public var label: String {
        switch outcome {
        case .complete:
            resultCount == 0 ? "No matches" : "Complete: \(resultCount) matches"

        case .incomplete:
            "Incomplete: \(resultCount) matches"

        case .cancelled:
            "Cancelled: \(resultCount) matches retained"

        case let .failed(error):
            error.rawValue

        case nil:
            progress
        }
    }
}
