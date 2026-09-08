# Verbi Domain Context

Verbi captures local-first dictation and meetings, transcribes the captured
audio, and processes the resulting text.

## Capture and transcription

**Dictation mode**:
A saved set of choices for a class of dictation captures, selected before a
capture begins and applied to that capture.
_Avoid_: profile, preset, style

**Transcription configuration**:
The concrete provider, model, input-language hint, and vocabulary choices in
effect for one transcription operation.
_Avoid_: live transcription settings, provider override

**Incremental transcription**:
Transcription of short audio windows during an active capture to provide a
live partial result before the completed audio file is processed.
_Avoid_: streaming transcription
