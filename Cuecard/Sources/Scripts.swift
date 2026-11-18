import AppKit

struct Script: Codable {
    var id = UUID()
    var title: String
    var source = ""
    var markdown = true

    var displayTitle: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled Script" : name
    }
}

struct ScriptLibrary: Codable {
    var scripts: [Script]
    var selected: UUID?
    var textSize = 24
    var scrollSpeed = 20

    static var starter: ScriptLibrary {
        let script = Script(title: "Sample Presentation", source: """
        # Introduction
        Good morning, everyone. Today I'll walk you through the project and what we learned.

        # Main Points
        - Start with the problem.
        - Explain the **decision** and why it mattered.
        - Pause before moving to the result.

        # Closing
        Thank you. I'm happy to take questions.
        """)
        return ScriptLibrary(scripts: [script], selected: script.id)
    }
}

struct ScriptStorage {
    let file: URL

    static var local: ScriptStorage {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ScriptStorage(file: home.appendingPathComponent("Library/Application Support/Cuecard/scripts.json"))
    }

    func load() throws -> ScriptLibrary {
        let bytes: Data
        do {
            bytes = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return .starter
        }
        var library = try JSONDecoder().decode(ScriptLibrary.self, from: bytes)
        if let first = library.scripts.first, !library.scripts.contains(where: { $0.id == library.selected }) {
            library.selected = first.id
        }
        if library.scripts.isEmpty { library.selected = nil }
        library.textSize = min(max(library.textSize, 14), 64)
        library.scrollSpeed = min(max(library.scrollSpeed, 5), 100)
        return library
    }

    func save(_ library: ScriptLibrary) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: file, options: .atomic)
    }
}

struct ScriptSection {
    let name: String
    let offset: Int
}

struct FormattedScript {
    let text: NSAttributedString
    let sections: [ScriptSection]

    private static let heading = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})[ \t]+(.+?)\s*$"#)
    private static let bullet = try! NSRegularExpression(pattern: #"^([ \t]*)[-+*][ \t]+"#)
    private static let fence = try! NSRegularExpression(pattern: "^ {0,3}(\u{0060}{3,}|~{3,})(.*)$")

    static func render(_ source: String, markdown: Bool, size: CGFloat) -> FormattedScript {
        let output = NSMutableAttributedString()
        var sections: [ScriptSection] = []
        var openingFence: String?
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")

        for (index, original) in lines.enumerated() {
            var line = original
            let lineRange = NSRange(line.startIndex..., in: line)
            var level = 0
            var code = openingFence != nil
            if let match = fence.firstMatch(in: line, range: lineRange),
               let marker = Range(match.range(at: 1), in: line),
               let tail = Range(match.range(at: 2), in: line) {
                let token = String(line[marker])
                if openingFence == nil {
                    openingFence = token
                    if markdown { continue }
                } else if let opening = openingFence, token.first == opening.first,
                          token.count >= opening.count, line[tail].trimmingCharacters(in: .whitespaces).isEmpty {
                    openingFence = nil
                    if markdown { continue }
                }
                code = true
            }

            if !code, let match = heading.firstMatch(in: line, range: lineRange),
               let titleRange = Range(match.range(at: 2), in: line) {
                let title = String(line[titleRange]).replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
                if !title.isEmpty {
                    sections.append(ScriptSection(name: title, offset: output.length))
                    if markdown {
                        level = match.range(at: 1).length
                        line = title
                    }
                }
            } else if markdown && !code {
                line = bullet.stringByReplacingMatches(in: line, range: lineRange, withTemplate: "$1•  ")
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = size * 0.17
            paragraph.paragraphSpacing = level > 0 ? size * 0.30 : size * 0.10
            if level > 0 && output.length > 0 { paragraph.paragraphSpacingBefore = size * 0.32 }
            let fontSize = size * (level == 1 ? 1.23 : level > 1 ? 1.10 : 1.0)
            let font = NSFont.systemFont(ofSize: fontSize, weight: level > 0 ? .semibold : .regular)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: markdown && code ? NSFont.monospacedSystemFont(ofSize: fontSize * 0.90, weight: .regular) : font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]

            if markdown && !code, !line.isEmpty,
               let parsed = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                for run in parsed.runs {
                    var style = attributes
                    if let intent = run.inlinePresentationIntent {
                        var traits: NSFontTraitMask = []
                        if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
                        if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
                        let runFont = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: fontSize * 0.90, weight: .regular) : font
                        style[.font] = traits.isEmpty ? runFont : NSFontManager.shared.convert(runFont, toHaveTrait: traits)
                        if intent.contains(.strikethrough) { style[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    }
                    output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: style))
                }
            } else {
                output.append(NSAttributedString(string: line, attributes: attributes))
            }
            if index != lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: attributes))
            }
        }
        return FormattedScript(text: output, sections: sections)
    }
}
