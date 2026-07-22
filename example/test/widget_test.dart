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
import 'package:whisper_cpp_flutter_plus_example/benchmark/benchmark_runner.dart';
import 'package:whisper_cpp_flutter_plus_example/main.dart';

void main() {
  testWidgets('shows the transcription workflow', (tester) async {
    await tester.pumpWidget(const WhisperExampleApp());

    expect(find.text('Offline speech to text'), findsOneWidget);
    expect(find.textContaining('complete recording'), findsOneWidget);
    expect(find.textContaining('live text'), findsWidgets);
    expect(find.text('Voice activity detection'), findsOneWidget);
    expect(find.text('Offline performance mode'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<WhisperPerformanceMode>>(
            find.byType(DropdownButtonFormField<WhisperPerformanceMode>),
          )
          .initialValue,
      WhisperPerformanceMode.balanced,
    );
    expect(find.text('Try local diarization'), findsOneWidget);
    expect(find.text('Benchmark'), findsOneWidget);
    expect(find.textContaining('Filter silence'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.scrollUntilVisible(
      find.text('Transcript'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Transcript'), findsOneWidget);
  });

  testWidgets('shows the fixed benchmark workload', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BenchmarkPage()),
    );

    expect(find.text('Performance benchmark'), findsOneWidget);
    expect(find.text('Canonical workload'), findsOneWidget);
    expect(find.textContaining('1 warm-up + 3 runs per mode'), findsOneWidget);
    expect(find.text('Play benchmark WAV'), findsOneWidget);
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
    expect(json['schema_version'], 3);
    expect(json['modes'], hasLength(3));
    for (final mode in json['modes'] as List) {
      expect((mode as Map)['iterations'], hasLength(3));
    }
    expect(find.text('Responsive'), findsWidgets);
    expect(find.text('Balanced'), findsWidgets);
    expect(find.text('Efficient'), findsWidgets);
    expect(find.text('WAV duration'), findsOneWidget);
    expect(find.text('11.000s'), findsOneWidget);
    expect(find.text('WAV size'), findsOneWidget);
    expect(find.text('343.8 KiB'), findsOneWidget);
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

  test('applies a performance mode only when explicitly requested', () {
    final offline = buildExampleTranscribeOptions(
      enableVad: false,
      vadModelPath: null,
      performanceMode: WhisperPerformanceMode.responsive,
    );
    final streaming = buildExampleTranscribeOptions(
      enableVad: false,
      vadModelPath: null,
    );

    expect(offline.greedyBestOf, 1);
    expect(offline.noTimestamps, isTrue);
    expect(streaming.greedyBestOf, 5);
    expect(streaming.noTimestamps, isFalse);
  });

  test('rotates benchmark modes through every measured position', () {
    expect(benchmarkExecutionOrder, hasLength(3));
    for (final mode in WhisperPerformanceMode.values) {
      expect(
        List.generate(
          benchmarkExecutionOrder.length,
          (round) => benchmarkExecutionOrder[round].indexOf(mode),
        ).toSet(),
        {0, 1, 2},
      );
    }
  });

  test('serializes every resolved benchmark option for each mode', () {
    const runner = WhisperBenchmarkRunner();
    const expectedTranscriptionKeys = {
      'strategy',
      'threads',
      'language',
      'translate',
      'detect_language',
      'offset_ms',
      'duration_ms',
      'max_text_context',
      'max_segment_length',
      'max_tokens_per_segment',
      'audio_context',
      'token_timestamps',
      'split_on_word',
      'suppress_blank',
      'suppress_non_speech_tokens',
      'single_segment',
      'no_context',
      'no_timestamps',
      'print_special_tokens',
      'tiny_diarize',
      'debug_mode',
      'carry_initial_prompt',
      'initial_prompt',
      'suppress_regex',
      'temperature',
      'timestamp_token_threshold',
      'timestamp_token_sum_threshold',
      'max_initial_timestamp',
      'length_penalty',
      'temperature_increment',
      'entropy_threshold',
      'log_probability_threshold',
      'no_speech_threshold',
      'greedy_best_of',
      'beam_size',
      'beam_patience',
      'enable_vad',
      'vad_model_path',
      'vad_threshold',
      'vad_min_speech_ms',
      'vad_min_silence_ms',
      'vad_max_speech_seconds',
      'vad_speech_pad_ms',
      'vad_samples_overlap',
    };

    for (final mode in WhisperPerformanceMode.values) {
      final configuration = runner.configurationForMode(
        mode,
        WhisperBenchmarkRunner.baseTranscriptionOptions
            .withPerformanceMode(mode),
      );
      expect(configuration['mode'], mode.name);
      expect(
        (configuration['model'] as Map).keys.toSet(),
        {'use_gpu', 'use_flash_attention', 'use_dtw', 'dtw_model'},
      );
      expect(
        (configuration['transcription'] as Map).keys.toSet(),
        expectedTranscriptionKeys,
      );
    }
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
    3,
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
      BenchmarkStatistics.calculate(List.filled(3, value));
  BenchmarkModeReport mode(
          String name, int threads, int bestOf, bool noTimestamps) =>
      BenchmarkModeReport(
        mode: name,
        configuration: {
          'mode': name,
          'model': const {
            'use_gpu': true,
            'use_flash_attention': true,
            'use_dtw': false,
            'dtw_model': 0,
          },
          'transcription': {
            'threads': threads,
            'greedy_best_of': bestOf,
            'no_timestamps': noTimestamps,
            'token_timestamps': !noTimestamps,
          },
        },
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
  return WhisperBenchmarkReport(
    schemaVersion: 3,
    createdAtUtc: DateTime.utc(2026),
    environment: const {'build_mode': 'release'},
    model: const {'name': 'tiny.en', 'sha256': 'model'},
    audio: const {
      'name': 'jfk.wav',
      'sha256': 'audio',
      'bytes': 352044,
      'duration_us': 11000000,
    },
    benchmarkConfiguration: const {
      'warmup_runs_per_mode': 1,
      'measured_runs_per_mode': 3,
    },
    modelLoadMicroseconds: 500000,
    modes: [
      mode('responsive', 4, 1, true),
      mode('balanced', 4, 5, false),
      mode('efficient', 2, 1, true),
    ],
  );
}
