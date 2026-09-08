export {};

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        verbiNotes?: { postMessage(message: unknown): void };
      };
    };
    verbiNotesLoadNote: (payload: {
      documentId?: string;
      markdown?: string;
      caretOffset?: number | null;
      textSize?: number;
      themeCSS?: string;
    }) => void;
    verbiNotesApplySettings: (payload: {
      textSize?: number;
      themeCSS?: string;
    }) => void;
  }
}
