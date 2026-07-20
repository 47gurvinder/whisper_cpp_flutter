# whisper_cpp_flutter example

This app downloads the `ggml-tiny.en.bin` model and demonstrates two local
workflows with `whisper_cpp_flutter`: transcribing a complete recording, and
continuous recorder-style transcription while speaking.

Run it on a physical Android or iOS device:

```sh
flutter pub get
flutter run
```

The first run needs network access to download the model (about 75 MB). After
that, transcription runs offline. Grant microphone permission when prompted.

The package does not require this download workflow or a Hugging Face model
source. An application can use its own downloader, keep the model in its cache
or support directory, and load that local path directly without copying it:

```dart
final cacheModelPath = await downloadModelToAppCache();
final engine = await WhisperEngine.load(cacheModelPath);
```

The application owns the file and must keep it available until
`engine.dispose()` is called.
