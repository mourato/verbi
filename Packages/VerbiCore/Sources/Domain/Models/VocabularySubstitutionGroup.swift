import Foundation

public struct VocabularySubstitutionGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var destination: String
    public var origins: [String]

    public init(id: UUID = UUID(), destination: String, origins: [String]) {
        self.id = id
        self.destination = VocabularyNormalization.spelling(destination)
        self.origins = Self.normalizedOrigins(origins)
    }

    public var isTextRemoval: Bool {
        destination.isEmpty
    }

    public var destinationKey: String {
        VocabularyNormalization.destinationKey(destination)
    }

    public var originKeys: Set<String> {
        Set(origins.map(VocabularyNormalization.originKey))
    }

    public func removingOrigin(_ origin: String) -> VocabularySubstitutionGroup {
        let key = VocabularyNormalization.originKey(origin)
        return VocabularySubstitutionGroup(
            id: id,
            destination: destination,
            origins: origins.filter { VocabularyNormalization.originKey($0) != key }
        )
    }

    public func appendingOrigins(_ additionalOrigins: [String]) -> VocabularySubstitutionGroup {
        VocabularySubstitutionGroup(
            id: id,
            destination: destination,
            origins: origins + additionalOrigins
        )
    }

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
