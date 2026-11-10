@testable import VerbiCore
import XCTest

final class VocabularySubstitutionGroupTests: XCTestCase {
    // MARK: - Grouping

    func testGroupsConsolidateVariantsThatShareDestination() {
        let rules = [
            VocabularyReplacementRule(find: "raycast", replace: "Raycast"),
            VocabularyReplacementRule(find: "reycast", replace: " Raycast ")
        ]

        let groups = VocabularySubstitutionGroup.groups(from: rules)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.destination, "Raycast")
        XCTAssertEqual(groups.first?.origins, ["raycast", "reycast"])
        XCTAssertEqual(groups.first?.id, rules.first?.id)
    }

    func testGroupsKeepCaseSensitiveDestinationsApart() {
        let rules = [
            VocabularyReplacementRule(find: "you ess", replace: "US"),
            VocabularyReplacementRule(find: "us", replace: "us")
        ]

        let groups = VocabularySubstitutionGroup.groups(from: rules)

        XCTAssertEqual(groups.map(\.destination), ["US", "us"])
        XCTAssertEqual(groups.map(\.origins), [["you ess"], ["us"]])
    }

    func testGroupsPreserveOriginsThatConflictAcrossDestinations() {
        let rules = [
            VocabularyReplacementRule(find: "raycast", replace: "Raycast"),
            VocabularyReplacementRule(find: "raycast", replace: "Ray Cast")
        ]

        let groups = VocabularySubstitutionGroup.groups(from: rules)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].origins, ["raycast"])
        XCTAssertEqual(groups[1].origins, ["raycast"])
    }

    func testGroupsDropEntriesWithoutOrigins() {
        let rules = [
            VocabularyReplacementRule(find: "   ", replace: "Ignored"),
            VocabularyReplacementRule(find: "kept", replace: "")
        ]

        let groups = VocabularySubstitutionGroup.groups(from: rules)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.destination, "")
        XCTAssertTrue(groups.first?.isTextRemoval == true)
    }

    func testGroupsNormalizeWhitespaceAndUnicodeWithoutReordering() {
        let rules = [
            VocabularyReplacementRule(find: "  cafe\u{301}  ", replace: "  Café  "),
            VocabularyReplacementRule(find: "café", replace: "Café")
        ]

        let groups = VocabularySubstitutionGroup.groups(from: rules)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.destination, "Café")
        XCTAssertEqual(groups.first?.origins, ["café"])
    }

    // MARK: - Partial removal

    func testRemovingOriginKeepsEntryIdentityAndOtherVariants() {
        let entry = VocabularySubstitutionGroup(
            destination: "Raycast",
            origins: ["raycast", "reycast", "recast"]
        )

        let remaining = entry.removingOrigin("REYCAST")

        XCTAssertEqual(remaining.id, entry.id)
        XCTAssertEqual(remaining.destination, "Raycast")
        XCTAssertEqual(remaining.origins, ["raycast", "recast"])
        XCTAssertEqual(entry.origins.count, 3, "Removal must not mutate the original entry")
    }

    func testRemovingOriginMatchesCanonicallyEquivalentSpelling() {
        let entry = VocabularySubstitutionGroup(
            destination: "Café",
            origins: ["cafe\u{301}", "café"]
        )

        XCTAssertEqual(entry.origins, ["café"], "Equivalent spellings dedupe on intake")
        XCTAssertTrue(entry.removingOrigin("café").origins.isEmpty)
    }

    // MARK: - Projection

    func testRulesFromGroupsRoundTripsDestinationAndOrigins() {
        let groups = [
            VocabularySubstitutionGroup(destination: "Raycast", origins: ["raycast", "reycast"]),
            VocabularySubstitutionGroup(destination: "", origins: ["hum"])
        ]

        let rules = VocabularySubstitutionGroup.rules(from: groups)

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].id, groups[0].id)
        XCTAssertEqual(rules[0].find, "raycast, reycast")
        XCTAssertEqual(rules[0].replace, "Raycast")
        XCTAssertEqual(rules[1].replace, "")
    }

    func testRulesFromGroupsDropsEntriesWithoutOrigins() {
        let rules = VocabularySubstitutionGroup.rules(from: [
            VocabularySubstitutionGroup(destination: "Unused", origins: []),
            VocabularySubstitutionGroup(destination: "Kept", origins: ["kept"])
        ])

        XCTAssertEqual(rules.map(\.replace), ["Kept"])
    }

    func testAppendingOriginsDedupesCaseInsensitively() {
        let entry = VocabularySubstitutionGroup(destination: "Raycast", origins: ["raycast"])
        let merged = entry.appendingOrigins(["RayCast", "reycast"])

        XCTAssertEqual(merged.origins, ["raycast", "reycast"])
    }
}
