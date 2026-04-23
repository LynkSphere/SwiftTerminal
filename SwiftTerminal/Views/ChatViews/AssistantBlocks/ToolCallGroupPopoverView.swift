import AppKit

final class ToolCallGroupPopoverView: NSView {
    private static let popoverWidth: CGFloat = 480
    private static let padding: CGFloat = 10
    private static let rowSpacing: CGFloat = 2
    private static let maxItems = 10

    init(items: [ToolCallItem]) {
        super.init(frame: .zero)

        let visibleItems = Array(items.prefix(Self.maxItems))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        for item in visibleItems {
            stack.addArrangedSubview(makeRow(for: item))
        }

        if items.count > Self.maxItems {
            let more = NSTextField(labelWithString: "+\(items.count - Self.maxItems) more")
            more.font = .systemFont(ofSize: 11, weight: .regular)
            more.textColor = .secondaryLabelColor
            stack.addArrangedSubview(more)
        }

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.padding),
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
