import Foundation

/// One substitution destination together with every origin spelling that maps
/// to it. Origins are edited as one entry because correcting a spelling once
/// should cover every misrecognition that leads to it.
///
/// This is the dictionary's in-memory shape. Persistence stays on
/// `VocabularyReplacementRule`, so stored keys and Codable shapes are unchanged.
public struct VocabularySubstitutionGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var destination: String
    public var origins: [String]

    public init(id: UUID = UUID(), destination: String, origins: [String]) {
        self.id = id
        self.destination = VocabularyNormalization.spelling(destination)
        self.origins = Self.normalizedOrigins(origins)
    }

    /// `true` when the entry deletes matched text instead of replacing it.
    public var isTextRemoval: Bool {
        destination.isEmpty
    }

    /// Case-sensitive identity of the destination. `US` and `us` stay separate.
    public var destinationKey: String {
        VocabularyNormalization.destinationKey(destination)
    }

    public var originKeys: Set<String> {
        Set(origins.map(VocabularyNormalization.originKey))
    }

    /// Returns a copy with only `origin` deleted. Identity and destination stay
    /// untouched so the remaining variants keep their entry.
    public func removingOrigin(_ origin: String) -> VocabularySubstitutionGroup {
        let key = VocabularyNormalization.originKey(origin)
        return VocabularySubstitutionGroup(
            id: id,
            destination: destination,
            origins: origins.filter { VocabularyNormalization.originKey($0) != key }
        )
    }

    /// Returns a copy with `additionalOrigins` appended, keeping the first
    /// displayed spelling of every origin.
    public func appendingOrigins(_ additionalOrigins: [String]) -> VocabularySubstitutionGroup {
        VocabularySubstitutionGroup(
            id: id,
            destination: destination,
            origins: origins + additionalOrigins
        )
    }

    /// Consolidates rules that share a normalized destination into one entry,
    /// preserving first-seen destination order, entry identity, and the first
    /// displayed spelling of every origin.
    ///
    /// Origins that point to more than one destination are intentionally kept
    /// in every entry. Legacy data can contain that conflict; dropping it here
    /// would lose an entry silently, so the dictionary surfaces it and asks for
    /// an explicit resolution.
    public static func groups(from rules: [VocabularyReplacementRule]) -> [VocabularySubstitutionGroup] {
        var groups: [VocabularySubstitutionGroup] = []
        var indexByDestinationKey: [String: Int] = [:]

        for rule in rules {
            let origins = rule.normalizedFindVariants
            guard !origins.isEmpty else { continue }

            let destination = VocabularyNormalization.spelling(rule.replace)
            let key = VocabularyNormalization.destinationKey(destination)

            if let index = indexByDestinationKey[key] {
                groups[index] = groups[index].appendingOrigins(origins)
            } else {
                indexByDestinationKey[key] = groups.count
                groups.append(
                    VocabularySubstitutionGroup(
                        id: rule.id,
                        destination: destination,
                        origins: origins
                    )
                )
            }
        }

        return groups
    }

    /// Origin keys that point at more than one destination in `rules`.
    public static func conflictingOriginKeys(in rules: [VocabularyReplacementRule]) -> Set<String> {
        var destinationsByOrigin: [String: Set<String>] = [:]

        for rule in rules {
            let destinationKey = VocabularyNormalization.destinationKey(rule.replace)
            for origin in rule.normalizedFindVariants {
                destinationsByOrigin[VocabularyNormalization.originKey(origin), default: []]
                    .insert(destinationKey)
            }
        }

        return Set(destinationsByOrigin.compactMap { origin, destinations in
            destinations.count > 1 ? origin : nil
        })
    }

    /// Merges `origins` into the entry for `destination`, keeping the entry
    /// identity when one already exists and appending every origin that other
    /// rules of the same destination contributed. The returned rules are the
    /// canonical consolidated shape used by both the settings editor and the
    /// quick correction editor.
    public static func merging(
        origins: [String],
        destination: String,
        into existingRules: [VocabularyReplacementRule],
        replacingEntryID: UUID? = nil
    ) -> [VocabularyReplacementRule] {
        let destinationKey = VocabularyNormalization.destinationKey(destination)
        let targetID = replacingEntryID
            ?? existingRules.first(where: {
                VocabularyNormalization.destinationKey($0.replace) == destinationKey
            })?.id
            ?? UUID()

        var mergedOrigins = origins
        var remainingRules: [VocabularyReplacementRule] = []
        var insertionIndex: Int?

        for rule in existingRules {
            let isEditedRule = rule.id == replacingEntryID
            let sharesDestination = VocabularyNormalization.destinationKey(rule.replace) == destinationKey

            guard isEditedRule || sharesDestination else {
                remainingRules.append(rule)
                continue
            }

            if insertionIndex == nil {
                insertionIndex = remainingRules.count
            }
            if !isEditedRule {
                mergedOrigins.append(contentsOf: rule.normalizedFindVariants)
            }
        }

        remainingRules.insert(
            VocabularyReplacementRule(
                id: targetID,
                find: mergedOrigins.joined(separator: ", "),
                replace: destination
            ),
            at: insertionIndex ?? remainingRules.count
        )

        return remainingRules
    }

    /// Removes every origin in `originKeys` from entries whose destination is
    /// not `destinationKey`. Entries left without origins are dropped because
    /// they would no longer do anything.
    public static func movingOrigins(
        _ originKeys: Set<String>,
        awayFrom destinationKey: String,
        in rules: [VocabularyReplacementRule]
    ) -> [VocabularyReplacementRule] {
        guard !originKeys.isEmpty else { return rules }

        return rules.compactMap { rule in
            guard VocabularyNormalization.destinationKey(rule.replace) != destinationKey else {
                return rule
            }

            let remaining = rule.normalizedFindVariants.filter {
                !originKeys.contains(VocabularyNormalization.originKey($0))
            }
            guard !remaining.isEmpty else { return nil }

            return VocabularyReplacementRule(
                id: rule.id,
                find: remaining.joined(separator: ", "),
                replace: rule.replace
            )
        }
    }

    /// Projects groups back onto the persisted rule shape. An entry without
    /// origins has no effect, so it is not persisted.
    public static func rules(from groups: [VocabularySubstitutionGroup]) -> [VocabularyReplacementRule] {
        groups.compactMap { group in
            guard !group.origins.isEmpty else { return nil }
            return VocabularyReplacementRule(
                id: group.id,
                find: group.origins.joined(separator: ", "),
                replace: group.destination
            )
        }
    }

    private static func normalizedOrigins(_ origins: [String]) -> [String] {
        var seenKeys = Set<String>()
        var ordered: [String] = []

        for origin in origins {
            let spelling = VocabularyNormalization.spelling(origin)
            let key = VocabularyNormalization.originKey(spelling)
            guard !spelling.isEmpty, seenKeys.insert(key).inserted else { continue }
            ordered.append(spelling)
        }

        return ordered
    }
}
