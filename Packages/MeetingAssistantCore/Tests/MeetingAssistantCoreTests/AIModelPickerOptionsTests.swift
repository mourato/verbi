@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class AIModelPickerOptionsTests: XCTestCase {
    func testOptionsPreserveRegistrationValuesAndSelectionWhileResolvingModelBrand() throws {
        let first = EnhancementsProviderModelOption(
            provider: .groq, registrationID: UUID(), registrationName: "Work Groq", modelID: "openai/gpt-oss-120b"
        )
        let second = EnhancementsProviderModelOption(
            provider: .groq, registrationID: UUID(), registrationName: "Personal Groq", modelID: first.modelID
        )
        let options = AIModelPickerOptions.make(options: [first, second]) { $0.registrationID == first.registrationID }

        XCTAssertEqual(options.map(\.groupTitle), ["Personal Groq", "Work Groq"])
        XCTAssertEqual(options.map(\.value), [second, first])
        XCTAssertEqual(options.map(\.id), [second.id, first.id])
        XCTAssertEqual(options.map(\.isSelected), [false, true])
        let selected = try XCTUnwrap(options.last)
        XCTAssertEqual(selected.title, "openai/gpt-oss-120b")
        XCTAssertEqual(selected.brand, .openai)
        XCTAssertEqual(selected.host, .groq)
        XCTAssertNil(selected.status)
    }

    func testOptionsFallBackToProviderGroupAndKeepLegacyProviderModelMatching() {
        let option = EnhancementsProviderModelOption(provider: .openai, modelID: "gpt-4o")
        let options = AIModelPickerOptions.make(options: [option]) {
            $0.provider == .openai && $0.modelID == "gpt-4o"
        }
        XCTAssertEqual(options.first?.groupTitle, AIProvider.openai.displayName)
        XCTAssertEqual(options.first?.brand, .openai)
        XCTAssertEqual(options.first?.isSelected, true)
    }
}
