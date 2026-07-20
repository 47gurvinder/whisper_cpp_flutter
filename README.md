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

## Run the example app

Connect a physical Android or iOS device, then run:

```sh
cd example
flutter pub get
flutter run
```

The example downloads the tiny English model and demonstrates both complete
recording transcription and recorder-style live transcription. The model
download is required only once.

## Provide and load a model

Models do not need to come from Hugging Face or be downloaded by this package.
If your application downloads a model into its own cache or support directory,
pass that readable local path directly to the engine:

```dart
final cacheModelPath = await downloadModelToAppCache();
final engine = await WhisperEngine.load(cacheModelPath);
```

`WhisperEngine.load` does not copy or take ownership of the model. Keep the
file available at that path until `engine.dispose()` is called.

`WhisperModelManager` is an optional convenience for applications that want
the package to download and manage model files. Its downloader accepts any
HTTP(S) URL; the Hugging Face URL below is only an example:

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
final task = await engine.transcribeMicrophone(
  options: const TranscribeOptions(language: 'en'),
);

task.updates.listen((update) {
  // confirmedText is append-only. partialText may change on later passes.
  print(update.text);
});

// Later, flush the remaining audio and stop the microphone.
final complete = await task.stop();
print(complete.confirmedText);
```

The plugin owns microphone permission, capture, rolling audio windows, overlap
removal, timestamp rebasing, and final flushing. The default
`WhisperStreamConfig` decodes every two seconds using a 30-second window and
keeps the newest four seconds provisional. Smaller models are recommended when
the transcript must keep up in real time on mobile hardware.

`confirmedSegments` and `partialSegments` use timestamps measured from the
beginning of the recording. Confirmed content never changes; partial content is
intended to be replaced in the UI on every update. `stop()` completes normally,
while `cancel()` aborts active inference and completes with a
`WhisperException`.

## Transcribe another PCM stream

Any stream of mono floating-point PCM can use the same pipeline:

```dart
final task = engine.transcribeStream(
  audioChunks, // Stream<RecordingChunk>
  options: const TranscribeOptions(language: 'auto'),
  config: const WhisperStreamConfig(
    updateInterval: Duration(seconds: 2),
    windowDuration: Duration(seconds: 30),
    confirmationLag: Duration(seconds: 4),
  ),
);

task.updates.listen((update) => print(update.text));
final complete = await task.result; // completes when the input stream closes
```

Chunks are resampled continuously to 16 kHz inside the plugin. A stream must
keep one sample rate for its lifetime. Integrated VAD remains optional: enable
it through `TranscribeOptions.enableVad` and `vadModelPath` when a Silero model
is available; live transcription does not otherwise require a second model.

## Standalone VAD

```dart
final vad = WhisperVad.load('/path/ggml-silero-v6.2.0.bin');
final speech = vad.isSpeech(samples);
final ranges = vad.segments(samples);
vad.dispose();
```

Call `dispose()` on `WhisperEngine` and `WhisperVad` when finished. One-shot and
streaming jobs reserve their engine until completion; create separate engine
instances when parallel inference is required.

## Author

Developed and maintained by **Gurwinder Singh**, a full-stack web and mobile
application developer at [Skyno Digital LLP](https://skynodigital.com/).

- [Website](https://gurwinderdevx.com/)
- [GitHub](https://github.com/47gurvinder)
- [LinkedIn](https://www.linkedin.com/in/gurwinderdevx/)
- [Upwork](https://www.upwork.com/freelancers/gurwinderdevx)

This plugin builds on the work of the
[whisper.cpp authors and contributors](https://github.com/ggml-org/whisper.cpp).

## License

This plugin and the vendored whisper.cpp source are available under the MIT
License. Whisper model licensing and distribution requirements remain the
application developer's responsibility.
