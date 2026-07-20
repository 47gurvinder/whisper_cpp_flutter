# whisper_cpp_flutter_plus

Run private, offline speech-to-text in Flutter with `whisper.cpp` v1.9.1.
This plugin provides native Android and iOS bindings for transcription,
translation, microphone capture, streaming results, model management, and
voice activity detection (VAD). Audio stays on the device after a model has
been downloaded or provided by your application.

## Features

- Offline transcription and translation
- Automatic or explicit language selection
- Greedy and beam-search decoding
- Segment, word, and token timestamps
- Token probabilities and speaker-turn markers
- Initial prompts, token suppression, and decoding thresholds
- Non-blocking inference with progress updates and cancellation
- Complete-recording and live microphone transcription
- Windowed streaming for any mono PCM source
- WAV decoding, channel mixing, and sample-rate conversion
- Integrated and standalone Silero VAD, including continuous VAD
- Resumable model downloads, SHA-256 verification, listing, and deletion
- Android CPU acceleration for ARM64 and ARMv7
- iOS Accelerate, Metal, and optional Core ML encoder acceleration

The package vendors the upstream source revision associated with stable
`whisper.cpp` v1.9.1. Whisper and Silero model files are not bundled.

## Supported platforms

- Android API 24 or later
- iOS 14 or later

Web, macOS, Windows, and Linux are not currently supported.

## Installation

Add the package to your Flutter project:

```sh
flutter pub add whisper_cpp_flutter_plus
```

Import the public API:

```dart
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
```

## Platform configuration

### Android

The plugin adds `RECORD_AUDIO` to the merged manifest. Request permission at
runtime with `WhisperRecorder.requestPermission()`, or let
`WhisperEngine.transcribeMicrophone()` request it when live transcription
starts.

### iOS

Add a microphone usage description to your application's `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is used for offline transcription.</string>
```

To use Core ML acceleration, place a compiled encoder such as
`ggml-base.en-encoder.mlmodelc` beside the matching `ggml-base.en.bin` model.
If the encoder is unavailable, inference falls back to Metal or the CPU.

## Load a model

Your application can obtain a compatible GGML model from any source and pass
its readable local filesystem path directly to the engine:

```dart
final modelPath = await downloadModelToAppStorage();
final engine = await WhisperEngine.load(modelPath);
```

`WhisperEngine.load()` does not copy, move, or take ownership of the file. Keep
the model available until `engine.dispose()` is called.

### Optional model manager

`WhisperModelManager` can download and manage models in the application support
directory. It accepts any HTTP or HTTPS URL; Hugging Face is only one possible
source.

```dart
final models = WhisperModelManager();

await for (final progress in models.download(
  Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/'
    'resolve/main/ggml-base.en.bin',
  ),
  'ggml-base.en.bin',
  // sha256Hex: 'expected model checksum',
)) {
  print(progress.fraction);
}

final model = await models.find('ggml-base.en.bin');
if (model == null) {
  throw StateError('Model download did not complete.');
}

final engine = await WhisperEngine.load(model.path);
```

Supplying `sha256Hex` is recommended when the expected checksum is known.

## Transcribe a WAV file

`WhisperAudio.readWav()` converts supported WAV input to the mono 16 kHz
`Float32` PCM expected by whisper.cpp.

```dart
final samples = await WhisperAudio.readWav(File('/path/to/audio.wav'));
final task = engine.transcribe(
  samples,
  options: const TranscribeOptions(
    language: 'auto',
    tokenTimestamps: true,
  ),
);

task.progress.listen((percent) => print('$percent%'));

final result = await task.result;
print(result.text);
```

Call `task.cancel()` to stop active inference.

## Transcribe the microphone live

```dart
final task = await engine.transcribeMicrophone(
  options: const TranscribeOptions(language: 'en'),
);

task.updates.listen((update) {
  print(update.text);
});

// Flush the remaining audio and finish the transcript.
final complete = await task.stop();
print(complete.confirmedText);
```

The plugin manages microphone permission, capture, rolling windows, overlap
removal, timestamp rebasing, and final flushing. With the default
`WhisperStreamConfig`, it decodes every two seconds using a 30-second window
and keeps the newest four seconds provisional.

`confirmedText` and `confirmedSegments` are append-only. Partial content can
change as later windows add context, so replace it in the UI on every update.
`stop()` produces a final result, while `cancel()` aborts the operation with a
`WhisperException`.

Smaller models are recommended when transcription must keep up with speech on
mobile hardware.

## Transcribe another PCM stream

Use the same streaming pipeline with any stream of mono PCM chunks:

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
final complete = await task.result;
```

Chunks are continuously resampled to 16 kHz. The source must use one sample
rate for the lifetime of a stream. The task completes when the source stream
closes.

## Voice activity detection

For integrated VAD, set both `enableVad` and `vadModelPath`:

```dart
final task = engine.transcribe(
  samples,
  options: const TranscribeOptions(
    enableVad: true,
    vadModelPath: '/path/to/ggml-silero-v6.2.0.bin',
  ),
);
```

Silero VAD can also be used independently:

```dart
final vad = WhisperVad.load('/path/to/ggml-silero-v6.2.0.bin');
final containsSpeech = vad.isSpeech(samples);
final speechRanges = vad.segments(samples);
vad.dispose();
```

## Resource management

Call `dispose()` on every `WhisperEngine` and `WhisperVad` when it is no longer
needed. A one-shot or streaming job reserves its engine until completion. Use
separate engine instances for parallel inference.

## Example application

Connect a physical Android or iOS device and run:

```sh
cd example
flutter pub get
flutter run
```

The example downloads the tiny English model once and demonstrates both
record-then-transcribe and recorder-style live transcription.

## Need help with whisper.cpp or another AI solution?

Looking to integrate this plugin into an existing app, build a custom product
on top of whisper.cpp, or create another AI-powered mobile or web solution? I
can help with architecture, Flutter plugin development, native Android and iOS
integration, speech-to-text workflows, model integration, performance
optimization, debugging, upgrades, and long-term maintenance.

Whether you need a focused integration, a custom plugin, help maintaining an
existing package, or a complete application, get in touch to discuss your
requirements:

- [Contact Gurwinder DevX](https://gurwinderdevx.com/)
- [Hire me on Upwork](https://www.upwork.com/freelancers/gurwinderdevx)

## Author and support

Developed and maintained by **Gurwinder Singh**, a full-stack web and mobile
application developer and founder of
[Gurwinder DevX](https://gurwinderdevx.com/).

- [GitHub](https://github.com/47gurvinder)
- [LinkedIn](https://www.linkedin.com/in/gurwinderdevx/)
- [Upwork](https://www.upwork.com/freelancers/gurwinderdevx)
- [Buy Me a Coffee](https://buymeacoffee.com/gurwinderdevx)

If this package helps your project, consider supporting its continued
development through Buy Me a Coffee.

## Acknowledgements

This plugin builds on the work of the
[whisper.cpp authors and contributors](https://github.com/ggml-org/whisper.cpp).

## License

This plugin and the vendored whisper.cpp source are available under the MIT
License. Whisper model licensing and distribution requirements remain the
application developer's responsibility.
