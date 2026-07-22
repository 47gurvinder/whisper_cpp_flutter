import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/src/benchmark_report.dart';

void main() {
  group('benchmark transcript helpers', () {
    test('normalizes punctuation, case, and whitespace', () {
      expect(
        normalizeBenchmarkTranscript('  Ask NOT,  what! '),
        'ask not what',
      );
    });

    test('calculates word error rate', () {
      expect(benchmarkWordErrorRate('one two three', 'one two three'), 0);
      expect(benchmarkWordErrorRate('one two three', 'one four three'), 1 / 3);
      expect(benchmarkWordErrorRate('one two three', 'one three'), 1 / 3);
    });
  });

  test('calculates stable aggregate statistics', () {
    final stats = BenchmarkStatistics.calculate([1, 2, 3, 4, 5]);
    expect(stats.minimum, 1);
    expect(stats.median, 3);
    expect(stats.mean, 3);
    expect(stats.p95, 5);
    expect(stats.maximum, 5);
    expect(stats.standardDeviation, closeTo(1.414213, .000001));
    expect(stats.firstToLastDriftPercent, 400);
  });

  test('round trips schema 3 JSON with complete mode configuration', () {
    final original = _report();
    final decoded = WhisperBenchmarkReport.decode(original.encode());
    expect(decoded.toJson(), original.toJson());
    expect(decoded.schemaVersion, 3);
    expect(decoded.toJson(), containsPair('benchmark_configuration', isMap));
    expect(decoded.toJson(), containsPair('modes', hasLength(3)));
    expect(
      decoded.modes.first.configuration,
      {
        'whisper_config': {'use_gpu': true, 'flash_attn': false},
        'transcribe_options': {
          'threads': 4,
          'best_of': 1,
          'token_timestamps': false,
          'timestamps': false,
          'language': 'en',
        },
      },
    );
  });

  test('validates three modes with three consistent measured runs', () {
    expect(() => _report().validate(), returnsNormally);
    expect(
      () => _report(iterationCount: 2).validate(),
      throwsStateError,
    );
    expect(
      () => _report(wordErrorRate: .5).validate(),
      throwsStateError,
    );
  });

  test('rejects wrong schema and missing, duplicate, or unexpected modes', () {
    expect(() => _report(schemaVersion: 2).validate(), throwsStateError);
    expect(
      () => _report(modeNames: const ['responsive', 'balanced']).validate(),
      throwsStateError,
    );
    expect(
      () => _report(
        modeNames: const ['responsive', 'responsive', 'efficient'],
      ).validate(),
      throwsStateError,
    );
    expect(
      () => _report(
        modeNames: const ['responsive', 'balanced', 'turbo'],
      ).validate(),
      throwsStateError,
    );
  });

  test('rejects non-finite metrics and inconsistent transcripts per mode', () {
    expect(
      () => _report(realTimeFactor: double.nan).validate(),
      throwsStateError,
    );
    expect(
      () => _report(statisticMean: double.infinity).validate(),
      throwsStateError,
    );
    expect(
      () => _report(inconsistentMode: 'balanced').validate(),
      throwsStateError,
    );
  });

  test('allows transcripts to differ between modes', () {
    expect(() => _report(differentModeTranscripts: true).validate(),
        returnsNormally);
  });
}

WhisperBenchmarkReport _report({
  int schemaVersion = 3,
  double multiplier = 1,
  String modelHash = 'model',
  String audioHash = 'audio',
  String deviceIdentity = 'device',
  int iterationCount = 3,
  double wordErrorRate = 0,
  double realTimeFactor = .1,
  double? statisticMean,
  String? inconsistentMode,
  bool differentModeTranscripts = false,
  List<String> modeNames = const ['responsive', 'balanced', 'efficient'],
}) {
  BenchmarkIteration iteration(int index, String transcript) =>
      BenchmarkIteration(
        index: index,
        wallMicroseconds: (1000000 * multiplier).round(),
        nativeMicroseconds: (800000 * multiplier).round(),
        overheadMicroseconds: (200000 * multiplier).round(),
        realTimeFactor: realTimeFactor * multiplier,
        transcript: transcript,
        normalizedTranscript: transcript,
        wordErrorRate: wordErrorRate,
      );
  BenchmarkStatistics stats(Iterable<num> values) =>
      BenchmarkStatistics.calculate(values.toList());
  BenchmarkModeReport mode(String name) {
    final transcript = differentModeTranscripts ? 'mode $name' : 'hello world';
    final iterations = List.generate(
      iterationCount,
      (index) => iteration(
        index + 1,
        inconsistentMode == name && index == iterationCount - 1
            ? 'different words'
            : transcript,
      ),
    );
    final wallStats = stats(
      iterations.map((value) => value.wallMicroseconds),
    );
    return BenchmarkModeReport(
      mode: name,
      configuration: {
        'whisper_config': {'use_gpu': true, 'flash_attn': false},
        'transcribe_options': {
          'threads': name == 'efficient' ? 2 : 4,
          'best_of': name == 'balanced' ? 5 : 1,
          'token_timestamps': name == 'balanced',
          'timestamps': name == 'balanced',
          'language': 'en',
        },
      },
      warmup: iteration(0, transcript),
      iterations: iterations,
      statistics: {
        'wall_us': statisticMean == null
            ? wallStats
            : BenchmarkStatistics(
                minimum: wallStats.minimum,
                median: wallStats.median,
                mean: statisticMean,
                p95: wallStats.p95,
                maximum: wallStats.maximum,
                standardDeviation: wallStats.standardDeviation,
                firstToLastDriftPercent: wallStats.firstToLastDriftPercent,
              ),
        'native_us': stats(
          iterations.map((value) => value.nativeMicroseconds),
        ),
        'overhead_us': stats(
          iterations.map((value) => value.overheadMicroseconds),
        ),
        'real_time_factor': stats(
          iterations.map((value) => value.realTimeFactor),
        ),
      },
      accuracy: {
        'maximum_accepted_word_error_rate': .25,
        'maximum_observed_word_error_rate': wordErrorRate,
        'transcripts_consistent': inconsistentMode != name,
      },
    );
  }

  return WhisperBenchmarkReport(
    schemaVersion: schemaVersion,
    createdAtUtc: DateTime.utc(2026),
    environment: {
      'operating_system': 'android',
      'operating_system_version': '1',
      'number_of_processors': 8,
      'build_mode': 'release',
      'device': {
        'identity': deviceIdentity,
        'architecture': 'arm64-v8a',
      },
    },
    model: {'name': 'tiny', 'sha256': modelHash},
    audio: {'name': 'jfk', 'sha256': audioHash},
    benchmarkConfiguration: {
      'warmup_count_per_mode': 1,
      'measured_count_per_mode': iterationCount,
      'execution_order': const [
        ['responsive', 'balanced', 'efficient'],
        ['balanced', 'efficient', 'responsive'],
        ['efficient', 'responsive', 'balanced'],
      ],
    },
    modelLoadMicroseconds: (500000 * multiplier).round(),
    modes: [
      for (final name in modeNames) mode(name),
    ],
  );
}
