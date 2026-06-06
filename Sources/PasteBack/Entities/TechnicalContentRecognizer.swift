import Foundation

/// Classifies developer-oriented captures: source code, structured data, diffs,
/// terminal commands, stack traces, and logs. It is intentionally deterministic
/// and local; the goal is to promote high-confidence "Code" chips without
/// turning ordinary prose into fenced blocks.
struct TechnicalContentRecognizer {

    enum Kind {
        case sourceCode
        case stackTrace
        case terminalCommand
        case json
        case yaml
        case sql
        case diff
        case log
    }

    struct Recognition {
        let kind: Kind
        let language: String?
        let confidence: Double
        let normalizedText: String
    }

    private struct LanguageProfile {
        let language: String
        let extensions: [String]
        let keywords: [String]
        let regexes: [String]
        let commentTokens: [String]
    }

    func entities(in text: String, source: CaptureSource, axElements: [AXElement]) -> [DetectedEntity] {
        guard let recognition = recognize(in: text, source: source, axElements: axElements) else {
            return []
        }

        var entities: [DetectedEntity] = []
        if recognition.kind == .stackTrace {
            entities.append(DetectedEntity(
                type: .stackTrace,
                value: recognition.normalizedText,
                sourceText: text
            ))
        }

        entities.append(DetectedEntity(
            type: .codeBlock(language: recognition.language),
            value: recognition.normalizedText,
            sourceText: text
        ))
        return entities
    }

    func recognize(in text: String, source: CaptureSource, axElements: [AXElement] = []) -> Recognition? {
        let normalized = normalize(text)
        guard meaningful(normalized) else { return nil }

        var candidates: [Recognition] = []
        candidates.append(contentsOf: structuredRecognitions(normalized))
        if let sourceCode = sourceCodeRecognition(normalized, source: source, axElements: axElements) {
            candidates.append(sourceCode)
        }

        return candidates
            .filter { $0.confidence >= threshold(for: $0.kind) }
            .sorted { $0.confidence > $1.confidence }
            .first
    }

    // MARK: - Structured recognizers

    private func structuredRecognitions(_ text: String) -> [Recognition] {
        var out: [Recognition] = []

        if isStackTrace(text) {
            out.append(Recognition(kind: .stackTrace, language: stackTraceLanguage(text),
                                   confidence: 0.96, normalizedText: stripLineNumberGutters(text)))
        }
        if isJSON(text) {
            out.append(Recognition(kind: .json, language: "json",
                                   confidence: 0.98, normalizedText: text))
        }
        if isDiff(text) {
            out.append(Recognition(kind: .diff, language: "diff",
                                   confidence: 0.95, normalizedText: text))
        }
        if isSQL(text) {
            out.append(Recognition(kind: .sql, language: "sql",
                                   confidence: 0.90, normalizedText: stripLineNumberGutters(text)))
        }
        if isShellCommand(text) {
            out.append(Recognition(kind: .terminalCommand, language: "bash",
                                   confidence: 0.88, normalizedText: normalizeShellPrompt(text)))
        }
        if isYAML(text) {
            out.append(Recognition(kind: .yaml, language: "yaml",
                                   confidence: 0.84, normalizedText: stripLineNumberGutters(text)))
        }
        if isLog(text) {
            out.append(Recognition(kind: .log, language: "log",
                                   confidence: 0.78, normalizedText: text))
        }

        return out
    }

    private func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
              (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func isDiff(_ text: String) -> Bool {
        let lines = nonEmptyLines(text)
        guard lines.count >= 3 else { return false }
        if text.contains("@@ ") || text.contains("diff --git") || text.contains("+++ ") && text.contains("--- ") {
            return true
        }
        let changed = lines.filter { $0.hasPrefix("+") || $0.hasPrefix("-") }.count
        return changed >= 3 && Double(changed) / Double(lines.count) >= 0.35
    }

    private func isSQL(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasVerb = regex(lower, #"\b(select|insert|update|delete|create|alter|drop|with)\b"#)
        let hasClause = regex(lower, #"\b(from|where|join|group by|order by|values|set|returning)\b"#)
        return hasVerb && hasClause
    }

    private func isYAML(_ text: String) -> Bool {
        let lines = nonEmptyLines(text)
        guard lines.count >= 3 else { return false }
        let keyed = lines.filter { regex($0, #"^\s*[-\w.]+\s*:\s*.+"#) }.count
        let listItems = lines.filter { regex($0, #"^\s*-\s+\w+"#) }.count
        return keyed >= 3 || (keyed >= 1 && listItems >= 2)
    }

    private func isShellCommand(_ text: String) -> Bool {
        let lines = nonEmptyLines(text)
        guard !lines.isEmpty, lines.count <= 6 else { return false }
        let promptLike = lines.filter { regex($0, #"^\s*(\$|%|❯|➜|>)\s+\S+"#) }.count
        let commandLike = lines.filter {
            regex($0, #"^\s*(sudo\s+)?(git|npm|pnpm|yarn|bun|node|python3?|pip3?|uv|cargo|go|swift|xcodebuild|make|cmake|docker|kubectl|curl|ssh|scp|rsync|brew|gh|jq|sed|awk|grep|rg|find|cat|cd|ls)\b"#)
        }.count
        return promptLike > 0 || commandLike == lines.count
    }

    private func isStackTrace(_ text: String) -> Bool {
        text.contains("Traceback (most recent call last)") ||
        text.contains("Exception in thread") ||
        text.contains("goroutine ") && text.contains(".go:") ||
        regex(text, #"(?m)^\s+at\s+\S+(\.\S+)?\(.+:\d+(:\d+)?\)"#) ||
        regex(text, #"(?m)^\s*File \"[^\"]+\", line \d+"#) ||
        regex(text, #"(?m)^\s*#\d+\s+0x[0-9a-fA-F]+\s+"#) ||
        regex(text, #"(?m)\b\w+\.(swift|m|mm|c|cc|cpp|h|hpp|go|rs|java|kt|py|rb|php|js|jsx|ts|tsx):\d+(:\d+)?\b"#)
    }

    private func isLog(_ text: String) -> Bool {
        let lines = nonEmptyLines(text)
        guard lines.count >= 3 else { return false }
        let dated = lines.filter { regex($0, #"^\s*(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}|\[\d{2}:\d{2}:\d{2}\])"#) }.count
        let leveled = lines.filter { regex($0, #"\b(DEBUG|INFO|WARN|WARNING|ERROR|FATAL|TRACE)\b"#) }.count
        return dated >= 2 || leveled >= 3
    }

    // MARK: - Source code recognizer

    private func sourceCodeRecognition(_ text: String, source: CaptureSource, axElements: [AXElement]) -> Recognition? {
        let stripped = stripLineNumberGutters(text)
        let context = contextBoost(source: source, axElements: axElements)
        let candidates = sourceCodeCandidates(from: stripped)

        let best = candidates.compactMap { candidate -> (text: String, language: String?, confidence: Double)? in
            let lines = nonEmptyLines(candidate)
            guard !lines.isEmpty else { return nil }
            let features = codeFeatureScore(candidate, lines: lines)
            let language = bestLanguage(for: candidate, source: source)
            let prosePenalty = naturalLanguagePenalty(candidate, lines: lines)
            let languageBoost = language.score >= 0.10 ? min(0.25, language.score) : 0
            let total = clamp(features + context + languageBoost - prosePenalty)
            return (candidate, language.language, total)
        }
        .filter { $0.confidence >= threshold(for: .sourceCode) }
        .sorted {
            if abs($0.confidence - $1.confidence) > 0.04 { return $0.confidence > $1.confidence }
            let lhsStartsAtCode = startsAtLikelyCode($0.text)
            let rhsStartsAtCode = startsAtLikelyCode($1.text)
            if lhsStartsAtCode != rhsStartsAtCode { return lhsStartsAtCode }
            return $0.text.count < $1.text.count
        }
        .first

        guard let best else { return nil }
        return Recognition(kind: .sourceCode,
                           language: best.language,
                           confidence: best.confidence,
                           normalizedText: trimSourceChrome(best.text))
    }

    /// AX often contributes nearby page/window labels before the selected code
    /// block. Score plausible suffixes and contiguous code-ish runs so the Code
    /// chip pastes the snippet, not browser/title/section chrome.
    private func sourceCodeCandidates(from text: String) -> [String] {
        let full = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = full.components(separatedBy: "\n")
        var candidates = [full]

        for index in lines.indices where isLikelyCodeStart(lines[index]) {
            let suffix = lines[index...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.count >= 8 { candidates.append(suffix) }
        }

        var current: [String] = []
        for line in lines {
            if isCodeLikeLine(line) || (!current.isEmpty && line.trimmingCharacters(in: .whitespaces).isEmpty) {
                current.append(line)
            } else {
                appendRun(current, to: &candidates)
                current.removeAll()
            }
        }
        appendRun(current, to: &candidates)

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private func appendRun(_ run: [String], to candidates: inout [String]) {
        let text = run.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if nonEmptyLines(text).count >= 2, text.count >= 12 {
            candidates.append(text)
        }
    }

    private func isLikelyCodeStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return regex(trimmed, #"^(pub\s+)?(async\s+)?(func|function|def|class|struct|enum|interface|protocol|impl|fn|let|var|const|import|from|package|module|using|namespace)\b"#) ||
               regex(trimmed, #"^(if|for|while|switch|guard|return|SELECT|WITH|INSERT|UPDATE|DELETE)\b"#) ||
               regex(trimmed, #"^(#include|<[A-Za-z][^>]*>|\{|\[)"#)
    }

    private func isCodeLikeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if isLikelyCodeStart(trimmed) { return true }
        if regex(trimmed, #"^[}\])];,]+$"#) { return true }
        if regex(trimmed, #"^(\.|->|::)\w+"#) { return true }
        if regex(trimmed, #"^[A-Za-z_][A-Za-z0-9_]*\s*(=|:=|=>|->|\(|\{)"#) { return true }
        if regex(trimmed, #"^\s{2,}\S"#) { return true }
        return countMatches(trimmed, #"[{}\[\]();=<>|]"#) >= 2
    }

    private func trimSourceChrome(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let firstCode = lines.firstIndex(where: { isLikelyCodeStart($0) }) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines[firstCode...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startsAtLikelyCode(_ text: String) -> Bool {
        guard let first = nonEmptyLines(text).first else { return false }
        return isLikelyCodeStart(first)
    }

    private func codeFeatureScore(_ text: String, lines: [String]) -> Double {
        var score = 0.0
        let joined = lines.joined(separator: "\n")
        let lineCount = lines.count

        let indented = lines.filter { regex($0, #"^\s{2,}\S"#) || regex($0, #"^\t+\S"#) }.count
        let braces = countMatches(joined, #"[{}\[\]();]"#)
        let operators = countMatches(joined, #"(==|!=|<=|>=|=>|->|::|&&|\|\||:=|\+=|-=|\*=|/=|=)"#)
        let comments = countMatches(joined, #"(?m)^\s*(//|#|/\*|\*|<!--|--|;)"#)
        let calls = countMatches(joined, #"\b[A-Za-z_][A-Za-z0-9_]*\s*\("#)
        let declarations = countMatches(joined, #"\b(func|function|def|class|struct|enum|interface|protocol|impl|fn|let|var|const|public|private|import|package|module|using|namespace)\b"#)

        if lineCount >= 2 { score += 0.08 }
        if lineCount >= 5 { score += 0.08 }
        score += min(0.18, Double(indented) / Double(max(1, lineCount)) * 0.28)
        score += min(0.18, Double(braces) / Double(max(1, text.count)) * 18.0)
        score += min(0.16, Double(operators) / Double(max(1, lineCount)) * 0.08)
        score += min(0.12, Double(comments) / Double(max(1, lineCount)) * 0.20)
        score += min(0.16, Double(calls) / Double(max(1, lineCount)) * 0.08)
        score += min(0.18, Double(declarations) / Double(max(1, lineCount)) * 0.12)

        let codeShapedLines = lines.filter { line in
            regex(line, #"[{};]$"#) ||
            regex(line, #"^\s*(if|for|while|switch|catch|guard|else|try|return|await|case|class|struct|enum|def|func|function|fn|let|var|const|import|from|package)\b"#) ||
            regex(line, #"\b[A-Za-z_][A-Za-z0-9_]*\s*(=|:=|=>|->|\()"#)
        }.count
        score += min(0.22, Double(codeShapedLines) / Double(max(1, lineCount)) * 0.32)

        return min(score, 0.82)
    }

    private func bestLanguage(for text: String, source: CaptureSource) -> (language: String?, score: Double) {
        if let fromURL = languageFromURL(source.url) {
            return (fromURL, 0.32)
        }

        var best: (String?, Double) = (nil, 0)
        for profile in Self.languageProfiles {
            var score = 0.0
            for keyword in profile.keywords {
                if regex(text, #"\b"# + NSRegularExpression.escapedPattern(for: keyword) + #"\b"#) {
                    score += 0.035
                }
            }
            for pattern in profile.regexes where regex(text, pattern) {
                score += 0.08
            }
            for token in profile.commentTokens where text.contains(token) {
                score += 0.035
            }
            if score > best.1 { best = (profile.language, min(score, 0.40)) }
        }
        return best
    }

    private func languageFromURL(_ url: URL?) -> String? {
        guard let ext = url?.pathExtension.lowercased(), !ext.isEmpty else { return nil }
        return Self.extensionLanguages[ext]
    }

    private func stackTraceLanguage(_ text: String) -> String? {
        if text.contains("Traceback (most recent call last)") { return "python" }
        if regex(text, #"(?m)^\s+at\s+\S+\(.+\.(js|jsx|ts|tsx):\d+"#) { return "javascript" }
        if text.contains(".swift:") { return "swift" }
        if text.contains(".go:") || text.contains("goroutine ") { return "go" }
        if text.contains(".rs:") { return "rust" }
        if text.contains(".java:") || text.contains("Exception in thread") { return "java" }
        return nil
    }

    // MARK: - Normalization

    private func normalize(_ text: String) -> String {
        var out = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        out = stripCodeFence(out)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripCodeFence(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2,
              lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true,
              lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true else {
            return text
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    private func stripLineNumberGutters(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let guttered = lines.filter {
            regex($0, #"^\s*\d{1,5}\s*[|:]\s+\S"#) ||
            regex($0, #"^\s*\d{1,5}\s{2,}\S"#)
        }.count
        guard lines.count >= 2, Double(guttered) / Double(lines.count) >= 0.45 else {
            return text
        }
        return lines.map {
            $0.replacingOccurrences(of: #"^\s*\d{1,5}\s*(?:[|:]|\s{2,})\s*"#,
                                    with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    private func normalizeShellPrompt(_ text: String) -> String {
        text.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: #"^\s*(\$|%|❯|➜|>)\s+"#,
                                    with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    // MARK: - Context / thresholds

    private func contextBoost(source: CaptureSource, axElements: [AXElement]) -> Double {
        var boost = 0.0
        let app = ((source.bundleIdentifier ?? "") + " " + (source.appName ?? "")).lowercased()
        if regex(app, #"(xcode|visual studio code|vscode|cursor|sublime|textmate|bbedit|nova|zed|jetbrains|intellij|pycharm|webstorm|rubymine|goland|clion|androidstudio)"#) {
            boost += 0.18
        }
        if regex(app, #"(terminal|iterm|warp|wezterm|alacritty|kitty)"#) {
            boost += 0.16
        }
        if let host = source.url?.host?.lowercased(),
           regex(host, #"(github\.com|gitlab\.com|bitbucket\.org|linear\.app|jira|stackoverflow\.com|docs\.)"#) {
            boost += 0.08
        }
        if axElements.contains(where: { regex($0.role.lowercased(), #"(text|area|editor|document)"#) }) {
            boost += 0.05
        }
        return min(boost, 0.26)
    }

    private func naturalLanguagePenalty(_ text: String, lines: [String]) -> Double {
        let words = countMatches(text, #"\b[A-Za-z]{3,}\b"#)
        let punctuation = countMatches(text, #"[{}\[\]();=<>/:._$#]"#)
        let sentenceEnds = countMatches(text, #"[.!?]\s"#)
        let avgWordsPerLine = Double(words) / Double(max(1, lines.count))
        var penalty = 0.0
        if avgWordsPerLine > 12 && punctuation < words / 8 { penalty += 0.22 }
        if sentenceEnds >= 2 && punctuation < words / 5 { penalty += 0.16 }
        if lines.count <= 2 && words > 16 && punctuation < 4 { penalty += 0.20 }
        return penalty
    }

    private func threshold(for kind: Kind) -> Double {
        switch kind {
        case .sourceCode: return 0.58
        case .yaml, .log: return 0.76
        default: return 0.70
        }
    }

    private func meaningful(_ text: String) -> Bool {
        text.count >= 8 && nonEmptyLines(text).count >= 1
    }

    // MARK: - Helpers

    private func nonEmptyLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func regex(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func countMatches(_ text: String, _ pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private func clamp(_ value: Double) -> Double {
        min(0.99, max(0, value))
    }

    private static let extensionLanguages: [String: String] = [
        "swift": "swift", "js": "javascript", "jsx": "javascript", "ts": "typescript",
        "tsx": "typescript", "py": "python", "rb": "ruby", "rs": "rust", "go": "go",
        "java": "java", "kt": "kotlin", "kts": "kotlin", "c": "c", "h": "c",
        "cc": "cpp", "cpp": "cpp", "cxx": "cpp", "hpp": "cpp", "cs": "csharp",
        "php": "php", "html": "html", "htm": "html", "css": "css", "scss": "scss",
        "json": "json", "yaml": "yaml", "yml": "yaml", "sql": "sql", "sh": "bash",
        "bash": "bash", "zsh": "bash", "ps1": "powershell", "xml": "xml",
        "toml": "toml", "dockerfile": "dockerfile", "diff": "diff", "patch": "diff",
        "scala": "scala", "dart": "dart", "lua": "lua", "pl": "perl", "pm": "perl",
        "r": "r", "m": "objective-c", "mm": "objective-cpp"
    ]

    private static let languageProfiles: [LanguageProfile] = [
        LanguageProfile(language: "swift", extensions: ["swift"],
                        keywords: ["func", "let", "var", "guard", "struct", "enum", "protocol", "extension", "import", "actor", "await"],
                        regexes: [#"func\s+\w+\s*\("#, #"\b(let|var)\s+\w+\s*[:=]"#, #"\bguard\s+.+\s+else"#],
                        commentTokens: ["//"]),
        LanguageProfile(language: "typescript", extensions: ["ts", "tsx"],
                        keywords: ["interface", "type", "const", "let", "async", "await", "export", "import", "implements"],
                        regexes: [#":\s*(string|number|boolean|unknown|Promise<)"#, #"\bReact\."#, #"\bexport\s+(type|interface|const|function)"#],
                        commentTokens: ["//", "/*"]),
        LanguageProfile(language: "javascript", extensions: ["js", "jsx"],
                        keywords: ["function", "const", "let", "async", "await", "export", "import", "return", "require"],
                        regexes: [#"\b(console\.log|module\.exports|=>|require\()"#],
                        commentTokens: ["//", "/*"]),
        LanguageProfile(language: "python", extensions: ["py"],
                        keywords: ["def", "class", "import", "from", "self", "lambda", "elif", "None", "True", "False"],
                        regexes: [#"def\s+\w+\s*\("#, #"^\s*class\s+\w+"#, #"^\s*if\s+__name__\s*=="#],
                        commentTokens: ["#"]),
        LanguageProfile(language: "rust", extensions: ["rs"],
                        keywords: ["fn", "let", "mut", "impl", "trait", "pub", "crate", "match", "Result", "Option"],
                        regexes: [#"\bfn\s+\w+\s*\("#, #"\blet\s+mut\s+"#, #"\bimpl\s+\w+"#, #"::\s*<"#, #"&str\b"#, #"\|\w+\|"#],
                        commentTokens: ["//"]),
        LanguageProfile(language: "go", extensions: ["go"],
                        keywords: ["func", "package", "import", "defer", "go", "chan", "interface", "struct", "nil"],
                        regexes: [#"func\s+\w+\s*\("#, #"package\s+\w+"#, #":=\s*"#],
                        commentTokens: ["//"]),
        LanguageProfile(language: "java", extensions: ["java"],
                        keywords: ["public", "private", "class", "interface", "static", "final", "throws", "new", "void"],
                        regexes: [#"\bpublic\s+(class|interface|static)"#, #"\bSystem\.out\.println"#],
                        commentTokens: ["//", "/*"]),
        LanguageProfile(language: "kotlin", extensions: ["kt", "kts"],
                        keywords: ["fun", "val", "var", "data", "sealed", "object", "companion", "suspend"],
                        regexes: [#"\bfun\s+\w+\s*\("#, #"\b(val|var)\s+\w+\s*[:=]"#],
                        commentTokens: ["//"]),
        LanguageProfile(language: "cpp", extensions: ["cc", "cpp", "cxx", "hpp"],
                        keywords: ["include", "namespace", "template", "typename", "std", "auto", "const", "nullptr"],
                        regexes: [#"#include\s*<"#, #"\bstd::\w+"#, #"\btemplate\s*<"#],
                        commentTokens: ["//", "/*"]),
        LanguageProfile(language: "csharp", extensions: ["cs"],
                        keywords: ["using", "namespace", "class", "public", "private", "async", "await", "var", "new"],
                        regexes: [#"\busing\s+System"#, #"\bpublic\s+(class|record|interface)"#],
                        commentTokens: ["//", "/*"]),
        LanguageProfile(language: "ruby", extensions: ["rb"],
                        keywords: ["def", "class", "module", "end", "do", "require", "attr_reader", "nil"],
                        regexes: [#"^\s*def\s+\w+"#, #"^\s*class\s+\w+"#],
                        commentTokens: ["#"]),
        LanguageProfile(language: "php", extensions: ["php"],
                        keywords: ["function", "class", "public", "private", "protected", "echo", "namespace"],
                        regexes: [#"<\?php"#, #"\$\w+\s*="#],
                        commentTokens: ["//", "#", "/*"]),
        LanguageProfile(language: "html", extensions: ["html", "htm"],
                        keywords: ["html", "body", "div", "span", "script", "style", "class"],
                        regexes: [#"</?[a-z][^>]*>"#, #"class=\"#],
                        commentTokens: ["<!--"]),
        LanguageProfile(language: "css", extensions: ["css", "scss"],
                        keywords: ["display", "position", "color", "background", "font", "grid", "flex"],
                        regexes: [#"[.#]?[A-Za-z0-9_-]+\s*\{\s*"#, #"[a-z-]+\s*:\s*[^;]+;"#],
                        commentTokens: ["/*"]),
        LanguageProfile(language: "bash", extensions: ["sh", "bash", "zsh"],
                        keywords: ["if", "then", "fi", "for", "do", "done", "export", "echo"],
                        regexes: [#"^\s*#!/bin/(ba|z)?sh"#, #"\$\{?\w+\}?"#],
                        commentTokens: ["#"]),
        LanguageProfile(language: "powershell", extensions: ["ps1"],
                        keywords: ["param", "function", "foreach", "where-object", "write-host", "get-childitem"],
                        regexes: [#"\$[A-Za-z_][A-Za-z0-9_]*"#, #"\b(Get|Set|New|Remove)-[A-Za-z]+\b"#],
                        commentTokens: ["#"]),
        LanguageProfile(language: "scala", extensions: ["scala"],
                        keywords: ["def", "val", "var", "object", "trait", "case", "match", "implicit", "given"],
                        regexes: [#"\b(def|val|var)\s+\w+\s*[:=]"#, #"\bcase\s+class\s+\w+"#],
                        commentTokens: ["//", "/*"]),
        LanguageProfile(language: "dart", extensions: ["dart"],
                        keywords: ["class", "final", "const", "var", "async", "await", "Future", "Widget"],
                        regexes: [#"\bFuture<"#, #"\bWidget\s+build\s*\("#],
                        commentTokens: ["//", "/*"]),
        LanguageProfile(language: "lua", extensions: ["lua"],
                        keywords: ["local", "function", "then", "elseif", "end", "nil", "require"],
                        regexes: [#"\blocal\s+function\s+\w+"#, #"\bfunction\s+\w+\s*\("#],
                        commentTokens: ["--"]),
        LanguageProfile(language: "perl", extensions: ["pl", "pm"],
                        keywords: ["sub", "my", "use", "strict", "warnings", "foreach", "undef"],
                        regexes: [#"\bsub\s+\w+\s*\{"#, #"\$[A-Za-z_][A-Za-z0-9_]*"#],
                        commentTokens: ["#"]),
        LanguageProfile(language: "r", extensions: ["r"],
                        keywords: ["function", "library", "data.frame", "ifelse", "TRUE", "FALSE", "NULL"],
                        regexes: [#"<-\s*"#, #"\bfunction\s*\("#],
                        commentTokens: ["#"]),
        LanguageProfile(language: "objective-c", extensions: ["m", "mm"],
                        keywords: ["@interface", "@implementation", "@property", "@end", "IBAction", "instancetype"],
                        regexes: [#"^\s*[-+]\s*\([^)]*\)\s*\w+"#, #"\[[A-Za-z_][A-Za-z0-9_]*\s+\w+"#],
                        commentTokens: ["//", "/*"])
    ]
}
