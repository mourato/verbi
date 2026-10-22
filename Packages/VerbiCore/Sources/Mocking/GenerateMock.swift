@attached(peer, names: prefixed(MacroMock))
public macro GenerateMock() = #externalMacro(
    module: "VerbiCoreMockingMacros",
    type: "GenerateMockMacro"
)
