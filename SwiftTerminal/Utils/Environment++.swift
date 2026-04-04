import SwiftUI

extension EnvironmentValues {
    @Entry var isDetachedEditor: Bool = false
    @Entry var editorFontSize: CGFloat = 12
    @Entry var fileTreeAction: (FileTreeAction) -> Void = { _ in }
    @Entry var showInFileTree: (URL) -> Void = { _ in }
}

extension FocusedValues {
    @Entry var editorPanel: EditorPanel?
    @Entry var isMainWindow: Bool?
}
