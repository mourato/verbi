import Foundation

public struct MeetingNotesContent: Equatable, Sendable {
    public var plainText: String
    public var richTextRTFData: Data?

    public init(plainText: String, richTextRTFData: Data? = nil) {
        self.plainText = plainText
        self.richTextRTFData = richTextRTFData
    }

    public static let empty = MeetingNotesContent(plainText: "", richTextRTFData: nil)
}
