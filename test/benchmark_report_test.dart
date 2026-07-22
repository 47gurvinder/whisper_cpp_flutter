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

  test('round trips schema 2 JSON', () {
    final original = _report();
    final decoded = WhisperBenchmarkReport.decode(original.encode());
    expect(decoded.toJson(), original.toJson());
    expect(decoded.schemaVersion, 2);
  });

  test('validates five consistent measured runs', () {
    expect(
      () => _report().validate(expectedIterations: 5),
      returnsNormally,
    );
    expect(
      () => _report(iterationCount: 4).validate(expectedIterations: 5),
      throwsStateError,
    );
    expect(
      () => _report(wordErrorRate: .5).validate(expectedIterations: 5),
      throwsStateError,
    );
  });
}

WhisperBenchmarkReport _report({
  double multiplier = 1,
  String modelHash = 'model',
  String audioHash = 'audio',
  Map<String, dynamic> configuration = const {'threads': 4},
  String deviceIdentity = 'device',
  int iterationCount = 5,
  double wordErrorRate = 0,
}) {
  BenchmarkIteration iteration(int index) => BenchmarkIteration(
        index: index,
        wallMicroseconds: (1000000 * multiplier).round(),
        nativeMicroseconds: (800000 * multiplier).round(),
        overheadMicroseconds: (200000 * multiplier).round(),
        realTimeFactor: .1 * multiplier,
        transcript: 'hello world',
        normalizedTranscript: 'hello world',
        wordErrorRate: wordErrorRate,
      );
  final iterations =
      List.generate(iterationCount, (index) => iteration(index + 1));
  BenchmarkStatistics stats(Iterable<num> values) =>
      BenchmarkStatistics.calculate(values.toList());
  return WhisperBenchmarkReport(
    schemaVersion: 2,
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
    configuration: configuration,
    modelLoadMicroseconds: (500000 * multiplier).round(),
    warmup: iteration(0),
    iterations: iterations,
    statistics: {
      'wall_us': stats(iterations.map((value) => value.wallMicroseconds)),
      'native_us': stats(iterations.map((value) => value.nativeMicroseconds)),
      'overhead_us':
          stats(iterations.map((value) => value.overheadMicroseconds)),
      'real_time_factor':
          stats(iterations.map((value) => value.realTimeFactor)),
    },
    accuracy: {
      'maximum_accepted_word_error_rate': .25,
      'maximum_observed_word_error_rate': wordErrorRate,
      'transcripts_consistent': true,
    },
  );
}
