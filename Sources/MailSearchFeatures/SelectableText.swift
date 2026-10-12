import SwiftUI

// MARK: - SelectableText

struct SelectableText: NSViewRepresentable {
    let text: String
    var caption = false

    func makeNSView(context _: Context) -> NSTextView {
        let view = CopyableTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.importsGraphics = false
        view.drawsBackground = false
        view.textColor = .labelColor
        view.font = .preferredFont(forTextStyle: caption ? .caption1 : .body)
        view.textContainerInset = .zero
        unsafe view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false
        // SwiftUI owns the frame, including after scroll bars change the available width.
        view.isVerticallyResizable = false
        unsafe view.textContainer?.widthTracksTextView = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: NSTextView, context _: Context) {
        if view.string != text {
            view.string = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context _: Context) -> CGSize? {
        guard let width = proposal.width, let container = unsafe nsView.textContainer,
              let layout = unsafe nsView.layoutManager
        else {
            return nil
        }

        container.containerSize = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(1, ceil(layout.usedRect(for: container).height)))
    }
}

// MARK: - CopyableTextView

private final class CopyableTextView: NSTextView {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if unsafe window?.firstResponder === self,
           event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        {
            switch event.charactersIgnoringModifiers {
            case "c":
                copy(nil); return true

            case "a":
                selectAll(nil); return true

            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
