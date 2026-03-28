import SwiftUI

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    Text(inlineMarkdown(content))
                        .textSelection(.enabled)
                        .font(.body)

                case .code(let language, let content):
                    codeBlock(language: language, content: content)
                }
            }
        }
    }

    private func codeBlock(language: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }

            Text(content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, language.isEmpty ? 8 : 4)
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        ))) ?? AttributedString(text)
    }

    // MARK: - Block Parsing

    private enum Block {
        case text(String)
        case code(language: String, content: String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeContent = ""

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if !inCodeBlock && line.hasPrefix("```") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .newlines)))
                    currentText = ""
                }
                inCodeBlock = true
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeContent = ""
            } else if inCodeBlock && line.hasPrefix("```") {
                blocks.append(.code(language: codeLanguage, content: codeContent.trimmingCharacters(in: .newlines)))
                inCodeBlock = false
                codeLanguage = ""
                codeContent = ""
            } else if inCodeBlock {
                if !codeContent.isEmpty { codeContent += "\n" }
                codeContent += line
            } else {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += line
            }
        }

        if inCodeBlock {
            // Unclosed code block - render as code anyway
            if !codeContent.isEmpty {
                blocks.append(.code(language: codeLanguage, content: codeContent.trimmingCharacters(in: .newlines)))
            }
        }

        if !currentText.isEmpty {
            blocks.append(.text(currentText.trimmingCharacters(in: .newlines)))
        }

        return blocks
    }
}
