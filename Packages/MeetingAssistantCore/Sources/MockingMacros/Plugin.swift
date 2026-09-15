import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MeetingAssistantCoreMockingPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GenerateMockMacro.self
    ]
}
