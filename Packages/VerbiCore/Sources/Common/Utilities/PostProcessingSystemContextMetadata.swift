import Foundation

public enum PostProcessingSystemContextMetadata {
    public static func augment(
        _ existingContext: String?,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        fullUserName: String = NSFullUserName()
    ) -> String? {
        guard let existingContext else { return nil }

        let trimmedContext = existingContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else { return nil }

        let normalizedBody = normalizeContextBody(trimmedContext)
        let systemLines = missingSystemLines(
            in: normalizedBody,
            now: now,
            timeZone: timeZone,
            locale: locale,
            fullUserName: fullUserName
        )

        var outputLines: [String] = []
        if !systemLines.isEmpty {
            outputLines.append("<SYSTEM_CONTEXT>")
            outputLines.append(contentsOf: systemLines)
            outputLines.append("</SYSTEM_CONTEXT>")
        }
        if !normalizedBody.isEmpty {
            outputLines.append(normalizedBody)
        }

        return outputLines.joined(separator: "\n")
    }

    private static func normalizeContextBody(_ context: String) -> String {
        var lines = context.components(separatedBy: .newlines)

        while let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
        }

        if let first = lines.first,
           first.trimmingCharacters(in: .whitespacesAndNewlines)
           .compare("CONTEXT_METADATA", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        {
            lines.removeFirst()
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func missingSystemLines(
        in existingBody: String,
        now: Date,
        timeZone: TimeZone,
        locale: Locale,
        fullUserName: String
    ) -> [String] {
        let userName = fullUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUserName = userName.isEmpty ? "Unknown" : userName

        let entries: [(label: String, value: String)] = [
            ("Current time", formattedCurrentTime(now: now, locale: locale, timeZone: timeZone)),
            ("Time zone", timeZone.identifier),
            ("Locale", locale.identifier),
            ("User's full name", resolvedUserName)
        ]

        return entries.compactMap { entry in
            guard !containsLabel(entry.label, in: existingBody) else { return nil }
            return "- \(entry.label): \(entry.value)"
        }
    }

    private static func formattedCurrentTime(now: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd, HH:mm"
        return formatter.string(from: now)
    }

    private static func containsLabel(_ label: String, in context: String) -> Bool {
        let normalizedContext = context
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let normalizedLabel = label
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return normalizedContext.contains("\(normalizedLabel):")
    }
}
