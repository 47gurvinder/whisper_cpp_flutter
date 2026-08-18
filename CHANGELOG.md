# Changelog

All notable changes to `whisper_cpp_flutter_plus` are documented in this file.

## 0.4.1 - 2026-08-18

### Changed

- Updated the bundled whisper.cpp core from v1.9.1 to v1.9.2, including ggml
  0.18.1 and upstream CJK voice-length improvements.
- Mapped token timestamps back to the original input-audio timeline when
  integrated VAD removes silence.

## 0.4.0 - 2026-07-30

### Added

- Added plain text, JSON, SRT, and WebVTT transcription result exports.
- Added cancellable sequential PCM/WAV batch transcription that reuses one
  loaded engine and can optionally capture per-item failures.
- Added a curated model catalog with immutable upstream revisions, SHA-256
  verification, and catalog-aware model downloads.

### Changed

- Hardened managed model paths, made HTTPS the download default, and added
  explicit model-manager client cleanup.

## 0.3.0 - 2026-07-27

### Added

- Added iOS Swift Package Manager support alongside CocoaPods.
- Added API documentation for the package's exported Dart types and members.

### Changed

- Reorganized the bundled whisper.cpp core and Flutter bridge into shared native
  sources used by Android, CocoaPods, and Swift Package Manager.
- Reformatted Dart sources for improved readability and maintainability without
  intended behavior changes.

## 0.2.0 - 2026-07-23

### Added

- Added reusable Responsive, Balanced, and Efficient offline transcription
  modes, plus an example mode selector.
- Expanded the manual benchmark to compare all three modes with rotating run
  order and complete schema-v3 JSON configuration reporting.
- Added benchmark WAV playback for manually cross-checking generated
  transcripts against the bundled source audio.
- Added a reproducible physical-device benchmark with a fixed tiny English
  model configuration, JFK audio fixture, multi-run statistics, transcript
  accuracy checks, cancellation, and copyable JSON results in the example app.

## 0.1.3 - 2026-07-20

### Added

- Added example-app screenshots to the package README, showcasing offline
  speech-to-text, live transcription, Silero VAD, and local diarization.

## 0.1.2 - 2026-07-20

### Added

- Added a dedicated local diarization example using the TinyDiarize-compatible
  `ggml-small.en-tdrz.bin` model.
- Added model download, microphone recording, progress, cancellation, and
  speaker-turn visualization to the diarization example.
- Added the `gdx` pub.dev topic for packages maintained by Gurwinder DevX.

### Changed

- Documented the experimental two-speaker TinyDiarize workflow and its
  speaker-turn boundary limitations.

## 0.1.1 - 2026-07-20

### Changed

- Expanded the example application to download and cache the Silero VAD model.
- Enabled integrated VAD for recorded and live transcription in the example,
  with an enabled-by-default switch for comparing behavior without VAD.
- Documented the example's VAD setup, model requirements, and silence-filtering
  behavior.

## 0.1.0 - 2026-07-20

Initial public release for Android and iOS.

### Added

- Offline whisper.cpp v1.9.1 transcription and translation.
- Automatic and explicit language selection.
- Greedy and beam-search decoding with configurable prompts, suppression, and
  thresholds.
- Segment, word, and token timestamps, token probabilities, and speaker-turn
  markers.
- Non-blocking inference with progress streams and cancellation.
- Microphone recording as mono 16 kHz `Float32` PCM.
- Complete-recording and windowed live transcription workflows.
- Streaming transcription for arbitrary mono PCM sources with continuous
  resampling, overlap removal, and timestamp rebasing.
- WAV decoding with channel mixing and sample-rate conversion.
- Integrated and standalone Silero voice activity detection, including
  continuous VAD.
- Optional model management with resumable downloads, SHA-256 verification,
  discovery, listing, and deletion.
- Android support for ARM64 and ARMv7 with CPU acceleration.
- iOS Accelerate and Metal support with optional Core ML encoder acceleration.
- Example application demonstrating model download, recording transcription,
  live transcription, progress reporting, and cancellation.
