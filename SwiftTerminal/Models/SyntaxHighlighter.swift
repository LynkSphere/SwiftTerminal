import AppKit

/// Lightweight regex-based syntax highlighter. No external dependencies.
/// Covers keywords, strings, comments, numbers, and types for common languages.
enum SyntaxHighlighter {

    nonisolated(unsafe) private static var regexCache: [String: NSRegularExpression] = [:]

    private static func cachedRegex(pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(pattern)|\(options.rawValue)"
        if let cached = regexCache[key] {
            return cached
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        regexCache[key] = regex
        return regex
    }

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

    static func highlight(_ source: String, fileExtension: String, fontSize: CGFloat = 12, theme: Theme = defaultTheme) -> NSAttributedString {
        let font = fontSize == 12 ? theme.font : NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.foreground,
        ]
        let attributed = NSMutableAttributedString(string: source, attributes: base)
        let fullRange = NSRange(location: 0, length: attributed.length)

        let rules = self.rules(for: fileExtension, theme: theme)
        for rule in rules {
            let regex = cachedRegex(pattern: rule.pattern, options: rule.options)
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
        // HTML/XML/SVG get their own dedicated rule set
        if ["html", "xml", "svg"].contains(ext) {
            return markupRules(theme: theme)
        }

        // CSS/SCSS/LESS get their own dedicated rule set
        if ["css", "scss", "less"].contains(ext) {
            return cssRules(theme: theme)
        }

        // Markdown
        if ["md", "markdown"].contains(ext) {
            return markdownRules(theme: theme)
        }

        let keywords = self.keywords(for: ext)
        var rules: [Rule] = []

        // Numbers (hex, binary, octal, float, plain int)
        rules.append(Rule(pattern: #"\b0[xX][0-9a-fA-F_]+\b"#, color: theme.number))
        rules.append(Rule(pattern: #"\b0[bB][01_]+\b"#, color: theme.number))
        rules.append(Rule(pattern: #"\b0[oO][0-7_]+\b"#, color: theme.number))
        rules.append(Rule(pattern: #"\b\d[\d_]*(\.\d[\d_]*)?\b"#, color: theme.number))

        // Types (capitalized identifiers)
        rules.append(Rule(pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#, color: theme.type))

        // Keywords
        if !keywords.isEmpty {
            let joined = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            rules.append(Rule(pattern: #"\b(?:"# + joined + #")\b"#, color: theme.keyword))
        }

        // Language-specific preprocessor / attributes / extras
        switch ext {
        case "swift":
            rules.append(Rule(pattern: #"@\w+"#, color: theme.preprocessor))
            rules.append(Rule(pattern: #"#\w+"#, color: theme.preprocessor))
        case "c", "cpp", "h", "hpp", "m", "mm":
            rules.append(Rule(pattern: #"^\s*#\w+.*$"#, color: theme.preprocessor, options: .anchorsMatchLines))
        case "py":
            rules.append(Rule(pattern: #"@[\w.]+"#, color: theme.preprocessor))
        case "rs":
            // Rust lifetimes 'a, attributes #[...], macros name!
            rules.append(Rule(pattern: #"'\b[a-z_]\w*\b"#, color: theme.preprocessor))
            rules.append(Rule(pattern: #"#\[[\s\S]*?\]"#, color: theme.preprocessor, options: .dotMatchesLineSeparators))
            rules.append(Rule(pattern: #"\b\w+!"#, color: theme.preprocessor))
        case "go":
            // Go tags in struct fields
            rules.append(Rule(pattern: #"`[^`]*`"#, color: theme.string))
        case "rb":
            // Ruby symbols :name
            rules.append(Rule(pattern: #":\w+"#, color: theme.number))
        case "sh", "bash", "zsh":
            // Shell variables $VAR, ${VAR}
            rules.append(Rule(pattern: #"\$\{?\w+\}?"#, color: theme.type))
        case "yml", "yaml":
            // YAML keys (word before colon at start of line)
            rules.append(Rule(pattern: #"^\s*[\w.-]+(?=\s*:)"#, color: theme.keyword, options: .anchorsMatchLines))
        case "toml":
            // TOML section headers [section] and keys
            rules.append(Rule(pattern: #"^\s*\[[\w.-]+\]"#, color: theme.preprocessor, options: .anchorsMatchLines))
            rules.append(Rule(pattern: #"^\s*[\w.-]+(?=\s*=)"#, color: theme.keyword, options: .anchorsMatchLines))
        default:
            break
        }

        // Strings — language-specific multi-line first, then standard
        switch ext {
        case "swift":
            // Swift multi-line string literal """..."""
            rules.append(Rule(pattern: #"\"\"\"[\s\S]*?\"\"\""#, color: theme.string, options: .dotMatchesLineSeparators))
            // Swift raw strings #"..."#
            rules.append(Rule(pattern: ##"#"(?:[^"\\]|\\.)*"#"##, color: theme.string))
            rules.append(Rule(pattern: #""(?:[^"\\]|\\.)*""#, color: theme.string))
        case "py":
            // Python triple-quoted strings (must come before single-quoted)
            rules.append(Rule(pattern: #"\"\"\"[\s\S]*?\"\"\""#, color: theme.string, options: .dotMatchesLineSeparators))
            rules.append(Rule(pattern: #"'''[\s\S]*?'''"#, color: theme.string, options: .dotMatchesLineSeparators))
            // Python f-strings f"..." / f'...'
            rules.append(Rule(pattern: #"[fFrRbBuU]*"(?:[^"\\]|\\.)*""#, color: theme.string))
            rules.append(Rule(pattern: #"[fFrRbBuU]*'(?:[^'\\]|\\.)*'"#, color: theme.string))
        case "rs":
            // Rust raw strings r"...", r#"..."#
            rules.append(Rule(pattern: "r#+\"[\\s\\S]*?\"#+", color: theme.string, options: .dotMatchesLineSeparators))
            rules.append(Rule(pattern: #""(?:[^"\\]|\\.)*""#, color: theme.string))
            rules.append(Rule(pattern: #"'(?:[^'\\]|\\.)*'"#, color: theme.string))
        case "js", "jsx", "ts", "tsx", "mjs":
            rules.append(Rule(pattern: #""(?:[^"\\]|\\.)*""#, color: theme.string))
            rules.append(Rule(pattern: #"'(?:[^'\\]|\\.)*'"#, color: theme.string))
            rules.append(Rule(pattern: #"`(?:[^`\\]|\\.)*`"#, color: theme.string, options: .dotMatchesLineSeparators))
        default:
            rules.append(Rule(pattern: #""(?:[^"\\]|\\.)*""#, color: theme.string))
            rules.append(Rule(pattern: #"'(?:[^'\\]|\\.)*'"#, color: theme.string))
        }

        // Comments — multi-line first, then single-line
        switch ext {
        case "py":
            // Python # comments (triple-quotes already handled as strings above)
            rules.append(Rule(pattern: #"#.*$"#, color: theme.comment, options: .anchorsMatchLines))
        case "rb":
            rules.append(Rule(pattern: #"=begin[\s\S]*?=end"#, color: theme.comment, options: .dotMatchesLineSeparators))
            rules.append(Rule(pattern: #"#.*$"#, color: theme.comment, options: .anchorsMatchLines))
        case "sh", "bash", "zsh", "yml", "yaml", "toml":
            rules.append(Rule(pattern: #"#.*$"#, color: theme.comment, options: .anchorsMatchLines))
        default:
            rules.append(Rule(pattern: #"/\*[\s\S]*?\*/"#, color: theme.comment, options: .dotMatchesLineSeparators))
            rules.append(Rule(pattern: #"//.*$"#, color: theme.comment, options: .anchorsMatchLines))
        }

        return rules
    }

    // MARK: - Markup Rules (HTML/XML/SVG)

    private static func markupRules(theme: Theme) -> [Rule] {
        var rules: [Rule] = []

        // Tag names <tagname ...> and </tagname>
        rules.append(Rule(pattern: #"</?(\w[\w.-]*)"#, color: theme.keyword))

        // Attribute names
        rules.append(Rule(pattern: #"\b([\w-]+)\s*="#, color: theme.type))

        // Attribute values (quoted strings)
        rules.append(Rule(pattern: #""[^"]*""#, color: theme.string))
        rules.append(Rule(pattern: #"'[^']*'"#, color: theme.string))

        // Entities &amp; etc
        rules.append(Rule(pattern: #"&\w+;"#, color: theme.number))

        // HTML comments
        rules.append(Rule(pattern: #"<!--[\s\S]*?-->"#, color: theme.comment, options: .dotMatchesLineSeparators))

        return rules
    }

    // MARK: - CSS Rules

    private static func cssRules(theme: Theme) -> [Rule] {
        var rules: [Rule] = []

        // Selectors (tag names, .class, #id)
        rules.append(Rule(pattern: #"[.#][\w-]+"#, color: theme.keyword))

        // Property names
        rules.append(Rule(pattern: #"\b[\w-]+(?=\s*:)"#, color: theme.type))

        // Numbers with units
        rules.append(Rule(pattern: #"\b\d[\d.]*(%|px|em|rem|vh|vw|pt|cm|mm|in|deg|s|ms)?\b"#, color: theme.number))

        // Colors #hex
        rules.append(Rule(pattern: #"#[0-9a-fA-F]{3,8}\b"#, color: theme.number))

        // Strings
        rules.append(Rule(pattern: #""[^"]*""#, color: theme.string))
        rules.append(Rule(pattern: #"'[^']*'"#, color: theme.string))

        // @rules
        rules.append(Rule(pattern: #"@[\w-]+"#, color: theme.preprocessor))

        // !important
        rules.append(Rule(pattern: #"!important"#, color: theme.preprocessor))

        // Comments
        rules.append(Rule(pattern: #"/\*[\s\S]*?\*/"#, color: theme.comment, options: .dotMatchesLineSeparators))

        return rules
    }

    // MARK: - Markdown Rules

    private static func markdownRules(theme: Theme) -> [Rule] {
        var rules: [Rule] = []

        // Headings # ## ### etc
        rules.append(Rule(pattern: #"^#{1,6}\s+.*$"#, color: theme.keyword, options: .anchorsMatchLines))

        // Bold **text** and __text__
        rules.append(Rule(pattern: #"\*\*[^*]+\*\*"#, color: theme.type))
        rules.append(Rule(pattern: #"__[^_]+__"#, color: theme.type))

        // Italic *text* and _text_
        rules.append(Rule(pattern: #"(?<!\*)\*(?!\*)[^*]+\*(?!\*)"#, color: theme.string))

        // Inline code `code`
        rules.append(Rule(pattern: #"`[^`]+`"#, color: theme.number))

        // Code fence markers ```
        rules.append(Rule(pattern: #"^```.*$"#, color: theme.number, options: .anchorsMatchLines))

        // Links [text](url)
        rules.append(Rule(pattern: #"\[([^\]]+)\]\([^)]+\)"#, color: theme.preprocessor))

        // Blockquotes > text
        rules.append(Rule(pattern: #"^>\s+.*$"#, color: theme.comment, options: .anchorsMatchLines))

        // List markers - * + and numbered 1.
        rules.append(Rule(pattern: #"^\s*[-*+]\s"#, color: theme.keyword, options: .anchorsMatchLines))
        rules.append(Rule(pattern: #"^\s*\d+\.\s"#, color: theme.keyword, options: .anchorsMatchLines))

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
        case "sh", "bash", "zsh":
            return [
                "if", "then", "else", "elif", "fi", "case", "esac", "for", "while", "until",
                "do", "done", "in", "function", "select", "return", "exit", "break", "continue",
                "local", "export", "readonly", "declare", "typeset", "unset", "shift",
                "source", "eval", "exec", "trap", "set", "true", "false",
            ]
        case "yml", "yaml":
            return ["true", "false", "null", "yes", "no", "on", "off"]
        case "toml":
            return ["true", "false"]
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
