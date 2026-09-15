import Foundation
import MeetingAssistantCoreDomain

public struct TextContextGuardrails: Sendable {
    public init() {}

    public func apply(to text: String, policy: TextContextPolicy = .default) -> String {
        let normalized = normalizeLineBreaks(text)
        let lines = splitLines(normalized)
        guard !lines.isEmpty else { return "" }

        let maxLines = min(policy.preferredLineWindow.upperBound, lines.count)
        var selectedLines = Array(lines.suffix(maxLines))
        selectedLines = trimToCharacterLimit(
            lines: selectedLines,
            maxCharacters: policy.maxCharacters,
            minLines: policy.preferredLineWindow.lowerBound
        )

        return selectedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitLines(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { String($0) }
    }

    private func trimToCharacterLimit(lines: [String], maxCharacters: Int, minLines: Int) -> [String] {
        var working = lines
        var removedFenceCount = 0

        func fenceCount(in line: String) -> Int {
            line.components(separatedBy: "```").count - 1
        }

        func combinedLength(of lines: [String]) -> Int {
            lines.joined(separator: "\n").count
        }

        let minLineCount = min(minLines, working.count)

        while combinedLength(of: working) > maxCharacters, working.count > minLineCount {
            let removedLine = working.removeFirst()
            removedFenceCount += fenceCount(in: removedLine)
        }

        while combinedLength(of: working) > maxCharacters, !working.isEmpty {
            let removedLine = working.removeFirst()
            removedFenceCount += fenceCount(in: removedLine)
        }

        if removedFenceCount % 2 == 1 {
            while !working.isEmpty {
                let line = working.removeFirst()
                if fenceCount(in: line) > 0 {
                    break
                }
            }
        }

        return working
    }

    private func normalizeLineBreaks(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
