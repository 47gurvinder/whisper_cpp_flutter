# whisper_cpp_flutter

Offline `whisper.cpp` v1.9.1 for Flutter, targeting Android and iOS only.

## Included

- Transcription and translation
- Automatic or explicit language selection
- Greedy and beam-search decoding
- Segment, word/token timestamps, probabilities and speaker-turn markers
- Initial prompts, suppression and decoding thresholds
- Integrated and standalone Silero VAD, including continuous VAD
- Non-blocking inference, progress streams and cancellation
- Microphone capture as mono 16 kHz `Float32` PCM
- Windowed real-time/streaming transcription
- PCM and WAV input with channel mixing and resampling
- Resumable model downloads, SHA-256 verification, listing and deletion
- Android CPU acceleration for ARM64 and ARMv7
- iOS Accelerate, Metal and optional Core ML encoder acceleration

The package vendors the exact upstream source revision associated with stable
whisper.cpp v1.9.1. Models are not bundled in the application.

## App configuration

Android already merges `RECORD_AUDIO`. Request it at runtime through
`WhisperRecorder.requestPermission()`.

Add this to the iOS application `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is used for offline transcription.</string>
```

The minimum versions are Android API 24 and iOS 14. Core ML is automatically
used when a compiled encoder named like
`ggml-base.en-encoder.mlmodelc` is placed next to `ggml-base.en.bin`; inference
falls back to Metal/CPU if it is absent.

## Download and load a model

```dart
final models = WhisperModelManager();
await for (final progress in models.download(
  Uri.parse('https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin'),
  'ggml-base.en.bin',
  sha256Hex: expectedSha256,
)) {
  print(progress.fraction);
}

final model = await models.find('ggml-base.en.bin');
final engine = await WhisperEngine.load(model!.path);
```

## Transcribe a WAV file

```dart
final samples = await WhisperAudio.readWav(File('/path/audio.wav'));
final task = engine.transcribe(samples, options: const TranscribeOptions(
  language: 'auto',
  tokenTimestamps: true,
  enableVad: true,
));
task.progress.listen(print);
final result = await task.result;
print(result.text);
```

For integrated VAD, also set `vadModelPath` in `TranscribeOptions` to a local
Silero VAD model path.

## Live microphone transcription

```dart
final recorder = WhisperRecorder();
if (await recorder.requestPermission()) {
  final session = WhisperStreamSession(engine);
  session.results.listen((partial) => print(partial.text));
  (await recorder.start()).listen((chunk) => session.add(chunk.samples));

  // Later:
  await recorder.stop();
  final complete = await session.close();
}
```

## Standalone VAD

```dart
final vad = WhisperVad.load('/path/ggml-silero-v6.2.0.bin');
final speech = vad.isSpeech(samples);
final ranges = vad.segments(samples);
vad.dispose();
```

Call `dispose()` on `WhisperEngine` and `WhisperVad` when finished. Do not run
two transcription jobs concurrently on the same engine; create separate engine
instances when parallel inference is required.

## License

This plugin and the vendored whisper.cpp source are available under the MIT
License. Whisper model licensing and distribution requirements remain the
application developer's responsibility.
