import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

void main() {
  test('JSON export round trips the native result schema', () {
    final original = _result([
      _segment(
        ' hello',
        const Duration(milliseconds: 125),
        const Duration(milliseconds: 950),
        tokens: [_token()],
      ),
    ]);

    final decoded = WhisperResult.fromJson(
      jsonDecode(original.toJsonString()) as Map<String, dynamic>,
    );

    expect(decoded.toJson(), original.toJson());
    expect(original.toPlainText(), ' hello');
  });

  test('JSON export can omit token metadata', () {
    final encoded = jsonDecode(
      _result([
        _segment(
          'hello',
          Duration.zero,
          const Duration(seconds: 1),
          tokens: [_token()],
        ),
      ]).toJsonString(includeTokens: false),
    ) as Map<String, dynamic>;

    final segment =
        (encoded['segments'] as List).single as Map<String, dynamic>;
    expect(segment, isNot(contains('tokens')));
  });

  test('exports standard SRT and VTT timestamps with multiline text', () {
    final result = _result([
      _segment(
        ' first\nline',
        const Duration(milliseconds: 125),
        const Duration(milliseconds: 950),
      ),
      _segment(
        ' second',
        const Duration(hours: 27, minutes: 2, seconds: 3, milliseconds: 4),
        const Duration(hours: 27, minutes: 2, seconds: 5, milliseconds: 6),
      ),
    ]);

    expect(
      result.toSrt(),
      '1\n'
      '00:00:00,125 --> 00:00:00,950\n'
      'first\nline\n\n'
      '2\n'
      '27:02:03,004 --> 27:02:05,006\n'
      'second',
    );
    expect(
      result.toVtt(),
      'WEBVTT\n\n'
      '00:00:00.125 --> 00:00:00.950\n'
      'first\nline\n\n'
      '27:02:03.004 --> 27:02:05.006\n'
      'second',
    );
  });

  test('normalizes negative and reversed subtitle timestamps', () {
    final result = _result([
      _segment(
        'negative',
        const Duration(milliseconds: -20),
        const Duration(milliseconds: -10),
      ),
      _segment(
        'reversed',
        const Duration(seconds: 2),
        const Duration(seconds: 1),
      ),
    ]);

    expect(result.toSrt(), contains('00:00:00,000 --> 00:00:00,000'));
    expect(result.toSrt(), contains('00:00:02,000 --> 00:00:02,000'));
  });

  test('empty results produce empty SRT and header-only VTT', () {
    final result = _result(const []);
    expect(result.toSrt(), isEmpty);
    expect(result.toVtt(), 'WEBVTT\n');
  });
}

WhisperResult _result(List<WhisperSegment> segments) => WhisperResult(
      text: segments.map((segment) => segment.text).join(),
      language: 'en',
      languageProbability: .9,
      segments: segments,
      processingTime: const Duration(milliseconds: 12),
      systemInfo: 'test',
    );

WhisperSegment _segment(
  String text,
  Duration start,
  Duration end, {
  List<WhisperToken> tokens = const [],
}) =>
    WhisperSegment(
      text: text,
      start: start,
      end: end,
      tokens: tokens,
      noSpeechProbability: .1,
      speakerTurnNext: false,
    );

WhisperToken _token() => const WhisperToken(
      id: 42,
      text: ' hello',
      start: Duration(milliseconds: 125),
      end: Duration(milliseconds: 950),
      probability: .8,
      logProbability: -.2,
      timestampProbability: .7,
      timestampProbabilitySum: .9,
      dtwTimestamp: Duration(milliseconds: 500),
      voiceLength: .5,
    );
