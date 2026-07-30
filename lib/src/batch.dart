import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'audio_utils.dart';
import 'models.dart';

/// One input in a sequential transcription batch.
sealed class WhisperBatchInput {
  WhisperBatchInput._(this.id, this.options) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty');
    }
  }

  /// Application-defined identifier used by progress and results.
  final String id;

  /// Per-item options, or `null` to use the batch defaults.
  final TranscribeOptions? options;
}

/// A batch input containing prepared mono 16 kHz floating-point PCM.
final class WhisperPcmBatchInput extends WhisperBatchInput {
  /// Creates a prepared-PCM batch item.
  WhisperPcmBatchInput(
    String id,
    this.samples, {
    TranscribeOptions? options,
  }) : super._(id, options);

  /// Prepared audio samples passed directly to the engine.
  final Float32List samples;
}

/// A batch input containing a WAV file decoded before inference.
final class WhisperWavBatchInput extends WhisperBatchInput {
  /// Creates a WAV-file batch item.
  WhisperWavBatchInput(
    String id,
    this.file, {
    TranscribeOptions? options,
  }) : super._(id, options);

  /// WAV file decoded through [WhisperAudio.readWav].
  final File file;
}

/// Completion information for one successfully processed or captured item.
final class WhisperBatchItemResult {
  const WhisperBatchItemResult._({
    required this.input,
    this.result,
    this.error,
    this.stackTrace,
  });

  /// Creates a successful item result.
  factory WhisperBatchItemResult.success(
    WhisperBatchInput input,
    WhisperResult result,
  ) =>
      WhisperBatchItemResult._(input: input, result: result);

  /// Creates a captured item failure.
  factory WhisperBatchItemResult.failure(
    WhisperBatchInput input,
    Object error,
    StackTrace stackTrace,
  ) =>
      WhisperBatchItemResult._(
        input: input,
        error: error,
        stackTrace: stackTrace,
      );

  /// Source item.
  final WhisperBatchInput input;

  /// Completed transcription, or `null` when this item failed.
  final WhisperResult? result;

  /// Captured error when `continueOnError` was enabled.
  final Object? error;

  /// Stack trace associated with [error].
  final StackTrace? stackTrace;

  /// Whether this item completed successfully.
  bool get isSuccess => result != null;
}

/// Ordered progress emitted by a sequential transcription batch.
final class WhisperBatchProgress {
  /// Creates an immutable batch progress snapshot.
  const WhisperBatchProgress({
    required this.completed,
    required this.total,
    required this.currentId,
    required this.isFinal,
  });

  /// Number of items that have reached a result.
  final int completed;

  /// Total number of input items.
  final int total;

  /// Most recently completed item, or `null` for an empty batch.
  final String? currentId;

  /// Whether all input items have completed.
  final bool isFinal;

  /// Completion ratio from zero to one.
  double get fraction => total == 0 ? 1 : completed / total;
}

/// Loads the samples for one batch input.
typedef WhisperBatchSampleLoader = Future<Float32List> Function(
  WhisperBatchInput input,
);

/// Starts one inference pass for a batch input.
typedef WhisperBatchInferenceStarter = Future<WhisperResult> Function(
  Float32List samples,
  TranscribeOptions options,
);

/// Owns one sequential batch and its active inference.
final class WhisperBatchTask {
  WhisperBatchTask._({
    required List<WhisperBatchInput> inputs,
    required TranscribeOptions defaultOptions,
    required bool continueOnError,
    required WhisperBatchSampleLoader loadSamples,
    required WhisperBatchInferenceStarter startInference,
    required void Function() releaseEngine,
    void Function()? cancelInference,
  })  : _inputs = inputs,
        _defaultOptions = defaultOptions,
        _continueOnError = continueOnError,
        _loadSamples = loadSamples,
        _startInference = startInference,
        _releaseEngine = releaseEngine,
        _cancelInference = cancelInference {
    _result.future.ignore();
    _runFuture = _run();
  }

  /// Creates a sequential batch around injectable loading and inference.
  ///
  /// Applications normally use `WhisperEngine.transcribeBatch`. This lower
  /// level entry point supports custom engines and deterministic tests.
  static WhisperBatchTask start({
    required List<WhisperBatchInput> inputs,
    required WhisperBatchInferenceStarter startInference,
    required void Function() releaseEngine,
    TranscribeOptions defaultOptions = const TranscribeOptions(),
    bool continueOnError = false,
    WhisperBatchSampleLoader loadSamples = _loadInputSamples,
    void Function()? cancelInference,
  }) {
    final copied = List<WhisperBatchInput>.unmodifiable(inputs);
    _validateInputs(copied);
    return WhisperBatchTask._(
      inputs: copied,
      defaultOptions: defaultOptions,
      continueOnError: continueOnError,
      loadSamples: loadSamples,
      startInference: startInference,
      releaseEngine: releaseEngine,
      cancelInference: cancelInference,
    );
  }

  final List<WhisperBatchInput> _inputs;
  final TranscribeOptions _defaultOptions;
  final bool _continueOnError;
  final WhisperBatchSampleLoader _loadSamples;
  final WhisperBatchInferenceStarter _startInference;
  final void Function() _releaseEngine;
  final void Function()? _cancelInference;
  final _updates = StreamController<WhisperBatchProgress>();
  final _result = Completer<List<WhisperBatchItemResult>>();

  late final Future<void> _runFuture;
  bool _cancelled = false;
  bool _released = false;

  /// Ordered item-completion updates.
  Stream<WhisperBatchProgress> get updates => _updates.stream;

  /// Completes with ordered results, or the first uncaptured failure.
  Future<List<WhisperBatchItemResult>> get result => _result.future;

  /// Cancels the active inference and prevents subsequent items from starting.
  Future<void> cancel() async {
    if (_result.isCompleted) return;
    _cancelled = true;
    _cancelInference?.call();
    await _runFuture;
  }

  Future<void> _run() async {
    final results = <WhisperBatchItemResult>[];
    Object? terminalError;
    StackTrace? terminalStackTrace;
    try {
      if (_inputs.isEmpty) {
        _updates.add(const WhisperBatchProgress(
          completed: 0,
          total: 0,
          currentId: null,
          isFinal: true,
        ));
      }
      for (final input in _inputs) {
        _throwIfCancelled();
        try {
          final samples = await _loadSamples(input);
          _throwIfCancelled();
          final result = await _startInference(
            samples,
            input.options ?? _defaultOptions,
          );
          _throwIfCancelled();
          results.add(WhisperBatchItemResult.success(input, result));
        } catch (error, stackTrace) {
          if (_cancelled) {
            throw const WhisperException('Batch transcription cancelled');
          }
          if (!_continueOnError) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          results.add(
            WhisperBatchItemResult.failure(input, error, stackTrace),
          );
        }
        _updates.add(WhisperBatchProgress(
          completed: results.length,
          total: _inputs.length,
          currentId: input.id,
          isFinal: results.length == _inputs.length,
        ));
      }
    } catch (error, stackTrace) {
      terminalError = error;
      terminalStackTrace = stackTrace;
    } finally {
      if (!_updates.isClosed) unawaited(_updates.close());
      _releaseOnce();
    }
    if (_result.isCompleted) return;
    if (terminalError != null) {
      _result.completeError(terminalError, terminalStackTrace!);
    } else {
      _result.complete(List<WhisperBatchItemResult>.unmodifiable(results));
    }
  }

  void _throwIfCancelled() {
    if (_cancelled) {
      throw const WhisperException('Batch transcription cancelled');
    }
  }

  void _releaseOnce() {
    if (_released) return;
    _released = true;
    _releaseEngine();
  }
}

Future<Float32List> _loadInputSamples(WhisperBatchInput input) {
  return switch (input) {
    WhisperPcmBatchInput(:final samples) => Future.value(samples),
    WhisperWavBatchInput(:final file) => WhisperAudio.readWav(file),
  };
}

void _validateInputs(List<WhisperBatchInput> inputs) {
  final ids = <String>{};
  for (final input in inputs) {
    if (!ids.add(input.id)) {
      throw ArgumentError.value(
        input.id,
        'inputs',
        'Batch item IDs must be unique',
      );
    }
  }
}
