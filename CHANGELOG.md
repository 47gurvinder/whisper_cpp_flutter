# Changelog

All notable changes to `whisper_cpp_flutter` are documented in this file.

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
