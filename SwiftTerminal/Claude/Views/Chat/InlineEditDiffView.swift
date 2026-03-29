import SwiftUI

struct InlineEditDiffView: View {
    let tool: ToolUseInfo

    private var filePath: String? {
        tool.input["file_path"] as? String
    }

    private var fileName: String {
        guard let path = filePath else { return "file" }
        return (path as NSString).lastPathComponent
    }

    private var fileExtension: String {
        (fileName as NSString).pathExtension
    }

    private var hunk: DiffHunk? {
        if tool.name == "Edit" {
            return hunkFromEdit()
        } else if tool.name == "Write" {
            return hunkFromWrite()
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            HStack(spacing: 5) {
                Image(systemName: tool.name == "Edit" ? "pencil" : "doc.badge.plus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(filePath.map { shortenPath($0) } ?? "file")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if !tool.isComplete {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5))

            // Diff content
            if let hunk {
                HunkTextView(hunk: hunk, fileExtension: fileExtension)
                    .frame(maxHeight: 400)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func hunkFromEdit() -> DiffHunk? {
        let oldString = tool.input["old_string"] as? String ?? ""
        let newString = tool.input["new_string"] as? String ?? ""

        guard !oldString.isEmpty || !newString.isEmpty else { return nil }

        let oldLines = oldString.isEmpty ? [] : oldString.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newString.isEmpty ? [] : newString.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var diffLines: [DiffHunkLine] = []
        var oldNum = 1
        var newNum = 1

        for line in oldLines {
            diffLines.append(DiffHunkLine(content: line, kind: .removed, oldLineNumber: oldNum, newLineNumber: nil))
            oldNum += 1
        }
        for line in newLines {
            diffLines.append(DiffHunkLine(content: line, kind: .added, oldLineNumber: nil, newLineNumber: newNum))
            newNum += 1
        }

        return DiffHunk(header: "", lines: diffLines, patchText: "")
    }

    private func hunkFromWrite() -> DiffHunk? {
        let content = tool.input["content"] as? String ?? ""
        guard !content.isEmpty else { return nil }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Only show first ~50 lines for Write to avoid huge previews
        let truncated = Array(lines.prefix(50))
        let isTruncated = lines.count > 50

        var diffLines: [DiffHunkLine] = []
        for (i, line) in truncated.enumerated() {
            diffLines.append(DiffHunkLine(content: line, kind: .added, oldLineNumber: nil, newLineNumber: i + 1))
        }
        if isTruncated {
            diffLines.append(DiffHunkLine(content: "... \(lines.count - 50) more lines", kind: nil, oldLineNumber: nil, newLineNumber: nil))
        }

        return DiffHunk(header: "", lines: diffLines, patchText: "")
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count <= 3 { return path }
        return ".../" + components.suffix(2).joined(separator: "/")
    }
}
