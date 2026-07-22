import 'dart:convert';
import 'dart:math' as math;

String normalizeBenchmarkTranscript(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double benchmarkWordErrorRate(String expected, String actual) {
  final reference = normalizeBenchmarkTranscript(expected).split(' ');
  final hypothesis = normalizeBenchmarkTranscript(actual).split(' ');
  if (reference.length == 1 && reference.first.isEmpty) {
    return hypothesis.length == 1 && hypothesis.first.isEmpty ? 0 : 1;
  }
  final previous = List<int>.generate(hypothesis.length + 1, (i) => i);
  for (var i = 1; i <= reference.length; i++) {
    final current = List<int>.filled(hypothesis.length + 1, 0)..[0] = i;
    for (var j = 1; j <= hypothesis.length; j++) {
      current[j] = math.min(
        current[j - 1] + 1,
        math.min(
          previous[j] + 1,
          previous[j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1),
        ),
      );
    }
    previous.setAll(0, current);
  }
  return previous.last / reference.length;
}

final class BenchmarkStatistics {
  const BenchmarkStatistics({
    required this.minimum,
    required this.median,
    required this.mean,
    required this.p95,
    required this.maximum,
    required this.standardDeviation,
    required this.firstToLastDriftPercent,
  });

  final double minimum;
  final double median;
  final double mean;
  final double p95;
  final double maximum;
  final double standardDeviation;
  final double firstToLastDriftPercent;

  factory BenchmarkStatistics.calculate(List<num> input) {
    if (input.isEmpty) {
      throw ArgumentError.value(input, 'input', 'Cannot be empty');
    }
    final ordered = input.map((value) => value.toDouble()).toList()..sort();
    final mean = ordered.reduce((a, b) => a + b) / ordered.length;
    final variance = ordered
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        ordered.length;
    final middle = ordered.length ~/ 2;
    final median = ordered.length.isOdd
        ? ordered[middle]
        : (ordered[middle - 1] + ordered[middle]) / 2;
    final p95Index = (ordered.length * .95).ceil().clamp(1, ordered.length) - 1;
    final first = input.first.toDouble();
    final last = input.last.toDouble();
    return BenchmarkStatistics(
      minimum: ordered.first,
      median: median,
      mean: mean,
      p95: ordered[p95Index],
      maximum: ordered.last,
      standardDeviation: math.sqrt(variance),
      firstToLastDriftPercent: first == 0 ? 0 : (last - first) / first * 100,
    );
  }

  Map<String, dynamic> toJson() => {
        'min': minimum,
        'median': median,
        'mean': mean,
        'p95': p95,
        'max': maximum,
        'standard_deviation': standardDeviation,
        'first_to_last_drift_percent': firstToLastDriftPercent,
      };

  factory BenchmarkStatistics.fromJson(Map<String, dynamic> json) =>
      BenchmarkStatistics(
        minimum: (json['min'] as num).toDouble(),
        median: (json['median'] as num).toDouble(),
        mean: (json['mean'] as num).toDouble(),
        p95: (json['p95'] as num).toDouble(),
        maximum: (json['max'] as num).toDouble(),
        standardDeviation: (json['standard_deviation'] as num).toDouble(),
        firstToLastDriftPercent:
            (json['first_to_last_drift_percent'] as num).toDouble(),
      );
}

final class BenchmarkIteration {
  const BenchmarkIteration({
    required this.index,
    required this.wallMicroseconds,
    required this.nativeMicroseconds,
    required this.overheadMicroseconds,
    required this.realTimeFactor,
    required this.transcript,
    required this.normalizedTranscript,
    required this.wordErrorRate,
  });

  final int index;
  final int wallMicroseconds;
  final int nativeMicroseconds;
  final int overheadMicroseconds;
  final double realTimeFactor;
  final String transcript;
  final String normalizedTranscript;
  final double wordErrorRate;

  Map<String, dynamic> toJson() => {
        'index': index,
        'wall_us': wallMicroseconds,
        'native_us': nativeMicroseconds,
        'overhead_us': overheadMicroseconds,
        'real_time_factor': realTimeFactor,
        'transcript': transcript,
        'normalized_transcript': normalizedTranscript,
        'word_error_rate': wordErrorRate,
      };

  factory BenchmarkIteration.fromJson(Map<String, dynamic> json) =>
      BenchmarkIteration(
        index: json['index'] as int,
        wallMicroseconds: json['wall_us'] as int,
        nativeMicroseconds: json['native_us'] as int,
        overheadMicroseconds: json['overhead_us'] as int,
        realTimeFactor: (json['real_time_factor'] as num).toDouble(),
        transcript: json['transcript'] as String,
        normalizedTranscript: json['normalized_transcript'] as String,
        wordErrorRate: (json['word_error_rate'] as num).toDouble(),
      );
}

final class WhisperBenchmarkReport {
  const WhisperBenchmarkReport({
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.environment,
    required this.model,
    required this.audio,
    required this.configuration,
    required this.modelLoadMicroseconds,
    required this.warmup,
    required this.iterations,
    required this.statistics,
    required this.accuracy,
  });

  final int schemaVersion;
  final DateTime createdAtUtc;
  final Map<String, dynamic> environment;
  final Map<String, dynamic> model;
  final Map<String, dynamic> audio;
  final Map<String, dynamic> configuration;
  final int modelLoadMicroseconds;
  final BenchmarkIteration warmup;
  final List<BenchmarkIteration> iterations;
  final Map<String, BenchmarkStatistics> statistics;
  final Map<String, dynamic> accuracy;

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'created_at_utc': createdAtUtc.toUtc().toIso8601String(),
        'environment': environment,
        'model': model,
        'audio': audio,
        'configuration': configuration,
        'model_load_us': modelLoadMicroseconds,
        'warmup': warmup.toJson(),
        'iterations': iterations.map((value) => value.toJson()).toList(),
        'statistics':
            statistics.map((key, value) => MapEntry(key, value.toJson())),
        'accuracy': accuracy,
      };

  String encode({bool pretty = false}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());

  factory WhisperBenchmarkReport.fromJson(Map<String, dynamic> json) =>
      WhisperBenchmarkReport(
        schemaVersion: json['schema_version'] as int,
        createdAtUtc: DateTime.parse(json['created_at_utc'] as String).toUtc(),
        environment: (json['environment'] as Map).cast<String, dynamic>(),
        model: (json['model'] as Map).cast<String, dynamic>(),
        audio: (json['audio'] as Map).cast<String, dynamic>(),
        configuration: (json['configuration'] as Map).cast<String, dynamic>(),
        modelLoadMicroseconds: json['model_load_us'] as int,
        warmup: BenchmarkIteration.fromJson(
          (json['warmup'] as Map).cast<String, dynamic>(),
        ),
        iterations: (json['iterations'] as List)
            .map((value) => BenchmarkIteration.fromJson(
                  (value as Map).cast<String, dynamic>(),
                ))
            .toList(growable: false),
        statistics: (json['statistics'] as Map).map(
          (key, value) => MapEntry(
            key as String,
            BenchmarkStatistics.fromJson(
                (value as Map).cast<String, dynamic>()),
          ),
        ),
        accuracy: (json['accuracy'] as Map).cast<String, dynamic>(),
      );

  factory WhisperBenchmarkReport.decode(String source) =>
      WhisperBenchmarkReport.fromJson(
        (jsonDecode(source) as Map).cast<String, dynamic>(),
      );

  void validate({required int expectedIterations}) {
    if (schemaVersion != 2) {
      throw StateError('Unsupported benchmark schema $schemaVersion');
    }
    if (iterations.length != expectedIterations) {
      throw StateError(
        'Expected $expectedIterations measured iterations, '
        'found ${iterations.length}',
      );
    }
    final transcript = iterations.first.normalizedTranscript;
    final maximumAccepted =
        (accuracy['maximum_accepted_word_error_rate'] as num).toDouble();
    for (final iteration in iterations) {
      if (iteration.wallMicroseconds <= 0 ||
          iteration.nativeMicroseconds <= 0 ||
          !iteration.realTimeFactor.isFinite ||
          !iteration.wordErrorRate.isFinite ||
          iteration.normalizedTranscript != transcript ||
          iteration.wordErrorRate > maximumAccepted) {
        throw StateError('Benchmark contains invalid or inconsistent results');
      }
    }
  }
}
