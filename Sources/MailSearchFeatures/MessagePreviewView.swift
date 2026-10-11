import MailSearchDomain
import SwiftUI

struct MessagePreviewView: View {
    let preview: MessagePreview?
    let isLoading: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView("Loading preview…")
                    .help("Fetching only this message’s text without marking it as read")
            } else if let error {
                SelectableText(text: error, caption: true)
            } else if let preview {
                SelectableText(text: preview.text.isEmpty ? "(Empty text body)" : preview.text)
                if preview.isTruncated {
                    Text("Preview limited to 32 KiB.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(8).background(.background, in: .rect(cornerRadius: 6))
    }
}
