import SwiftUI

struct BottomSheetView: View {
    let directoryURL: URL
    @Environment(EditorPanel.self) private var panel
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("editorPanelHeight_v3") private var panelHeight: Double = 250

    private var headerHeight: CGFloat { 30 }

    var body: some View {
        VStack(spacing: 0) {
            dragBorder
            content
        }
        .frame(height: panel.isOpen ? panelHeight : headerHeight, alignment: .top)
        .clipped()
        .background(colorScheme == .dark ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.bar))
    }

    private var dragBorder: some View {
        Rectangle()
            .fill(Color(nsColor: .gridColor))
            .frame(height: 1)
            .overlay {
                Rectangle()
                    .fill(.clear)
                    .frame(height: 8)
                    .contentShape(Rectangle())
                    .cursor(.resizeUpDown)
                    .gesture(resizeGesture)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch panel.content {
        case .file(let url):
            FileEditorPanel(fileURL: url, directoryURL: directoryURL)
        case .diff(let ref):
            DiffPanel(reference: ref)
        case .none:
            PanelLayout {
                // no title
            } actions: {
                // no actions
            } content: {
                // no content
            }
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = -value.translation.height
                panelHeight = max(100, panelHeight + delta)
            }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
