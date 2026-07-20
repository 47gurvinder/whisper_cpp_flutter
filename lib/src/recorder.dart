import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'models.dart';

final class WhisperRecorder {
  static const _methods = MethodChannel('whisper_cpp_flutter/recorder');
  static const _audio = EventChannel('whisper_cpp_flutter/audio');
  Stream<RecordingChunk>? _stream;
  Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;
  Future<Stream<RecordingChunk>> start(
      {int sampleRate = 16000, int chunkMilliseconds = 100}) async {
    await _methods.invokeMethod('start',
        {'sampleRate': sampleRate, 'chunkMilliseconds': chunkMilliseconds});
    return _stream ??= _audio.receiveBroadcastStream().map((e) {
      final bytes = e as Uint8List;
      if (bytes.lengthInBytes % Float32List.bytesPerElement != 0) {
        throw const FormatException('PCM byte length must be a multiple of 4');
      }
      final pcmBytes = bytes.offsetInBytes % Float32List.bytesPerElement == 0
          ? bytes
          : Uint8List.fromList(bytes);
      return RecordingChunk(
          Float32List.view(pcmBytes.buffer, pcmBytes.offsetInBytes,
              pcmBytes.lengthInBytes ~/ 4),
          sampleRate);
    });
  }

  Future<void> stop() async {
    await _methods.invokeMethod('stop');
    _stream = null;
  }
}
