import Foundation
import MailSearchDomain

public extension SearchModel {
    /// Dismisses a preview when keyboard selection moves elsewhere.
    func selectionDidChange() {
        if expanded != selection {
            cancelPreview()
        }
    }

    /// Expands or collapses the preview at this exact message location.
    func togglePreview(_ id: MessageLocation) {
        if expanded == id {
            cancelPreview()
        } else {
            selection = id
            loadPreview()
        }
    }

    // swiftlint:disable function_body_length - Sequential operation and cleanup.
    /// Loads the selected preview, rejecting cancelled or replaced replies.
    func loadPreview() {
        let previous = previewTask
        previous?.cancel()
        previewGeneration = UUID()
        let token = previewGeneration
        let cacheToken = cacheGeneration
        preview = nil
        previewError = nil
        expanded = selection
        guard let result = selectedResult, let connection = statuses[result.id.accountID]?.connection else {
            isPreviewing = false
            return
        }

        let key = MailCacheKey.preview(
            connectionKey: connection.credentialKey(accountID: result.id.accountID),
            location: result.id,
        )
        if let cached = previewCache.value(for: key) {
            preview = cached
            isPreviewing = false
            return
        }
        isPreviewing = true
        previewTask = Task {
            await previous?.value
            guard Task.isCancelled == false, previewGeneration == token else {
                return
            }

            defer {
                if previewGeneration == token {
                    isPreviewing = false; previewTask = nil
                }
            }
            do {
                let value = try await previewer.preview(result.id, connection: connection)
                guard Task.isCancelled == false, previewGeneration == token else {
                    return
                }

                preview = value
                if cacheToken == cacheGeneration {
                    previewCache.insert(
                        value,
                        for: key,
                        // swiftlint:disable:next no_magic_numbers - Preview identity overhead.
                        bytes: value.text.utf8.count + 256,
                    )
                }
            } catch {
                guard Task.isCancelled == false, previewGeneration == token else {
                    return
                }

                previewError = (error as? SearchFailure ?? .previewUnavailable).rawValue
            }
        }
    }

    // swiftlint:enable function_body_length

    /// Cancels the active preview and rejects its pending response.
    func cancelPreview() {
        previewGeneration = UUID()
        expanded = nil
        previewTask?.cancel()
        preview = nil
        previewError = nil
        isPreviewing = false
    }

    internal func waitForPreview() async {
        await previewTask?.value
    }
}
