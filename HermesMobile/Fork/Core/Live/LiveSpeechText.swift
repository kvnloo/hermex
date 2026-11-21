import Foundation

enum LiveSpeechText {
    static let chunkLimit = 220

    static func speakable(_ markdown: String) -> String {
        var lines: [String] = []
        var inFence = false
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence || line.isEmpty || isTableRule(line) { continue }
            lines.append(clean(line))
        }
        return collapse(lines.filter { !$0.isEmpty }.joined(separator: " "))
    }

    static func chunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for sentence in sentences(text) {
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= chunkLimit {
                current += " " + sentence
            } else {
                chunks.append(current)
                current = sentence
            }
            while current.count > chunkLimit {
                let cut = splitPoint(current)
                chunks.append(String(current[..<cut]).trimmingCharacters(in: .whitespaces))
                current = String(current[cut...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func clean(_ line: String) -> String {
        var text = line
        let rules: [(String, String)] = [
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
            (#"https?://\S+"#, ""),
            (#"`([^`]*)`"#, "$1"),
            (#"^#{1,6}\s+"#, ""),
            (#"^>\s?"#, ""),
            (#"^([-*+]|\d+[.)])\s+"#, ""),
            (#"^\[[ xX]\]\s+"#, ""),
            (#"(\*\*|__|~~)(.+?)\1"#, "$2"),
            (#"(?<![\w*])[*_](?!\s)(.+?)(?<!\s)[*_](?![\w*])"#, "$1"),
            (#"\|"#, " "),
            (#"<[^>]+>"#, ""),
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func isTableRule(_ line: String) -> Bool {
        line.contains("-") && line.allSatisfy { "|-: ".contains($0) }
    }

    private static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            if ".!?".contains(character), next == " " {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    private static func splitPoint(_ text: String) -> String.Index {
        let limit = text.index(text.startIndex, offsetBy: chunkLimit)
        if let space = text[..<limit].lastIndex(where: { $0 == " " || $0 == "," || $0 == ";" }), space > text.startIndex {
            return text.index(after: space)
        }
        return limit
    }
}
