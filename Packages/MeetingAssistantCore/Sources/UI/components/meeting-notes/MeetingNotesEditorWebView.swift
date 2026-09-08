import AppKit
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI
import WebKit

struct MeetingNotesEditorWebView: NSViewRepresentable {
    let documentId: String
    let content: MeetingNotesContent
    let textSize: Int
    let themeCSS: String
    let onContentChange: (MeetingNotesContent) -> Void
    var onContentHeightChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onContentChange: onContentChange, onContentHeightChange: onContentHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: Coordinator.handlerName)
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.loadIfNeeded(
            documentId: documentId,
            content: content,
            textSize: textSize,
            themeCSS: themeCSS,
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onContentHeightChange = onContentHeightChange
        context.coordinator.applySettings(textSize: textSize, themeCSS: themeCSS)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let handlerName = "verbiNotes"

        var webView: WKWebView?
        let onContentChange: (MeetingNotesContent) -> Void
        var onContentHeightChange: ((CGFloat) -> Void)?
        private var loadedDocumentId: String?
        private var isEditorReady = false
        private var pendingLoad: MeetingNotesEditorLoadPayload?

        init(
            onContentChange: @escaping (MeetingNotesContent) -> Void,
            onContentHeightChange: ((CGFloat) -> Void)?,
        ) {
            self.onContentChange = onContentChange
            self.onContentHeightChange = onContentHeightChange
        }

        func loadIfNeeded(
            documentId: String,
            content: MeetingNotesContent,
            textSize: Int,
            themeCSS: String,
        ) {
            guard let webView else { return }

            if loadedDocumentId == nil {
                loadedDocumentId = documentId
                if let url = Bundle.module.url(
                    forResource: "index",
                    withExtension: "html",
                    subdirectory: "MeetingNotesEditor/dist",
                ) {
                    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                } else {
                    webView.loadHTMLString(Self.fallbackHTML, baseURL: nil)
                }
            }

            let payload = MeetingNotesEditorLoadPayload(
                documentId: documentId,
                markdown: content.plainText,
                textSize: textSize,
                themeCSS: themeCSS,
            )
            pendingLoad = payload
            sendLoadIfReady()
        }

        func applySettings(textSize: Int, themeCSS: String) {
            guard isEditorReady,
                  let payloadJSON = MeetingNotesEditorBridgeCodec.encode(
                      MeetingNotesEditorLoadPayload(
                          documentId: loadedDocumentId ?? "",
                          markdown: "",
                          textSize: textSize,
                          themeCSS: themeCSS,
                      ),
                  )
            else {
                return
            }

            webView?.evaluateJavaScript("window.verbiNotesApplySettings(\(payloadJSON))")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.handlerName else { return }

            guard let body = message.body as? [String: Any],
                  let typeRaw = body["type"] as? String,
                  let type = MeetingNotesEditorMessage(rawValue: typeRaw)
            else {
                return
            }

            switch type {
            case .ready:
                isEditorReady = true
                sendLoadIfReady()
            case .edited:
                guard let payload = MeetingNotesEditorBridgeCodec.decodeEditedPayload(from: body["payload"] ?? body) else {
                    return
                }
                onContentChange(MeetingNotesContent(plainText: payload.markdown))
            case .contentHeight:
                guard let payload = MeetingNotesEditorBridgeCodec.decodeContentHeight(from: body["payload"] ?? body) else {
                    return
                }
                onContentHeightChange?(CGFloat(payload.height))
            case .caret, .close:
                break
            }
        }

        private func sendLoadIfReady() {
            guard isEditorReady,
                  let payload = pendingLoad,
                  let payloadJSON = MeetingNotesEditorBridgeCodec.encode(payload)
            else {
                return
            }

            webView?.evaluateJavaScript("window.verbiNotesLoadNote(\(payloadJSON))")
            pendingLoad = nil
        }

        private static let fallbackHTML = """
        <!doctype html><html><head><meta charset=\"utf-8\"><style>
        html,body{margin:0;height:100%;font:15px -apple-system,BlinkMacSystemFont,sans-serif}
        textarea{width:100%;height:100%;border:0;padding:12px;resize:none;background:transparent;color:CanvasText}
        </style></head><body><textarea id=\"editor\"></textarea><script>
        const handler = window.webkit.messageHandlers.verbiNotes;
        const editor = document.getElementById('editor');
        window.verbiNotesLoadNote = (payload) => {
          editor.style.fontSize = (payload.textSize || 15) + 'px';
          editor.value = payload.markdown || '';
        };
        window.verbiNotesApplySettings = (payload) => {
          editor.style.fontSize = (payload.textSize || 15) + 'px';
        };
        editor.addEventListener('input', () => {
          handler.postMessage({ type: 'edited', payload: { markdown: editor.value } });
        });
        handler.postMessage({ type: 'ready' });
        </script></body></html>
        """
    }
}

#if DEBUG
#Preview("Meeting Notes Web Editor") {
    MeetingNotesEditorWebView(
        documentId: "preview-note",
        content: MeetingNotesContent(plainText: "# Notes\n\n- item"),
        textSize: 15,
        themeCSS: "",
        onContentChange: { _ in },
    )
    .frame(width: 420, height: 280)
}
#endif
