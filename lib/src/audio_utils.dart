import 'dart:io';
import 'dart:typed_data';

/// Utilities for preparing audio for whisper.cpp.
final class WhisperAudio {
  /// This class exposes static utilities and cannot be instantiated.
  /// Creates an audio utility instance.
  WhisperAudio();

  /// Reads and decodes a WAV [file] as mono 16 kHz floating-point PCM.
  static Future<Float32List> readWav(File file) async =>
      decodeWav(await file.readAsBytes());

  /// Decodes WAV [bytes] as mono 16 kHz floating-point PCM.
  ///
  /// Integer PCM with 16, 24, or 32 bits and 32-bit IEEE float PCM are
  /// supported. Multiple channels are averaged and other sample rates are
  /// resampled. Invalid or unsupported input throws a [FormatException].
  static Float32List decodeWav(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    if (bytes.length < 44 ||
        _four(bytes, 0) != 'RIFF' ||
        _four(bytes, 8) != 'WAVE') {
      throw const FormatException('Invalid WAV file');
    }
    var p = 12,
        format = 0,
        channels = 0,
        rate = 0,
        bits = 0,
        dataStart = -1,
        dataSize = 0;
    while (p + 8 <= bytes.length) {
      final id = _four(bytes, p),
          size = d.getUint32(p + 4, Endian.little),
          start = p + 8;
      if (id == 'fmt ') {
        format = d.getUint16(start, Endian.little);
        channels = d.getUint16(start + 2, Endian.little);
        rate = d.getUint32(start + 4, Endian.little);
        bits = d.getUint16(start + 14, Endian.little);
      } else if (id == 'data') {
        dataStart = start;
        dataSize = size;
        break;
      }
      p = start + size + (size & 1);
    }
    if (dataStart < 0 || channels < 1 || (format != 1 && format != 3)) {
      throw const FormatException('Only PCM/float WAV is supported');
    }
    final frames = dataSize ~/ (channels * (bits ~/ 8)),
        mono = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      double sum = 0;
      for (var c = 0; c < channels; c++) {
        final off = dataStart + (i * channels + c) * (bits ~/ 8);
        sum += format == 3 && bits == 32
            ? d.getFloat32(off, Endian.little)
            : bits == 16
                ? d.getInt16(off, Endian.little) / 32768.0
                : bits == 24
                    ? _i24(d, off) / 8388608.0
                    : bits == 32
                        ? d.getInt32(off, Endian.little) / 2147483648.0
                        : throw const FormatException(
                            'Unsupported WAV bit depth');
      }
      mono[i] = sum / channels;
    }
    return rate == 16000 ? mono : resample(mono, rate, 16000);
  }

  /// Linearly resamples [input] from [from] hertz to [to] hertz.
  ///
  /// The input is returned unchanged when both rates are equal.
  static Float32List resample(Float32List input, int from, int to) {
    if (from == to) return input;
    final out = Float32List((input.length * to / from).round());
    for (var i = 0; i < out.length; i++) {
      final x = i * from / to, j = x.floor(), f = x - j;
      out[i] = j + 1 < input.length
          ? input[j] * (1 - f) + input[j + 1] * f
          : input.last;
    }
    return out;
  }

  static String _four(Uint8List b, int p) =>
      String.fromCharCodes(b.sublist(p, p + 4));
  static int _i24(ByteData d, int p) {
    var v =
        d.getUint8(p) | (d.getUint8(p + 1) << 8) | (d.getUint8(p + 2) << 16);
    return (v & 0x800000) != 0 ? v | ~0xffffff : v;
  }
}
