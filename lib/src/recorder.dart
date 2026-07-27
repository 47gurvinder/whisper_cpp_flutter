import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'models.dart';

/// Captures mono floating-point PCM from the device microphone.
final class WhisperRecorder {
  /// Creates an idle microphone recorder.
  WhisperRecorder();

  static const _methods = MethodChannel('whisper_cpp_flutter/recorder');
  static const _audio = EventChannel('whisper_cpp_flutter/audio');
  static WhisperRecorder? _activeRecorder;

  StreamController<RecordingChunk>? _controller;
  StreamSubscription<dynamic>? _nativeSubscription;
  bool _stopping = false;

  /// Requests microphone access from the current platform.
  ///
  /// Returns whether access is available after the platform prompt completes.
  Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  /// Starts recording mono floating-point PCM.
  ///
  /// [sampleRate] is measured in hertz and [chunkMilliseconds] controls the
  /// requested native delivery interval. Only one recorder may be active at a
  /// time. Call [stop] when the returned stream is no longer needed.
  Future<Stream<RecordingChunk>> start({
    int sampleRate = 16000,
    int chunkMilliseconds = 100,
  }) async {
    if (sampleRate <= 0) {
      throw ArgumentError.value(
          sampleRate, 'sampleRate', 'Must be greater than zero');
    }
    if (chunkMilliseconds <= 0) {
      throw ArgumentError.value(
          chunkMilliseconds, 'chunkMilliseconds', 'Must be greater than zero');
    }
    if (_controller != null) {
      throw StateError('This recorder is already running');
    }
    if (_activeRecorder != null) {
      throw StateError('Another microphone recording is already active');
    }

    _activeRecorder = this;
    // A single-subscription controller buffers the first native chunks until
    // the caller attaches its listener after start() completes.
    final controller = StreamController<RecordingChunk>();
    _controller = controller;
    _nativeSubscription = _audio.receiveBroadcastStream().listen(
      (dynamic event) {
        try {
          controller.add(_decodeChunk(event, sampleRate));
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          unawaited(stop());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        controller.addError(error, stackTrace);
        unawaited(stop());
      },
    );

    try {
      await _methods.invokeMethod('start', {
        'sampleRate': sampleRate,
        'chunkMilliseconds': chunkMilliseconds,
      });
      return controller.stream;
    } catch (_) {
      try {
        await _methods.invokeMethod('stop');
      } catch (_) {
        // Preserve the original start failure.
      }
      await _cleanup();
      rethrow;
    }
  }

  /// Stops recording and closes the stream returned by [start].
  ///
  /// Calling this on an idle or already stopped recorder is safe.
  Future<void> stop() async {
    if (_controller == null || _stopping) return;
    _stopping = true;
    Object? stopError;
    StackTrace? stopStackTrace;
    try {
      await _methods.invokeMethod('stop');
    } catch (error, stackTrace) {
      stopError = error;
      stopStackTrace = stackTrace;
    } finally {
      await _cleanup();
      _stopping = false;
    }
    if (stopError != null) {
      Error.throwWithStackTrace(stopError, stopStackTrace!);
    }
  }

  Future<void> _cleanup() async {
    final subscription = _nativeSubscription;
    final controller = _controller;
    _nativeSubscription = null;
    _controller = null;
    if (identical(_activeRecorder, this)) _activeRecorder = null;
    await subscription?.cancel();
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }

  static RecordingChunk _decodeChunk(dynamic event, int sampleRate) {
    if (event is! Uint8List) {
      throw const FormatException('Recorder returned non-byte PCM data');
    }
    if (event.lengthInBytes % Float32List.bytesPerElement != 0) {
      throw const FormatException('PCM byte length must be a multiple of 4');
    }
    final pcmBytes = event.offsetInBytes % Float32List.bytesPerElement == 0
        ? event
        : Uint8List.fromList(event);
    return RecordingChunk(
      Float32List.view(
        pcmBytes.buffer,
        pcmBytes.offsetInBytes,
        pcmBytes.lengthInBytes ~/ Float32List.bytesPerElement,
      ),
      sampleRate,
    );
  }
}
