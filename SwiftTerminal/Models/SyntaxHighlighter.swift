import AppKit

/// Lightweight regex-based syntax highlighter. No external dependencies.
/// Covers keywords, strings, comments, numbers, and types for common languages.
enum SyntaxHighlighter {

    struct Theme {
        var keyword = NSColor.systemPink
        var string = NSColor.systemRed
        var comment = NSColor.systemGreen
        var number = NSColor.systemBlue
        var type = NSColor.systemTeal
        var preprocessor = NSColor.systemOrange
        var background = NSColor.textBackgroundColor
        var foreground = NSColor.labelColor
        var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    static let defaultTheme = Theme()

    // MARK: - Public

    static func highlight(_ source: String, fileExtension: String, theme: Theme = defaultTheme) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: theme.font,
            .foregroundColor: theme.foreground,
        ]
        let attributed = NSMutableAttributedString(string: source, attributes: base)
        let fullRange = NSRange(location: 0, length: attributed.length)

        let rules = self.rules(for: fileExtension, theme: theme)
        for rule in rules {
            let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options)
            regex?.enumerateMatches(in: source, range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                attributed.addAttribute(.foregroundColor, value: rule.color, range: range)
            }
        }

        return attributed
    }

    // MARK: - Rules

    private struct Rule {
        let pattern: String
        let color: NSColor
        var options: NSRegularExpression.Options = []
    }

    private static func rules(for ext: String, theme: Theme) -> [Rule] {
        let keywords = self.keywords(for: ext)
        var rules: [Rule] = []

        // Numbers
        rules.append(Rule(pattern: #"\b\d+(\.\d+)?\b"#, color: theme.number))

        // Types (capitalized identifiers)
        rules.append(Rule(pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#, color: theme.type))

        // Keywords
        if !keywords.isEmpty {
            let joined = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            rules.append(Rule(pattern: #"\b(?:"# + joined + #")\b"#, color: theme.keyword))
        }

        // Preprocessor / attributes
        switch ext {
        case "swift":
            rules.append(Rule(pattern: #"@\w+"#, color: theme.preprocessor))
            rules.append(Rule(pattern: #"#\w+"#, color: theme.preprocessor))
        case "c", "cpp", "h", "hpp", "m", "mm":
            rules.append(Rule(pattern: #"^\s*#\w+.*$"#, color: theme.preprocessor, options: .anchorsMatchLines))
        case "py":
            rules.append(Rule(pattern: #"@\w+"#, color: theme.preprocessor))
        default:
            break
        }

        // Strings (double-quoted, single-quoted, backtick for JS/TS)
        rules.append(Rule(pattern: #""(?:[^"\\]|\\.)*""#, color: theme.string))
        rules.append(Rule(pattern: #"'(?:[^'\\]|\\.)*'"#, color: theme.string))
        if ["js", "ts", "jsx", "tsx"].contains(ext) {
            rules.append(Rule(pattern: #"`(?:[^`\\]|\\.)*`"#, color: theme.string, options: .dotMatchesLineSeparators))
        }

        // Multi-line comments (applied before single-line so they take precedence)
        rules.append(Rule(pattern: #"/\*[\s\S]*?\*/"#, color: theme.comment, options: .dotMatchesLineSeparators))

        // Single-line comments
        switch ext {
        case "py", "rb", "sh", "bash", "zsh", "yml", "yaml", "toml":
            rules.append(Rule(pattern: #"#.*$"#, color: theme.comment, options: .anchorsMatchLines))
        case "html", "xml", "svg":
            rules.append(Rule(pattern: #"<!--[\s\S]*?-->"#, color: theme.comment, options: .dotMatchesLineSeparators))
        default:
            rules.append(Rule(pattern: #"//.*$"#, color: theme.comment, options: .anchorsMatchLines))
        }

        return rules
    }

    // MARK: - Keywords

    private static func keywords(for ext: String) -> [String] {
        switch ext {
        case "swift":
            return [
                "import", "class", "struct", "enum", "protocol", "extension", "func", "var", "let",
                "if", "else", "guard", "switch", "case", "default", "for", "while", "repeat",
                "return", "throw", "throws", "try", "catch", "do", "break", "continue", "fallthrough",
                "in", "where", "as", "is", "self", "Self", "super", "init", "deinit", "subscript",
                "true", "false", "nil", "typealias", "associatedtype", "static", "override",
                "mutating", "nonmutating", "lazy", "weak", "unowned", "private", "fileprivate",
                "internal", "public", "open", "final", "required", "convenience", "optional",
                "some", "any", "async", "await", "actor", "nonisolated", "isolated",
                "willSet", "didSet", "get", "set", "inout", "indirect",
            ]
        case "js", "jsx", "ts", "tsx", "mjs":
            return [
                "const", "let", "var", "function", "class", "extends", "return", "if", "else",
                "for", "while", "do", "switch", "case", "default", "break", "continue",
                "import", "export", "from", "async", "await", "try", "catch", "finally",
                "throw", "new", "this", "super", "typeof", "instanceof", "in", "of",
                "true", "false", "null", "undefined", "void", "delete", "yield",
                "interface", "type", "enum", "implements", "abstract", "readonly",
                "private", "protected", "public", "static", "as", "keyof", "declare",
            ]
        case "py":
            return [
                "def", "class", "import", "from", "return", "if", "elif", "else", "for", "while",
                "break", "continue", "pass", "raise", "try", "except", "finally", "with", "as",
                "lambda", "yield", "global", "nonlocal", "assert", "del", "in", "not", "and", "or",
                "is", "True", "False", "None", "self", "async", "await",
            ]
        case "c", "h":
            return [
                "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
                "else", "enum", "extern", "float", "for", "goto", "if", "int", "long", "register",
                "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef",
                "union", "unsigned", "void", "volatile", "while", "NULL",
            ]
        case "cpp", "hpp", "cc", "cxx":
            return [
                "auto", "break", "case", "char", "class", "const", "continue", "default", "delete",
                "do", "double", "else", "enum", "extern", "float", "for", "friend", "goto", "if",
                "inline", "int", "long", "namespace", "new", "operator", "private", "protected",
                "public", "register", "return", "short", "signed", "sizeof", "static", "struct",
                "switch", "template", "this", "throw", "try", "catch", "typedef", "typename",
                "union", "unsigned", "using", "virtual", "void", "volatile", "while",
                "bool", "true", "false", "nullptr", "override", "final", "constexpr", "noexcept",
            ]
        case "rs":
            return [
                "as", "break", "const", "continue", "crate", "else", "enum", "extern", "false",
                "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut",
                "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait",
                "true", "type", "unsafe", "use", "where", "while", "async", "await", "dyn",
            ]
        case "go":
            return [
                "break", "case", "chan", "const", "continue", "default", "defer", "else",
                "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
                "package", "range", "return", "select", "struct", "switch", "type", "var",
                "true", "false", "nil", "iota",
            ]
        case "rb":
            return [
                "def", "class", "module", "end", "if", "elsif", "else", "unless", "case", "when",
                "while", "until", "for", "do", "begin", "rescue", "ensure", "raise", "return",
                "yield", "block_given?", "self", "super", "true", "false", "nil", "and", "or",
                "not", "in", "then", "require", "include", "extend", "attr_accessor", "attr_reader",
                "attr_writer", "private", "protected", "public", "lambda", "proc",
            ]
        case "json":
            return ["true", "false", "null"]
        case "m", "mm":
            return [
                "auto", "break", "case", "char", "const", "continue", "default", "do", "double",
                "else", "enum", "extern", "float", "for", "goto", "if", "int", "long", "register",
                "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef",
                "union", "unsigned", "void", "volatile", "while", "NULL",
                "id", "self", "super", "nil", "YES", "NO", "TRUE", "FALSE",
                "@interface", "@implementation", "@end", "@protocol", "@class", "@selector",
                "@property", "@synthesize", "@dynamic", "@try", "@catch", "@finally", "@throw",
                "nonatomic", "strong", "weak", "assign", "copy", "readonly", "readwrite",
            ]
        default:
            return []
        }
    }
}
