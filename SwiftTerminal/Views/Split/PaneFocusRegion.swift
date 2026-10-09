import SwiftUI

struct PaneFocusRegion: NSViewRepresentable {
    let pane: Pane

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        pane.focusRegion = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { pane.focusRegion = view }
}
