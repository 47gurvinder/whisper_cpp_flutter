# whisper_cpp_flutter example

This app downloads the `ggml-tiny.en.bin` model, records microphone audio,
and transcribes it locally with `whisper_cpp_flutter`.

Run it on a physical Android or iOS device:

```sh
flutter pub get
flutter run
```

The first run needs network access to download the model (about 75 MB). After
that, transcription runs offline. Grant microphone permission when prompted.
