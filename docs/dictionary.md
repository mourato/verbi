# Vocabulary and Substitutions — Truthful Support

This page documents how the dictionary surfaces explain what saved vocabulary
does for each transcription setup, and where that explanation comes from in the
code.

## What vocabulary does

Vocabulary terms are a **recognition preference and spelling hint**, not model
training. Sending term strings to a remote speech-recognition provider biases
how the model hears and spells those words; nothing is written back to the
model. **Substitutions** are different: they are explicit, deterministic
replacements applied to the transcript after recognition (and before AI cleanup
when AI post-processing is enabled).

## Where support is shown

- **Settings > Dictionary > Vocabulary**: a "Recognition support" section shows
  the active dictation/assistant provider and model, the hint mechanism it
  accepts, how many terms would be sent, and which terms are skipped.
- **Settings > Models**: every model row in the transcription model catalog
  carries a vocabulary capability label in its subtitle.

## Where the truth comes from

The UI derives everything from the same owners the request boundary uses; there
is no second capability registry:

- `TranscriptionProvider.vocabularyHelper` (VerbiCoreInfrastructure) is the
  single mapping of provider → hint parameter. It mirrors the routing in
  `TranscriptionClient.transcribeConfigured`:
  - **local**: no hints. Local FluidAudio ASR (including the incremental path)
    has no vocabulary parameter.
  - **Groq / OpenAI**: the Whisper-compatible `prompt` field.
  - **ElevenLabs**: repeated `keyterms` fields.
- `VocabularySnapshot` (VerbiCoreDomain) owns all wire limits and projections.
  The summary (`VocabularyRecognitionSupport`) calls the *same* projection
  functions (`projectedGroqPrompt`, `projectedElevenLabsKeyterms`) that the
  request boundary applies, so counts can never drift from what is actually
  sent: Groq/OpenAI prompt capped at whole terms up to the prompt budget,
  ElevenLabs keyterms capped at the documented per-term length, unsupported
  characters, and count limits.
- The AI-enhancement explanation is conditional: terms guide spelling when
  enhancement runs for the capture's mode and provider. A global switch cannot
  describe every dictation mode, so this page does not report it as the active
  dictation state.

When AI enhancement runs, terms also reach it as a `<VOCABULARY>` spelling
context (escaped, definitions ignored). The support UI labels this explicitly.

## Privacy bounds (unchanged)

Term strings — never their definitions — may leave the device as hints for the
selected remote provider, and as spelling context when remote AI enhancement
runs. Local ASR alone sends nothing off-device. The support view discloses this
whenever a remote path would send terms. No network request is made just to
show support, and no term content is logged.

## Tests

`VocabularyRecognitionSupportTests` pins the provider mapping and the
used/skipped results with fictional terms and the real wire limits.
`VocabularySnapshotTests` continues to own the projection limits.
