@attached(peer, names: prefixed(MacroMock))
public macro GenerateMock() = #externalMacro(
    module: "MeetingAssistantCoreMockingMacros",
    type: "GenerateMockMacro"
)
