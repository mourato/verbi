import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct VerbiCoreMockingPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GenerateMockMacro.self
    ]
}
