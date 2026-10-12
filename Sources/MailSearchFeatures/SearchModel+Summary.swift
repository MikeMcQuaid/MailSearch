import MailSearchDomain

public extension SearchModel {
    /// The selected row in the current result collection.
    var selectedResult: SearchResult? {
        results.rows.first { $0.id == selection }
    }

    /// Whether this result can begin an explicit flag operation.
    func canFlag(_ id: MessageLocation?) -> Bool {
        flagging == nil && results.rows.contains { $0.id == id }
    }

    /// User-facing progress and completeness of the submitted search.
    var summary: String {
        if isStopping, isSearching == false {
            return "Stopping the previous search…"
        }
        if isSearching {
            return "Searching… \(results.rows.count) results so far"
        }
        if hasSearched == false {
            return "Search your selected IMAP servers."
        }
        if statuses.isEmpty {
            return "Choose an account to show results."
        }
        if statuses.values.contains(where: { $0.outcome == .cancelled }) {
            return "Search cancelled. \(results.rows.count) partial results retained."
        }
        if statuses.values.contains(where: { $0.outcome != .complete }) {
            return "Incomplete search. \(results.rows.count) results available."
        }
        return results.rows.isEmpty
            ? "No matches in the searched mailboxes."
            : "\(results.rows.count) results. Search complete."
    }
}
