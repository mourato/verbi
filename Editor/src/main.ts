import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { EditorState, Transaction, type Extension } from "@codemirror/state";
import {
  EditorView,
  drawSelection,
  keymap,
  placeholder,
} from "@codemirror/view";

import { livePreview } from "./live-preview";

const handler = window.webkit?.messageHandlers?.verbiNotes;

function post(type: string, payload: Record<string, unknown> = {}) {
  handler?.postMessage({ type, payload });
}

let view: EditorView | null = null;
let currentDocumentId = "";
let editTimer: ReturnType<typeof setTimeout> | null = null;

function applyTheme(themeCSS: string) {
  let style = document.getElementById("verbi-theme") as HTMLStyleElement | null;
  if (!style) {
    style = document.createElement("style");
    style.id = "verbi-theme";
    document.head.appendChild(style);
  }
  style.textContent = themeCSS || "";
}

function applyTextSize(textSize: number) {
  document.documentElement.style.setProperty("--text-size", `${textSize || 15}px`);
}

function reportContentHeight() {
  if (!view) {
    return;
  }
  const height = Math.ceil(view.scrollDOM.getBoundingClientRect().height);
  post("contentHeight", { height });
}

function scheduleEdited() {
  if (!view) {
    return;
  }
  if (editTimer) {
    clearTimeout(editTimer);
  }
  editTimer = setTimeout(() => {
    if (!view) {
      return;
    }
    post("edited", {
      markdown: view.state.doc.toString(),
      caretOffset: view.state.selection.main.head,
    });
    reportContentHeight();
  }, 120);
}

function createEditor(initialText: string): EditorView {
  const root = document.getElementById("editor-root");
  if (!root) {
    throw new Error("Missing #editor-root");
  }

  const extensions: Extension[] = [
    history(),
    drawSelection(),
    placeholder(""),
    markdown({ base: markdownLanguage }),
    ...livePreview(),
    keymap.of([...defaultKeymap, ...historyKeymap]),
    EditorView.lineWrapping,
    EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        scheduleEdited();
      }
      if (update.docChanged || update.geometryChanged) {
        reportContentHeight();
      }
    }),
    EditorView.theme({
      "&": { height: "100%", backgroundColor: "transparent" },
      ".cm-scroller": { overflow: "auto" },
    }),
  ];

  const state = EditorState.create({
    doc: initialText,
    extensions,
  });

  view = new EditorView({
    state,
    parent: root,
  });

  reportContentHeight();
  return view;
}

function ensureEditor(initialText = ""): EditorView {
  if (view) {
    return view;
  }
  return createEditor(initialText);
}

window.verbiNotesLoadNote = (payload) => {
  currentDocumentId = payload.documentId || "";
  applyTextSize(payload.textSize || 15);
  applyTheme(payload.themeCSS || "");

  const markdownText = payload.markdown || "";
  const editor = ensureEditor(markdownText);

  if (editor.state.doc.toString() !== markdownText) {
    editor.dispatch({
      changes: {
        from: 0,
        to: editor.state.doc.length,
        insert: markdownText,
      },
      annotations: Transaction.addToHistory.of(false),
    });
  }

  const caret = payload.caretOffset;
  if (typeof caret === "number" && caret >= 0 && caret <= markdownText.length) {
    editor.dispatch({
      selection: { anchor: caret },
      annotations: Transaction.addToHistory.of(false),
    });
  }

  editor.focus();
  reportContentHeight();
};

window.verbiNotesApplySettings = (payload) => {
  applyTextSize(payload.textSize || 15);
  applyTheme(payload.themeCSS || "");
  reportContentHeight();
};

post("ready");
