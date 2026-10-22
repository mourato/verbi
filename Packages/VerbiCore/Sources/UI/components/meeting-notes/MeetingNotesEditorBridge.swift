import Foundation

public enum MeetingNotesEditorMessage: String, Codable, Sendable {
    case ready
    case edited
    case contentHeight
    case caret
    case close
}

public struct MeetingNotesEditorEditedPayload: Codable, Sendable {
    public let markdown: String
    public let caretOffset: Int?

    public init(markdown: String, caretOffset: Int? = nil) {
        self.markdown = markdown
        self.caretOffset = caretOffset
    }
}

public struct MeetingNotesEditorContentHeightPayload: Codable, Sendable {
    public let height: Double

    public init(height: Double) {
        self.height = height
    }
}

public struct MeetingNotesEditorLoadPayload: Codable, Sendable {
    public let documentId: String
    public let markdown: String
    public let caretOffset: Int?
    public let textSize: Int
    public let themeCSS: String

    public init(
        documentId: String,
        markdown: String,
        caretOffset: Int? = nil,
        textSize: Int,
        themeCSS: String
    ) {
        self.documentId = documentId
        self.markdown = markdown
        self.caretOffset = caretOffset
        self.textSize = textSize
        self.themeCSS = themeCSS
    }
}

enum MeetingNotesEditorBridgeCodec {
    static func encode(_ value: some Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return json
    }

    static func decodeEditedPayload(from body: Any) -> MeetingNotesEditorEditedPayload? {
        guard let dictionary = body as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dictionary)
        else {
            return nil
        }
        return try? JSONDecoder().decode(MeetingNotesEditorEditedPayload.self, from: data)
    }

    static func decodeContentHeight(from body: Any) -> MeetingNotesEditorContentHeightPayload? {
        guard let dictionary = body as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dictionary)
        else {
            return nil
        }
        return try? JSONDecoder().decode(MeetingNotesEditorContentHeightPayload.self, from: data)
    }
}
