//
//  PreviewSupport.swift
//  todoMarkdown
//
//  Created by Codex on 2026/3/16.
//

import Foundation

enum PreviewLineKind: Equatable {
    case heading(level: Int, text: String)
    case todo(isCompleted: Bool, text: String)
    case paragraph(String)
    case empty
}

struct PreviewMentionContent: Equatable {
    var assignees: [String]
    var displayText: String
}

enum PreviewInlineSegmentKind: Equatable {
    case plain
    case dateTag
    case remarkTag
}

struct PreviewInlineSegment: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var kind: PreviewInlineSegmentKind
}

struct PreviewLine: Identifiable, Equatable {
    let id = UUID()
    var kind: PreviewLineKind

    var mentionContent: PreviewMentionContent {
        switch kind {
        case let .heading(_, text):
            PreviewMentionParser.parse(text)
        case let .todo(_, text):
            PreviewMentionParser.parse(text)
        case let .paragraph(text):
            PreviewMentionParser.parse(text)
        case .empty:
            PreviewMentionContent(assignees: [], displayText: "")
        }
    }
}

enum PreviewLineCodec {
    nonisolated static func decode(_ content: String) -> [PreviewLine] {
        guard !content.isEmpty else { return [] }

        return content.components(separatedBy: "\n").map { line in
            PreviewLine(kind: classify(line))
        }
    }

    nonisolated static func encode(_ lines: [PreviewLine]) -> String {
        lines.map(serialize).joined(separator: "\n")
    }

    nonisolated static func toggleTodo(in content: String, at index: Int) -> String {
        var lines = decode(content)
        guard lines.indices.contains(index) else { return content }
        guard case let .todo(isCompleted, text) = lines[index].kind else { return content }

        lines[index].kind = .todo(isCompleted: !isCompleted, text: text)
        return encode(lines)
    }

    nonisolated static func insertTodo(in content: String, after index: Int?) -> String {
        var lines = decode(content)
        let newLine = PreviewLine(kind: .todo(isCompleted: false, text: ""))

        if lines.isEmpty {
            lines = [newLine]
        } else {
            let insertIndex = min((index ?? (lines.count - 1)) + 1, lines.count)
            lines.insert(newLine, at: insertIndex)
        }

        return encode(lines)
    }

    nonisolated static func deleteLine(in content: String, at index: Int) -> String {
        var lines = decode(content)
        guard lines.indices.contains(index) else { return content }
        lines.remove(at: index)
        return encode(lines)
    }

    nonisolated static func archiveLine(in content: String, at index: Int) -> String {
        var rawLines = content.components(separatedBy: "\n")
        guard rawLines.indices.contains(index) else { return content }

        let lineToArchive = rawLines.remove(at: index)
        let trimmed = lineToArchive.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawLines.joined(separator: "\n") }

        let archiveHeading = "## Archive"
        if !rawLines.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == archiveHeading.lowercased() }) {
            if let last = rawLines.last, !last.isEmpty {
                rawLines.append("")
            }
            rawLines.append(archiveHeading)
        }

        rawLines.append(lineToArchive)
        return rawLines.joined(separator: "\n")
    }

    nonisolated static func moveLines(in content: String, fromOffsets: IndexSet, toOffset: Int) -> String {
        var lines = decode(content)
        move(&lines, fromOffsets: fromOffsets, toOffset: toOffset)
        return encode(lines)
    }

    private nonisolated static func move(
        _ lines: inout [PreviewLine],
        fromOffsets: IndexSet,
        toOffset: Int
    ) {
        let movingLines = fromOffsets.map { lines[$0] }
        lines.removeAll { line in
            movingLines.contains(where: { $0.id == line.id })
        }

        let destination = max(0, min(toOffset, lines.count))
        lines.insert(contentsOf: movingLines, at: destination)
    }

    private nonisolated static func classify(_ line: String) -> PreviewLineKind {
        if line.isEmpty {
            return .empty
        }

        if let todo = parseTodo(line) {
            return todo
        }

        if let heading = parseHeading(line) {
            return heading
        }

        return .paragraph(line)
    }

    private nonisolated static func parseTodo(_ line: String) -> PreviewLineKind? {
        if line.hasPrefix("- [ ] ") {
            return .todo(isCompleted: false, text: String(line.dropFirst(6)))
        }

        if line == "- [ ]" {
            return .todo(isCompleted: false, text: "")
        }

        if line.hasPrefix("- [x] ") {
            return .todo(isCompleted: true, text: String(line.dropFirst(6)))
        }

        if line == "- [x]" {
            return .todo(isCompleted: true, text: "")
        }

        return nil
    }

    private nonisolated static func parseHeading(_ line: String) -> PreviewLineKind? {
        for level in 1...3 {
            let prefix = String(repeating: "#", count: level) + " "
            if line.hasPrefix(prefix) {
                return .heading(level: level, text: String(line.dropFirst(prefix.count)))
            }
        }

        return nil
    }

    private nonisolated static func serialize(_ line: PreviewLine) -> String {
        switch line.kind {
        case let .heading(level, text):
            return String(repeating: "#", count: level) + " " + text
        case let .todo(isCompleted, text):
            let prefix = isCompleted ? "- [x]" : "- [ ]"
            return text.isEmpty ? prefix : prefix + " " + text
        case let .paragraph(text):
            return text
        case .empty:
            return ""
        }
    }
}

enum PreviewMentionParser {
    nonisolated static func mentionRanges(in text: String) -> [NSRange] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return mentionRegex().matches(in: text, range: nsRange).map(\.range)
    }

    nonisolated static func parse(_ text: String) -> PreviewMentionContent {
        guard !text.isEmpty else {
            return PreviewMentionContent(assignees: [], displayText: "")
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = mentionRegex().matches(in: text, range: nsRange)
        let assignees: [String] = matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }

        guard !matches.isEmpty else {
            return PreviewMentionContent(assignees: [], displayText: text)
        }

        var displayText = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: displayText) else { continue }
            displayText.removeSubrange(range)
        }

        displayText = displayText
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return PreviewMentionContent(
            assignees: assignees,
            displayText: displayText
        )
    }

    private nonisolated static func mentionRegex() -> NSRegularExpression {
        try! NSRegularExpression(pattern: #"(?<!\S)@([^\s@]+)"#)
    }
}

enum PreviewInlineParser {
    nonisolated static func dateTagRanges(in text: String) -> [NSRange] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return dateRegex().matches(in: text, range: nsRange).map(\.range)
    }

    nonisolated static func remarkRanges(in text: String) -> [NSRange] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return remarkRegex().matches(in: text, range: nsRange).map(\.range)
    }

    nonisolated static func segments(in text: String) -> [PreviewInlineSegment] {
        guard !text.isEmpty else { return [] }

        var allMatches: [(range: NSRange, kind: PreviewInlineSegmentKind)] = .init()
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        
        for match in dateRegex().matches(in: text, range: nsRange) {
            allMatches.append((match.range, .dateTag))
        }
        for match in remarkRegex().matches(in: text, range: nsRange) {
            allMatches.append((match.range, .remarkTag))
        }
        
        allMatches.sort { $0.range.location < $1.range.location }

        guard !allMatches.isEmpty else {
            return [PreviewInlineSegment(text: text, kind: .plain)]
        }

        var segments: [PreviewInlineSegment] = []
        var currentLocation = 0

        for match in allMatches {
            if match.range.location < currentLocation { continue }
            
            if match.range.location > currentLocation {
                let prefixRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
                if let prefix = substring(in: text, range: prefixRange), !prefix.isEmpty {
                    segments.append(PreviewInlineSegment(text: prefix, kind: .plain))
                }
            }

            if let tag = substring(in: text, range: match.range), !tag.isEmpty {
                segments.append(PreviewInlineSegment(text: tag, kind: match.kind))
            }

            currentLocation = match.range.location + match.range.length
        }

        let trailingLength = text.utf16.count - currentLocation
        if trailingLength > 0 {
            let trailingRange = NSRange(location: currentLocation, length: trailingLength)
            if let trailing = substring(in: text, range: trailingRange), !trailing.isEmpty {
                segments.append(PreviewInlineSegment(text: trailing, kind: .plain))
            }
        }

        return segments
    }

    private nonisolated static func substring(in text: String, range: NSRange) -> String? {
        guard let range = Range(range, in: text) else { return nil }
        return String(text[range])
    }

    private nonisolated static func dateRegex() -> NSRegularExpression {
        try! NSRegularExpression(pattern: #"(?<!\S)#(?!\s)([^\s#]+)"#)
    }

    private nonisolated static func remarkRegex() -> NSRegularExpression {
        try! NSRegularExpression(pattern: #"(?<!\S)--(?!\s)([^\s]+)"#)
    }
}
