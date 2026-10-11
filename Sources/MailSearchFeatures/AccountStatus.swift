import MailSearchDomain

public struct AccountStatus: Equatable {
    public let connection: ConnectionSettings
    public var progress = "Waiting"
    public var notices: [String] = []
    public var count = 0
    public var isCached = false
    public var outcome: AccountOutcome?

    public var label: String {
        switch outcome {
        case .complete: count == 0 ? "No matches" : "Complete: \(count) matches"
        case .incomplete: "Incomplete: \(count) matches"
        case .cancelled: "Cancelled: \(count) matches retained"
        case let .failed(error): error.rawValue
        case nil: progress
        }
    }
}
