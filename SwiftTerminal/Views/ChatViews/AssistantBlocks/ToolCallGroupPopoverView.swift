import AppKit

final class ToolCallGroupPopoverView: NSView {
    private static let popoverWidth: CGFloat = 480
    private static let padding: CGFloat = 10
    private static let rowSpacing: CGFloat = 2
    private static let maxHeight: CGFloat = 360

    init(items: [ToolCallItem]) {
        super.init(frame: .zero)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        for item in items {
            stack.addArrangedSubview(makeRow(for: item))
        }

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = documentView

        addSubview(scrollView)

        let heightMatchesContent = scrollView.heightAnchor.constraint(equalTo: documentView.heightAnchor)
        heightMatchesContent.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding),
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.maxHeight),
            heightMatchesContent,

            widthAnchor.constraint(equalToConstant: Self.popoverWidth),
        ])
    }

    private func makeRow(for item: ToolCallItem) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        let statusImage: NSImage?
        let statusTint: NSColor
        switch item.status {
        case .pending:
            statusImage = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            statusTint = .secondaryLabelColor
        case .inProgress:
            statusImage = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
            statusTint = .secondaryLabelColor
        case .completed:
            statusImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusTint = .systemGreen
        case .failed:
            statusImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
            statusTint = .systemRed
        }

        let statusView = NSImageView(image: statusImage ?? NSImage())
        statusView.contentTintColor = statusTint
        statusView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        statusView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusView.widthAnchor.constraint(equalToConstant: 14),
            statusView.heightAnchor.constraint(equalToConstant: 14),
        ])

        let label = NSTextField(labelWithString: item.title)
        label.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.wraps = false

        row.addArrangedSubview(statusView)
        row.addArrangedSubview(label)
        return row
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
