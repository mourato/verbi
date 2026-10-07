## Phase 0 Audio Baseline (2026-05-25)

### Scope
- Goal: establish Phase 0 baseline for the Rust-audio pilot and architecture refactor track.
- Risk classification: **High** (audio hot path + architecture changes), lane: **Full**.
- Reuse/extend/create: **Reuse** existing QA and profiling command surface (`make test-sensitive`, `make test-perf`, `make profile-*`) and existing instrumentation points.

### Execution With Stall Watchdog
- All long commands were executed with a watchdog wrapper that prints heartbeat every 10-20s (`elapsed`, `log_bytes`, `pid`, `children`) and force-terminates on timeout.
- This made stalled `xctrace export` visible immediately and prevented indefinite hangs.

### Command Results
- `make test-sensitive`: **failed** (6 failures, existing `RecordingManagerTests` readiness assertions).
  - Failing assertions observed in `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/RecordingManagerTests.swift` around lines `222`, `382`, `383`, `403`, `404`, `712`.
- `make test-perf`: **passed** (`Total: 9 | Passed: 9 | Failed: 0`).
- `make profile-cpu` (watchdog): **passed**.
  - Trace: `performance-reports/profile_20260525_150342_cpu.trace`
  - Metrics: `performance-reports/profile_20260525_150342_cpu_metrics.txt`
- `./scripts/profile-performance.sh --memory --no-report` (watchdog): **passed**.
  - Trace: `performance-reports/profile_20260525_151128_memory.trace`
- `./scripts/profile-performance.sh --animation --no-report` (watchdog): **passed**.
  - Trace: `performance-reports/profile_20260525_151218_animation.trace`

### Baseline Hotspots (Current Swift)

#### 1) VAD window assembly
- File: `Packages/MeetingAssistantCore/Sources/Audio/Services/RealtimeVoiceActivityWindowAssembler.swift:96`
- Current constants snapshot:
  - `sampleRate = 16_000`, `frameDurationSeconds = 0.03`, `frameSampleCount = 480`
  - `speechThresholdDB = -48`
  - `speechStartFrameCount = 6`, `speechEndFrameCount = 15`
  - `preRollFrameCount = 7`, `tailFrameCount = 8`
  - `commitSpokenFrameCount = 400`
- Targeted tests: `RealtimeVoiceActivityWindowAssemblerTests` passed (`2/2`).

#### 2) RMS/peak/bar metering
- File: `Packages/MeetingAssistantCore/Sources/Audio/Services/AudioRecordingWorker.swift:352`
- Entry point: `AudioRecordingWorker.makeMeterSnapshot(from:barCount:)`.
- Perf suite baseline (`AudioRecordingWorkerTests.testPerformance_BufferProcessing_Guardrail`):
  - Clock avg: `0.000160 s`
  - CPU instructions retired avg: `7889.923 kI`
  - CPU cycles avg: `2463.923 kC`
  - CPU time avg: `0.001 s`

#### 3) Silence compaction analysis
- File: `Packages/MeetingAssistantCore/Sources/Audio/Services/AudioSilenceCompactor.swift:122`
- Current constants snapshot:
  - `windowDurationSeconds = 0.03`
  - `silenceThresholdDB = -48`
  - `minimumSilenceDurationSeconds = 0.9`
  - `mergeGapDurationSeconds = 0.25`
  - `paddingDurationSeconds = 0.12`
  - `analysisChunkFrames = 8192`
- Targeted tests: `AudioSilenceCompactorTests` passed (`6/6`).

### Supporting Perf Signals
- Perf suite (`AudioSystemPerformanceTests`) baseline:
  - Buffer creation avg: `0.049 s`
  - Enqueue/dequeue avg: `0.001 s`
  - High throughput avg: `0.000 s`
  - Overflow handling avg: `0.000 s`
  - Clear operation avg: `0.004 s`
  - Concurrent ops avg: `0.000 s`
  - Stats access avg: `0.005 s`
- CPU trace summary (`profile_20260525_150342_cpu_metrics.txt`):
  - `selected_schema=time-profile`
  - `rows=952`

### Reliability / Safety Baseline Signals Already Present
- Dropped frame warning at stop path: `Packages/MeetingAssistantCore/Sources/Audio/Services/AudioRecorder/AudioRecorder.swift:407`.
- Silence compaction metrics and fallback behavior: `Packages/MeetingAssistantCore/Sources/UI/Services/RecordingManager/AudioPreparation.swift:54` and `Packages/MeetingAssistantCore/Sources/UI/Services/RecordingManager/AudioPreparation.swift:76`.
- Incremental transcription fallback telemetry path: `Packages/MeetingAssistantCore/Sources/UI/Services/RecordingManager/RecordingControl.swift:375` and `Packages/MeetingAssistantCore/Sources/UI/Services/RecordingManager/RecordingControl.swift:443`.

### Known Limitation (Phase 0)
- Full profiling with report extraction (`make profile` in the current command surface) can stall on `xctrace export` for memory/animation traces.
- Operational workaround for reliable baselines:
  1. run `make profile-cpu` (or `--cpu --report`) under watchdog,
  2. run memory/animation with `--no-report` under watchdog,
  3. keep raw `.trace` artifacts for manual Instruments drill-down.

### Phase 1 Entry Criteria Status
- Baseline commands executed and recorded: **yes**.
- Hotspot constants and test baselines captured: **yes**.
- Blocking instability found in sensitive suite (non-audio readiness tests): **yes** (tracked for awareness before merge gates in later phases).
