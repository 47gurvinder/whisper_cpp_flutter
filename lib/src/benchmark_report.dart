import 'dart:convert';
import 'dart:math' as math;

/// Normalizes [value] for case-insensitive benchmark transcript comparison.
String normalizeBenchmarkTranscript(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Computes word error rate between [expected] and [actual].
///
/// The result is the Levenshtein word-edit distance divided by the expected
/// word count.
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

/// Distribution and drift statistics for one benchmark metric.
final class BenchmarkStatistics {
  /// Creates a set of precomputed statistics.
  const BenchmarkStatistics({
    required this.minimum,
    required this.median,
    required this.mean,
    required this.p95,
    required this.maximum,
    required this.standardDeviation,
    required this.firstToLastDriftPercent,
  });

  /// Smallest observed value.
  final double minimum;

  /// Median observed value.
  final double median;

  /// Arithmetic mean of all values.
  final double mean;

  /// Nearest-rank 95th percentile.
  final double p95;

  /// Largest observed value.
  final double maximum;

  /// Population standard deviation.
  final double standardDeviation;

  /// Percentage change from the first input value to the last.
  final double firstToLastDriftPercent;

  /// Calculates statistics for non-empty [input].
  ///
  /// Throws [ArgumentError] when [input] is empty.
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

  /// Converts this value to the benchmark report JSON schema.
  Map<String, dynamic> toJson() => {
        'min': minimum,
        'median': median,
        'mean': mean,
        'p95': p95,
        'max': maximum,
        'standard_deviation': standardDeviation,
        'first_to_last_drift_percent': firstToLastDriftPercent,
      };

  /// Decodes statistics from the benchmark report JSON schema.
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

/// Measurements and transcript output from one benchmark inference.
final class BenchmarkIteration {
  /// Creates one benchmark iteration.
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

  /// Zero-based measured iteration index.
  final int index;

  /// End-to-end elapsed time in microseconds.
  final int wallMicroseconds;

  /// Native inference time in microseconds.
  final int nativeMicroseconds;

  /// Dart/isolate overhead in microseconds.
  final int overheadMicroseconds;

  /// Inference duration divided by input-audio duration.
  final double realTimeFactor;

  /// Transcript produced by this iteration.
  final String transcript;

  /// Transcript after benchmark comparison normalization.
  final String normalizedTranscript;

  /// Word error rate relative to the benchmark reference.
  final double wordErrorRate;

  /// Converts this iteration to the benchmark report JSON schema.
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

  /// Decodes an iteration from the benchmark report JSON schema.
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

/// Benchmark results collected for one performance mode.
final class BenchmarkModeReport {
  /// Creates a report for one performance mode.
  const BenchmarkModeReport({
    required this.mode,
    required this.configuration,
    required this.warmup,
    required this.iterations,
    required this.statistics,
    required this.accuracy,
  });

  /// Performance-mode identifier.
  final String mode;

  /// Effective transcription configuration for this mode.
  final Map<String, dynamic> configuration;

  /// Unmeasured warm-up inference.
  final BenchmarkIteration warmup;

  /// Measured inference iterations.
  final List<BenchmarkIteration> iterations;

  /// Aggregated statistics keyed by metric name.
  final Map<String, BenchmarkStatistics> statistics;

  /// Accuracy thresholds and consistency results.
  final Map<String, dynamic> accuracy;

  /// Converts this mode report to the benchmark report JSON schema.
  Map<String, dynamic> toJson() => {
        'mode': mode,
        'configuration': configuration,
        'warmup': warmup.toJson(),
        'iterations': iterations.map((value) => value.toJson()).toList(),
        'statistics':
            statistics.map((key, value) => MapEntry(key, value.toJson())),
        'accuracy': accuracy,
      };

  /// Decodes a mode report from the benchmark report JSON schema.
  factory BenchmarkModeReport.fromJson(Map<String, dynamic> json) =>
      BenchmarkModeReport(
        mode: json['mode'] as String,
        configuration: (json['configuration'] as Map).cast<String, dynamic>(),
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
              (value as Map).cast<String, dynamic>(),
            ),
          ),
        ),
        accuracy: (json['accuracy'] as Map).cast<String, dynamic>(),
      );
}

/// Serializable benchmark report for a model, audio input, and environment.
final class WhisperBenchmarkReport {
  /// Creates a complete benchmark report.
  const WhisperBenchmarkReport({
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.environment,
    required this.model,
    required this.audio,
    required this.benchmarkConfiguration,
    required this.modelLoadMicroseconds,
    required this.modes,
  });

  /// Version of the benchmark JSON schema.
  final int schemaVersion;

  /// UTC time at which the report was created.
  final DateTime createdAtUtc;

  /// Device, operating-system, and native runtime metadata.
  final Map<String, dynamic> environment;

  /// Model identity and metadata.
  final Map<String, dynamic> model;

  /// Input audio identity and duration metadata.
  final Map<String, dynamic> audio;

  /// Settings shared across benchmark modes.
  final Map<String, dynamic> benchmarkConfiguration;

  /// Model loading time in microseconds.
  final int modelLoadMicroseconds;

  /// Results for each tested performance mode.
  final List<BenchmarkModeReport> modes;

  /// Converts this report to its JSON-compatible map representation.
  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'created_at_utc': createdAtUtc.toUtc().toIso8601String(),
        'environment': environment,
        'model': model,
        'audio': audio,
        'benchmark_configuration': benchmarkConfiguration,
        'model_load_us': modelLoadMicroseconds,
        'modes': modes.map((value) => value.toJson()).toList(),
      };

  /// Encodes this report as JSON, optionally with indentation when [pretty].
  String encode({bool pretty = false}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());

  /// Decodes a report from its JSON-compatible map representation.
  factory WhisperBenchmarkReport.fromJson(Map<String, dynamic> json) =>
      WhisperBenchmarkReport(
        schemaVersion: json['schema_version'] as int,
        createdAtUtc: DateTime.parse(json['created_at_utc'] as String).toUtc(),
        environment: (json['environment'] as Map).cast<String, dynamic>(),
        model: (json['model'] as Map).cast<String, dynamic>(),
        audio: (json['audio'] as Map).cast<String, dynamic>(),
        benchmarkConfiguration:
            (json['benchmark_configuration'] as Map).cast<String, dynamic>(),
        modelLoadMicroseconds: json['model_load_us'] as int,
        modes: (json['modes'] as List)
            .map((value) => BenchmarkModeReport.fromJson(
                  (value as Map).cast<String, dynamic>(),
                ))
            .toList(growable: false),
      );

  /// Decodes a report from a JSON [source] string.
  factory WhisperBenchmarkReport.decode(String source) =>
      WhisperBenchmarkReport.fromJson(
        (jsonDecode(source) as Map).cast<String, dynamic>(),
      );

  /// Validates report structure, metrics, accuracy, and mode consistency.
  ///
  /// Throws [StateError] on the first invalid value. [expectedModes] and
  /// [expectedIterations] describe the benchmark run that must be present.
  void validate({
    Set<String> expectedModes = const {
      'responsive',
      'balanced',
      'efficient',
    },
    int expectedIterations = 3,
  }) {
    if (schemaVersion != 3) {
      throw StateError('Unsupported benchmark schema $schemaVersion');
    }
    if (modelLoadMicroseconds <= 0) {
      throw StateError('Benchmark contains an invalid model load time');
    }

    final actualModes = modes.map((value) => value.mode).toSet();
    if (actualModes.length != modes.length ||
        actualModes.length != expectedModes.length ||
        !actualModes.containsAll(expectedModes)) {
      throw StateError(
          'Benchmark modes are missing, duplicated, or unexpected');
    }

    for (final mode in modes) {
      if (mode.iterations.length != expectedIterations) {
        throw StateError(
          'Expected $expectedIterations measured iterations for ${mode.mode}, '
          'found ${mode.iterations.length}',
        );
      }
      final maximumAcceptedValue =
          mode.accuracy['maximum_accepted_word_error_rate'];
      if (maximumAcceptedValue is! num) {
        throw StateError('${mode.mode} has no valid WER threshold');
      }
      final maximumAccepted = maximumAcceptedValue.toDouble();
      if (!maximumAccepted.isFinite || maximumAccepted < 0) {
        throw StateError('${mode.mode} has an invalid WER threshold');
      }
      final maximumObservedValue =
          mode.accuracy['maximum_observed_word_error_rate'];
      if (maximumObservedValue is! num ||
          !maximumObservedValue.toDouble().isFinite ||
          maximumObservedValue < 0 ||
          maximumObservedValue > maximumAccepted) {
        throw StateError('${mode.mode} has an invalid observed WER');
      }
      if (mode.accuracy['transcripts_consistent'] != true) {
        throw StateError('${mode.mode} reports inconsistent transcripts');
      }

      _validateIteration(mode.warmup, maximumAccepted, mode.mode);
      final transcript = mode.iterations.first.normalizedTranscript;
      for (final iteration in mode.iterations) {
        _validateIteration(iteration, maximumAccepted, mode.mode);
        if (iteration.normalizedTranscript != transcript) {
          throw StateError('${mode.mode} has inconsistent transcripts');
        }
      }
      for (final statistics in mode.statistics.values) {
        final values = [
          statistics.minimum,
          statistics.median,
          statistics.mean,
          statistics.p95,
          statistics.maximum,
          statistics.standardDeviation,
          statistics.firstToLastDriftPercent,
        ];
        if (values.any((value) => !value.isFinite)) {
          throw StateError('${mode.mode} has non-finite statistics');
        }
      }
    }
  }
}

void _validateIteration(
  BenchmarkIteration iteration,
  double maximumAcceptedWordErrorRate,
  String mode,
) {
  if (iteration.wallMicroseconds <= 0 ||
      iteration.nativeMicroseconds <= 0 ||
      iteration.overheadMicroseconds < 0 ||
      !iteration.realTimeFactor.isFinite ||
      iteration.realTimeFactor <= 0 ||
      !iteration.wordErrorRate.isFinite ||
      iteration.wordErrorRate < 0 ||
      iteration.wordErrorRate > maximumAcceptedWordErrorRate) {
    throw StateError('$mode contains invalid benchmark metrics');
  }
}
