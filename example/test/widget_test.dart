import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
// Benchmark report models are internal to repository tooling and the example.
// ignore: implementation_imports
import 'package:whisper_cpp_flutter_plus/src/benchmark_report.dart';
import 'package:whisper_cpp_flutter_plus_example/diarization_page.dart';
import 'package:whisper_cpp_flutter_plus_example/benchmark_page.dart';
import 'package:whisper_cpp_flutter_plus_example/main.dart';

void main() {
  testWidgets('shows the transcription workflow', (tester) async {
    await tester.pumpWidget(const WhisperExampleApp());

    expect(find.text('Offline speech to text'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.textContaining('complete recording'), findsOneWidget);
    expect(find.textContaining('live text'), findsOneWidget);
    expect(find.text('Voice activity detection'), findsOneWidget);
    expect(find.text('Try local diarization'), findsOneWidget);
    expect(find.text('Benchmark'), findsOneWidget);
    expect(find.textContaining('Filter silence'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('shows the fixed benchmark workload', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BenchmarkPage()),
    );

    expect(find.text('Performance benchmark'), findsOneWidget);
    expect(find.text('Canonical workload'), findsOneWidget);
    expect(find.textContaining('1 warm-up + 5 runs'), findsOneWidget);
    expect(find.text('Run benchmark'), findsOneWidget);
  });

  testWidgets('copies completed benchmark results as JSON', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? copiedJson;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedJson = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(home: BenchmarkPage(initialReport: _benchmarkReport())),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy results as JSON'));
    await tester.pump();

    final json = jsonDecode(copiedJson!) as Map<String, dynamic>;
    expect(json['schema_version'], 2);
    expect(json['iterations'], hasLength(5));
    expect(find.text('Benchmark JSON copied.'), findsOneWidget);
  });

  testWidgets('opens the local diarization page', (tester) async {
    await tester.pumpWidget(const WhisperExampleApp());

    await tester.tap(find.text('Try local diarization'));
    await tester.pumpAndSettle();

    expect(find.text('Local diarization'), findsOneWidget);
    expect(find.text('Who spoke when?'), findsOneWidget);
    expect(find.textContaining('two voices'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
  });

  test('builds transcription options for TinyDiarize', () {
    final options = buildDiarizationOptions();

    expect(options.language, 'en');
    expect(options.tokenTimestamps, isTrue);
    expect(options.tinyDiarize, isTrue);
  });

  test('builds transcription options with VAD enabled', () {
    final options = buildExampleTranscribeOptions(
      enableVad: true,
      vadModelPath: '/models/ggml-silero-v6.2.0.bin',
      tokenTimestamps: true,
    );

    expect(options.language, 'en');
    expect(options.tokenTimestamps, isTrue);
    expect(options.enableVad, isTrue);
    expect(options.vadModelPath, '/models/ggml-silero-v6.2.0.bin');
  });

  test('builds transcription options with VAD disabled', () {
    final options = buildExampleTranscribeOptions(
      enableVad: false,
      vadModelPath: '/models/ggml-silero-v6.2.0.bin',
    );

    expect(options, isA<TranscribeOptions>());
    expect(options.enableVad, isFalse);
    expect(options.vadModelPath, isNull);
  });
}

WhisperBenchmarkReport _benchmarkReport() {
  const iteration = BenchmarkIteration(
    index: 1,
    wallMicroseconds: 1000000,
    nativeMicroseconds: 800000,
    overheadMicroseconds: 200000,
    realTimeFactor: .1,
    transcript: 'hello world',
    normalizedTranscript: 'hello world',
    wordErrorRate: 0,
  );
  final iterations = List.generate(
    5,
    (index) => BenchmarkIteration(
      index: index + 1,
      wallMicroseconds: iteration.wallMicroseconds,
      nativeMicroseconds: iteration.nativeMicroseconds,
      overheadMicroseconds: iteration.overheadMicroseconds,
      realTimeFactor: iteration.realTimeFactor,
      transcript: iteration.transcript,
      normalizedTranscript: iteration.normalizedTranscript,
      wordErrorRate: iteration.wordErrorRate,
    ),
  );
  BenchmarkStatistics stats(num value) =>
      BenchmarkStatistics.calculate(List.filled(5, value));
  return WhisperBenchmarkReport(
    schemaVersion: 2,
    createdAtUtc: DateTime.utc(2026),
    environment: const {'build_mode': 'release'},
    model: const {'name': 'tiny.en', 'sha256': 'model'},
    audio: const {'name': 'jfk.wav', 'sha256': 'audio'},
    configuration: const {'threads': 4},
    modelLoadMicroseconds: 500000,
    warmup: iteration,
    iterations: iterations,
    statistics: {
      'wall_us': stats(iteration.wallMicroseconds),
      'native_us': stats(iteration.nativeMicroseconds),
      'overhead_us': stats(iteration.overheadMicroseconds),
      'real_time_factor': stats(iteration.realTimeFactor),
    },
    accuracy: const {
      'maximum_accepted_word_error_rate': .25,
      'maximum_observed_word_error_rate': 0,
      'transcripts_consistent': true,
    },
  );
}
