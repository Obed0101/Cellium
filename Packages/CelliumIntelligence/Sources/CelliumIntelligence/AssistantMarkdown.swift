import Foundation

public struct AssistantMarkdownBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case paragraph
        case heading(level: Int)
        case unorderedListItem
        case orderedListItem(marker: String)
        case quote
        case code(language: String?)
        case divider
    }

    public let kind: Kind
    public let content: String

    public init(kind: Kind, content: String) {
        self.kind = kind
        self.content = content
    }
}

public enum AssistantMarkdownParser {
    public static func parse(_ markdown: String) -> [AssistantMarkdownBlock] {
        let normalized = AssistantResponseFormatter.normalizeLineBreaks(markdown)
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [AssistantMarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var insideCodeFence = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(
                AssistantMarkdownBlock(
                    kind: .paragraph,
                    content: paragraphLines.joined(separator: "\n")
                )
            )
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushCode() {
            blocks.append(
                AssistantMarkdownBlock(
                    kind: .code(language: codeLanguage),
                    content: codeLines.joined(separator: "\n")
                )
            )
            codeLines.removeAll(keepingCapacity: true)
            codeLanguage = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if insideCodeFence {
                if trimmed.hasPrefix("```") {
                    flushCode()
                    insideCodeFence = false
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                insideCodeFence = true
                let language = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                codeLanguage = language.isEmpty ? nil : language
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(AssistantMarkdownBlock(kind: .divider, content: ""))
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(
                    AssistantMarkdownBlock(
                        kind: .heading(level: heading.level),
                        content: heading.content
                    )
                )
                continue
            }

            if let item = unorderedItem(from: trimmed) {
                flushParagraph()
                blocks.append(AssistantMarkdownBlock(kind: .unorderedListItem, content: item))
                continue
            }

            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                blocks.append(
                    AssistantMarkdownBlock(
                        kind: .orderedListItem(marker: item.marker),
                        content: item.content
                    )
                )
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quote = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(AssistantMarkdownBlock(kind: .quote, content: quote))
                continue
            }

            paragraphLines.append(line)
        }

        if insideCodeFence {
            flushCode()
        } else {
            flushParagraph()
        }
        return blocks
    }

    private static func heading(from line: String) -> (level: Int, content: String)? {
        let prefix = line.prefix { $0 == "#" }
        guard (1...6).contains(prefix.count),
              line.dropFirst(prefix.count).first == " " else {
            return nil
        }
        let content = line.dropFirst(prefix.count + 1)
            .trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : (prefix.count, content)
    }

    private static func unorderedItem(from line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let prefixes = ["- ", "* ", "+ "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func orderedItem(from line: String) -> (marker: String, content: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let remainder = line.dropFirst(digits.count)
        guard remainder.count >= 2,
              let punctuation = remainder.first,
              punctuation == "." || punctuation == ")",
              remainder.dropFirst().first == " " else {
            return nil
        }
        return (
            marker: String(digits) + String(punctuation),
            content: String(remainder.dropFirst(2))
        )
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first else { return false }
        guard first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }
}
