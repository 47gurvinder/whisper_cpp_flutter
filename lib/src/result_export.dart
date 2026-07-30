import 'dart:convert';

import 'models.dart';

/// Text and subtitle exports for a completed transcription.
extension WhisperResultExport on WhisperResult {
  /// Returns the transcript without altering whitespace or punctuation.
  String toPlainText() => text;

  /// Encodes this result as JSON using the native bridge schema.
  ///
  /// Set [includeTokens] to false to omit detailed token metadata.
  String toJsonString({bool includeTokens = true}) =>
      jsonEncode(toJson(includeTokens: includeTokens));

  /// Encodes timestamped segments as SubRip subtitles.
  String toSrt() {
    if (segments.isEmpty) return '';
    final buffer = StringBuffer();
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final times = _normalizedTimes(segment);
      if (index > 0) buffer.write('\n\n');
      buffer.writeln(index + 1);
      buffer.writeln(
        '${_formatTimestamp(times.$1, ',')} --> '
        '${_formatTimestamp(times.$2, ',')}',
      );
      buffer.write(segment.text.trim());
    }
    return buffer.toString();
  }

  /// Encodes timestamped segments as WebVTT subtitles.
  String toVtt() {
    if (segments.isEmpty) return 'WEBVTT\n';
    final buffer = StringBuffer('WEBVTT\n\n');
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final times = _normalizedTimes(segment);
      if (index > 0) buffer.write('\n\n');
      buffer.writeln(
        '${_formatTimestamp(times.$1, '.')} --> '
        '${_formatTimestamp(times.$2, '.')}',
      );
      buffer.write(segment.text.trim());
    }
    return buffer.toString();
  }
}

(Duration, Duration) _normalizedTimes(WhisperSegment segment) {
  final start = segment.start < Duration.zero ? Duration.zero : segment.start;
  final end = segment.end < start ? start : segment.end;
  return (start, end);
}

String _formatTimestamp(Duration value, String millisecondSeparator) {
  final milliseconds = value.inMilliseconds;
  final hours = milliseconds ~/ Duration.millisecondsPerHour;
  final minutes = milliseconds.remainder(Duration.millisecondsPerHour) ~/
      Duration.millisecondsPerMinute;
  final seconds = milliseconds.remainder(Duration.millisecondsPerMinute) ~/
      Duration.millisecondsPerSecond;
  final millis = milliseconds.remainder(Duration.millisecondsPerSecond);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}'
      '$millisecondSeparator${millis.toString().padLeft(3, '0')}';
}
