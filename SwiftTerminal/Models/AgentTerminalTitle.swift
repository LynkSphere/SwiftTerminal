import Foundation

/// Converts a CLI-provided terminal title into the chat title shown by an
/// active Claude Code or Codex session.
enum AgentTerminalTitle {
    static func displayTitle(reportedTitle: String?, foregroundCommand: String?) -> String? {
        guard let reportedTitle,
              let executable = agentExecutable(in: foregroundCommand) else { return nil }

        var title = reportedTitle
            .replacing("\n", with: " ")
            .replacing("\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Claude prefixes its OSC title with a decorative activity glyph.
        if executable == "claude", title.first == "✳" {
            title.removeFirst()
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !title.isEmpty,
              UUID(uuidString: title) == nil,
              title != "Claude Code",
              title != "Codex",
              title != "OpenAI Codex" else { return nil }

        return String(title.prefix(160))
    }

    private static func agentExecutable(in commandLine: String?) -> String? {
        guard let commandLine else { return nil }

        let tokens = commandLine.split { character in
            character.isWhitespace || character == ";" || character == "|" || character == "&"
        }

        for token in tokens.prefix(8) {
            let unquoted = token.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            guard let executable = unquoted.split(separator: "/").last.map(String.init) else { continue }
            if executable == "claude" || executable == "codex" {
                return executable
            }
        }

        return nil
    }
}
