import Foundation
import SwiftTerm

final class BellNotifyingTerminalView: LocalProcessTerminalView {
    var onAttention: (() -> Void)?

    override func bell(source: Terminal) {
        super.bell(source: source)
        onAttention?()
    }
}
