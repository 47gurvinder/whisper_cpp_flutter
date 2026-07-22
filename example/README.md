# whisper_cpp_flutter_plus example

A complete Flutter example for private, on-device speech-to-text with
`whisper_cpp_flutter_plus`. It demonstrates how to download and load a whisper.cpp
model, record microphone audio, transcribe a finished recording, and display
live transcription updates while the user speaks. It also demonstrates
integrated Silero voice activity detection (VAD) for filtering silence before
Whisper processes the audio. A separate local diarization page demonstrates
experimental TinyDiarize speaker-turn detection.

## What this example demonstrates

- Downloading and caching `ggml-tiny.en.bin`
- Restoring the cached model on later launches
- Requesting microphone permission
- Capturing mono PCM audio from the microphone
- Recording first and transcribing afterward
- Displaying transcription progress and handling cancellation
- Showing confirmed and provisional live transcript text
- Stopping a live session and flushing its final audio
- Enabling or disabling integrated Silero VAD for recorded and live audio
- Detecting two-speaker turns locally with a TinyDiarize-compatible model
- Cleaning up the recorder, transcription task, and engine
- Running a reproducible five-run performance and accuracy benchmark

All transcription runs locally after the models have been downloaded.

## Requirements

- Flutter 3.19 or later
- Android API 24 or later, or iOS 14 or later
- A physical Android or iOS device is recommended for microphone testing
- Network access for the first model download

The tiny English Whisper model is approximately 75 MB. The example also
downloads `ggml-silero-v6.2.0.bin` for voice activity detection. Both files are
cached in the application's managed model directory.

The optional diarization demo downloads `ggml-small.en-tdrz.bin`, which is
approximately 465 MB and is cached separately.

## Run the example

From the repository root:

```sh
cd example
flutter pub get
flutter run
```

On the first launch, select **Download required models**. The example downloads
only the Whisper or VAD model files that are not already cached. Once both
models are available, choose one of the two workflows:

1. **Record, then transcribe** captures a complete recording and transcribes it
   after recording stops.
2. **Transcribe live** displays local transcription updates as you speak and
   finalizes the remaining audio when stopped.

Grant microphone permission when prompted. Later launches reuse the downloaded
models unless the application's data is removed.

**Voice activity detection** is enabled by default for both workflows. Turn off
the switch before starting a recording or live transcription to compare the
same workflows without silence filtering. The switch is locked while a
recording or transcription is active.

## Try local diarization

Select **Diarization** in the app bar or **Try local diarization** on the main
page. Download the TinyDiarize model, then choose **Record a conversation** and
let two people take turns speaking English. The result displays each segment
as Voice A or Voice B with local timestamps.

TinyDiarize detects speaker-change boundaries rather than persistent speaker
identities. The example alternates Voice A and Voice B after each detected
turn, so it is intended for two-speaker recordings. Audio and inference remain
on the device after the model has been downloaded.

## Use your own model workflow

The plugin does not require Hugging Face or its built-in model manager. Your
application can use its own authenticated downloader, cache, asset delivery
system, or model registry and then load the resulting local path:

```dart
final modelPath = await downloadModelToAppStorage();
final engine = await WhisperEngine.load(modelPath);
```

The application owns the model file. Keep it readable until
`engine.dispose()` is called.

## Run the reproducible benchmark

Select **Benchmark** in the example app to run the canonical workload and view
or copy its JSON report. The report is also saved under the application's
managed model directory. The benchmark downloads `ggml-tiny.en.bin` if needed;
download and WAV decoding time are excluded.

Run the example on a physical device in release mode:

```sh
flutter run --release -d DEVICE_ID
```

Open **Benchmark**, wait for the Responsive, Balanced, and Efficient profiles
to complete three measured runs each, and choose **Copy results as JSON**. The
comparison table shows latency, real-time factor, drift, accuracy, and the
WAV size and duration alongside the effective decoding settings.
Use **Play benchmark WAV** to hear the bundled source and cross-check each
transcript; playback stops before and is excluded from measured time. Keep the
device, OS version, build mode, model/audio hashes, and pinned benchmark
configuration identical. Debug,
profile, simulator, and emulator results must not be compared with
physical-device release baselines. The benchmark does not measure battery or
memory usage.

## Adapting the example

The example is intentionally small enough to use as a starting point. Its
offline workflow includes a Responsive, Balanced, and Efficient mode selector;
live transcription keeps its streaming-specific timestamp behavior. Replace
the tiny English model with another compatible model, customize
`TranscribeOptions` and `WhisperStreamConfig`, or connect transcript updates to
your own state management and user interface.

For real-time use on mobile devices, begin with a smaller model and measure
performance on the oldest hardware your application supports.

## Need integration help or a custom AI solution?

Want help adding offline transcription to your app, building a custom product
on top of whisper.cpp, maintaining an existing Flutter plugin, or developing a
different AI-powered mobile or web solution? I can help with technical
planning, Flutter and native integration, model workflows, performance
optimization, debugging, upgrades, and long-term maintenance.

- [Discuss your project through Gurwinder DevX](https://gurwinderdevx.com/)
- [Hire me on Upwork](https://www.upwork.com/freelancers/gurwinderdevx)

## Author and support

Developed and maintained by **Gurwinder Singh**, a full-stack web and mobile
application developer and founder of
[Gurwinder DevX](https://gurwinderdevx.com/).

- [GitHub](https://github.com/47gurvinder)
- [LinkedIn](https://www.linkedin.com/in/gurwinderdevx/)
- [Upwork](https://www.upwork.com/freelancers/gurwinderdevx)
- [Buy Me a Coffee](https://buymeacoffee.com/gurwinderdevx)

If this example or plugin helps your project, consider supporting its continued
development through Buy Me a Coffee.

## Acknowledgements

This example uses the Flutter plugin built on the work of the
[whisper.cpp authors and contributors](https://github.com/ggml-org/whisper.cpp).
