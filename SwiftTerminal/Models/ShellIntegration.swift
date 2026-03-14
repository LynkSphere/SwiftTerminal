import Foundation

struct ShellIntegration {
    let integrationDirectory: URL
    let userConfigDirectory: URL

    static func prepare(using environment: [String: String]) -> ShellIntegration? {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let userConfigDirectory = environment["ZDOTDIR"].map(URL.init(fileURLWithPath:)) ?? homeDirectory

        guard let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let integrationDirectory = applicationSupportDirectory
            .appendingPathComponent("SwiftTerminal", isDirectory: true)
            .appendingPathComponent("ShellIntegration", isDirectory: true)
            .appendingPathComponent("zsh", isDirectory: true)

        do {
            try fileManager.createDirectory(at: integrationDirectory, withIntermediateDirectories: true)
            try writeProxyFiles(to: integrationDirectory)
            return ShellIntegration(
                integrationDirectory: integrationDirectory,
                userConfigDirectory: userConfigDirectory
            )
        } catch {
            assertionFailure("Failed to prepare zsh integration: \(error)")
            return nil
        }
    }

    private static func writeProxyFiles(to directory: URL) throws {
        try proxyContents(for: ".zshenv").write(
            to: directory.appendingPathComponent(".zshenv"),
            atomically: true,
            encoding: .utf8
        )
        try proxyContents(for: ".zprofile").write(
            to: directory.appendingPathComponent(".zprofile"),
            atomically: true,
            encoding: .utf8
        )
        try zshrcContents.write(
            to: directory.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )
        try proxyContents(for: ".zlogin").write(
            to: directory.appendingPathComponent(".zlogin"),
            atomically: true,
            encoding: .utf8
        )
        try proxyContents(for: ".zlogout").write(
            to: directory.appendingPathComponent(".zlogout"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func proxyContents(for fileName: String) -> String {
        """
        if [[ -n "${SWIFTTERMINAL_USER_ZDOTDIR:-}" && -f "${SWIFTTERMINAL_USER_ZDOTDIR}/\(fileName)" ]]; then
            source "${SWIFTTERMINAL_USER_ZDOTDIR}/\(fileName)"
        fi
        """
    }

    private static let zshrcContents = """
    if [[ -n "${SWIFTTERMINAL_USER_ZDOTDIR:-}" && -f "${SWIFTTERMINAL_USER_ZDOTDIR}/.zshrc" ]]; then
        source "${SWIFTTERMINAL_USER_ZDOTDIR}/.zshrc"
    fi

    if [[ -z "${SWIFTTERMINAL_OSC7_HOOKED:-}" ]]; then
        export SWIFTTERMINAL_OSC7_HOOKED=1

        swiftterminal_emit_cwd() {
            printf '\\e]7;%s\\a' "$PWD"
        }

        autoload -Uz add-zsh-hook
        add-zsh-hook chpwd swiftterminal_emit_cwd
        add-zsh-hook precmd swiftterminal_emit_cwd
        swiftterminal_emit_cwd
    fi
    """
}
