import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'models.dart';

final class WhisperRecorder {
  static const _methods = MethodChannel('whisper_cpp_flutter/recorder');
  static const _audio = EventChannel('whisper_cpp_flutter/audio');
  Stream<RecordingChunk>? _stream;
  Future<bool> requestPermission() async => await _methods.invokeMethod<bool>('requestPermission') ?? false;
  Future<Stream<RecordingChunk>> start({int sampleRate=16000, int chunkMilliseconds=100}) async {
    await _methods.invokeMethod('start', {'sampleRate':sampleRate,'chunkMilliseconds':chunkMilliseconds});
    return _stream ??= _audio.receiveBroadcastStream().map((e) {
      final bytes=e as Uint8List;
      return RecordingChunk(Float32List.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes~/4),sampleRate);
    });
  }
  Future<void> stop() async { await _methods.invokeMethod('stop'); _stream=null; }
}
