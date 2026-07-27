import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'models.dart';
import 'native_bindings.dart';

/// Runs whisper.cpp voice activity detection on mono 16 kHz PCM.
final class WhisperVad {
  WhisperVad._(this._context);
  final Pointer<Void> _context;

  /// Loads a VAD model from [modelPath].
  ///
  /// [threads] controls CPU concurrency and [useGpu] enables a supported GPU
  /// backend. The caller must eventually call [dispose].
  static WhisperVad load(String modelPath,
      {bool useGpu = true, int threads = 4}) {
    final n = NativeBindings.instance, p = modelPath.toNativeUtf8();
    try {
      final c = n.vadCreate(p, useGpu ? 1 : 0, threads);
      if (c == nullptr) throw WhisperException(n.lastError().toDartString());
      return WhisperVad._(c);
    } finally {
      malloc.free(p);
    }
  }

  /// Returns whether [pcm16k] contains speech.
  ///
  /// When [continuous] is true, native detector state is retained between
  /// calls until [reset] is invoked.
  bool isSpeech(Float32List pcm16k, {bool continuous = false}) {
    final p = malloc<Float>(pcm16k.length);
    p.asTypedList(pcm16k.length).setAll(0, pcm16k);
    try {
      return NativeBindings.instance
              .vadIsSpeech(_context, p, pcm16k.length, continuous ? 1 : 0) !=
          0;
    } finally {
      malloc.free(p);
    }
  }

  /// Finds speech intervals in [pcm16k].
  ///
  /// The input must contain mono 16 kHz floating-point PCM. Millisecond
  /// parameters control minimum speech, silence, and padding durations;
  /// [maxSpeechSeconds] limits individual intervals in seconds.
  List<VadSegment> segments(Float32List pcm16k,
      {double threshold = .5,
      int minSpeechMs = 250,
      int minSilenceMs = 100,
      double maxSpeechSeconds = double.maxFinite,
      int speechPadMs = 30,
      double samplesOverlap = .1}) {
    final n = NativeBindings.instance, p = malloc<Float>(pcm16k.length);
    p.asTypedList(pcm16k.length).setAll(0, pcm16k);
    try {
      final out = n.vadSegments(
          _context,
          p,
          pcm16k.length,
          threshold,
          minSpeechMs,
          minSilenceMs,
          maxSpeechSeconds,
          speechPadMs,
          samplesOverlap);
      if (out == nullptr) throw WhisperException(n.lastError().toDartString());
      try {
        return (jsonDecode(out.toDartString()) as List)
            .map((e) => VadSegment(
                Duration(milliseconds: ((e['t0'] as num) * 1000).round()),
                Duration(milliseconds: ((e['t1'] as num) * 1000).round())))
            .toList();
      } finally {
        n.stringFree(out);
      }
    } finally {
      malloc.free(p);
    }
  }

  /// Clears state accumulated by continuous speech detection.
  void reset() => NativeBindings.instance.vadReset(_context);

  /// Releases the native VAD context.
  ///
  /// The instance must not be used after disposal.
  void dispose() => NativeBindings.instance.vadFree(_context);
}
