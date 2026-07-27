import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'models.dart';

/// Controls how often live audio is decoded and how long text remains
/// provisional before it can be confirmed.
final class WhisperStreamConfig {
  /// Creates live transcription timing configuration.
  const WhisperStreamConfig({
    this.updateInterval = const Duration(seconds: 2),
    this.windowDuration = const Duration(seconds: 30),
    this.confirmationLag = const Duration(seconds: 4),
  });

  /// Minimum audio duration accumulated between inference passes.
  final Duration updateInterval;

  /// Maximum audio duration decoded by a single inference pass.
  final Duration windowDuration;

  /// Recent audio duration retained as provisional before confirmation.
  final Duration confirmationLag;

  /// Validates relationships between the configured durations.
  ///
  /// Throws [ArgumentError] when a duration is negative, zero where forbidden,
  /// or incompatible with the window duration.
  void validate() {
    if (updateInterval <= Duration.zero) {
      throw ArgumentError.value(
          updateInterval, 'updateInterval', 'Must be greater than zero');
    }
    if (windowDuration <= updateInterval) {
      throw ArgumentError.value(windowDuration, 'windowDuration',
          'Must be greater than updateInterval');
    }
    if (confirmationLag < Duration.zero) {
      throw ArgumentError.value(
          confirmationLag, 'confirmationLag', 'Must not be negative');
    }
    if (confirmationLag >= windowDuration) {
      throw ArgumentError.value(confirmationLag, 'confirmationLag',
          'Must be shorter than windowDuration');
    }
  }
}

/// A display-ready snapshot of a live transcription.
final class WhisperStreamUpdate {
  /// Creates an immutable streaming transcription snapshot.
  const WhisperStreamUpdate({
    required this.confirmedText,
    required this.partialText,
    required this.confirmedSegments,
    required this.partialSegments,
    required this.audioDuration,
    required this.isFinal,
  });

  /// Stable text that later updates will preserve.
  final String confirmedText;

  /// Provisional text that a later inference pass may replace.
  final String partialText;

  /// Stable, time-ordered segments.
  final List<WhisperSegment> confirmedSegments;

  /// Provisional segments that a later update may replace.
  final List<WhisperSegment> partialSegments;

  /// Total input audio duration received so far.
  final Duration audioDuration;

  /// Whether this is the terminal successful update.
  final bool isFinal;

  /// Combined [confirmedText] and [partialText] for display.
  String get text => '$confirmedText$partialText';
}

typedef _InferenceStarter = Future<WhisperResult> Function(
    Float32List samples, String? contextPrompt);

/// Owns one continuous transcription and its audio subscription.
final class WhisperStreamTask {
  WhisperStreamTask._({
    required Stream<RecordingChunk> audio,
    required WhisperStreamConfig config,
    required _InferenceStarter startInference,
    required void Function() releaseEngine,
    void Function()? cancelInference,
    Future<void> Function()? stopSource,
  })  : _config = config,
        _startInference = startInference,
        _releaseEngine = releaseEngine,
        _cancelInference = cancelInference,
        _stopSource = stopSource {
    _result.future.ignore();
    _audioSubscription = audio.listen(
      _addChunk,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_fail(error, stackTrace));
      },
      onDone: () => unawaited(_finish()),
      cancelOnError: false,
    );
  }

  /// Creates a streaming task around an audio source and inference callback.
  ///
  /// This lower-level entry point is useful for custom engines and tests.
  /// [releaseEngine] is called exactly once when the task terminates.
  static WhisperStreamTask start({
    required Stream<RecordingChunk> audio,
    required WhisperStreamConfig config,
    required Future<WhisperResult> Function(
            Float32List samples, String? contextPrompt)
        startInference,
    required void Function() releaseEngine,
    void Function()? cancelInference,
    Future<void> Function()? stopSource,
  }) {
    config.validate();
    return WhisperStreamTask._(
      audio: audio,
      config: config,
      startInference: startInference,
      releaseEngine: releaseEngine,
      cancelInference: cancelInference,
      stopSource: stopSource,
    );
  }

  static const _sampleRate = 16000;
  static const _timestampTolerance = Duration(milliseconds: 750);

  final WhisperStreamConfig _config;
  final _InferenceStarter _startInference;
  final void Function() _releaseEngine;
  final void Function()? _cancelInference;
  final Future<void> Function()? _stopSource;
  final _updates = StreamController<WhisperStreamUpdate>();
  final _result = Completer<WhisperStreamUpdate>();
  final _samples = <double>[];
  final _confirmed = <WhisperSegment>[];

  StreamSubscription<RecordingChunk>? _audioSubscription;
  Future<void>? _finishFuture;
  List<WhisperSegment> _previousPartial = const [];
  List<WhisperSegment> _partial = const [];
  int? _inputSampleRate;
  _StreamingResampler? _resampler;
  int _bufferStartSample = 0;
  int _totalSamples = 0;
  int _samplesSinceInference = 0;
  bool _processing = false;
  bool _dirty = false;
  bool _finishing = false;
  bool _cancelled = false;
  bool _released = false;

  /// Non-final and terminal snapshots emitted by the transcription.
  Stream<WhisperStreamUpdate> get updates => _updates.stream;

  /// Completes with the final snapshot, or with the source/inference error.
  Future<WhisperStreamUpdate> get result => _result.future;

  /// Stops the source, performs final inference, and returns the final update.
  ///
  /// Repeated calls share the same completion result.
  Future<WhisperStreamUpdate> stop() async {
    await _finish();
    return result;
  }

  /// Cancels source collection and active inference.
  ///
  /// [result] and [updates] terminate with a [WhisperException].
  Future<void> cancel() async {
    if (_result.isCompleted) return;
    _cancelled = true;
    _finishing = true;
    _cancelInference?.call();
    await _audioSubscription?.cancel();
    await _stopSourceSafely();
    await _completeError(
      const WhisperException('Streaming transcription cancelled'),
      StackTrace.current,
    );
  }

  void _addChunk(RecordingChunk chunk) {
    if (_finishing || _cancelled || _result.isCompleted) return;
    try {
      if (chunk.sampleRate <= 0) {
        throw ArgumentError.value(
            chunk.sampleRate, 'sampleRate', 'Must be greater than zero');
      }
      if (_inputSampleRate != null && _inputSampleRate != chunk.sampleRate) {
        throw FormatException(
            'Audio sample rate changed from $_inputSampleRate to '
            '${chunk.sampleRate} Hz');
      }
      _inputSampleRate ??= chunk.sampleRate;
      if (chunk.samples.isEmpty) return;
      final converted = chunk.sampleRate == _sampleRate
          ? chunk.samples
          : (_resampler ??= _StreamingResampler(chunk.sampleRate, _sampleRate))
              .add(chunk.samples);
      _samples.addAll(converted);
      _totalSamples += converted.length;
      _samplesSinceInference += converted.length;
      if (_samplesSinceInference >= _durationSamples(_config.updateInterval)) {
        _samplesSinceInference = 0;
        _scheduleInference();
      }
    } catch (error, stackTrace) {
      unawaited(_fail(error, stackTrace));
    }
  }

  void _scheduleInference() {
    if (_processing) {
      _dirty = true;
      return;
    }
    unawaited(_processOnce());
  }

  Future<void> _processOnce({bool finalPass = false}) async {
    if (_processing || _cancelled || _result.isCompleted || _samples.isEmpty) {
      return;
    }
    _processing = true;
    _dirty = false;
    try {
      final maxSamples = _durationSamples(_config.windowDuration);
      final count = math.min(maxSamples, _samples.length);
      final window = Float32List.fromList(_samples.sublist(0, count));
      final windowStart = _bufferStartSample;
      final result = await _startInference(window, _contextPrompt());
      if (_cancelled || _result.isCompleted) return;

      final absolute = result.segments
          .map((segment) => _shiftSegment(
                segment,
                Duration(
                    microseconds: windowStart *
                        Duration.microsecondsPerSecond ~/
                        _sampleRate),
              ))
          .map(_trimConfirmedOverlap)
          .whereType<WhisperSegment>()
          .toList(growable: false);

      if (finalPass) {
        final hasMoreAudio = count < _samples.length;
        if (hasMoreAudio) {
          final discardSample = windowStart + count - _overlapSamples;
          final forcedCutoff = Duration(
              microseconds: discardSample *
                  Duration.microsecondsPerSecond ~/
                  _sampleRate);
          _confirm(absolute.where((s) => s.end <= forcedCutoff));
          _partial = absolute.where((s) => s.end > _confirmedEnd).toList();
          _discardAudioThrough(discardSample);
        } else {
          _confirm(absolute);
          _partial = const [];
        }
      } else {
        _stabilize(absolute);
        if (count < _samples.length) {
          // Never let a full silent or unstable window pin the stream forever.
          // The overlap is retained so boundary words are decoded again.
          final discardSample = windowStart + count - _overlapSamples;
          final forcedCutoff = Duration(
              microseconds: discardSample *
                  Duration.microsecondsPerSecond ~/
                  _sampleRate);
          _confirm(absolute.where((segment) => segment.end <= forcedCutoff));
          _partial =
              absolute.where((segment) => segment.end > _confirmedEnd).toList();
          _previousPartial = List<WhisperSegment>.of(_partial);
          _discardAudioThrough(discardSample);
          _dirty = true;
        }
        _discardConfirmedAudio();
        _emitUpdate(isFinal: false);
      }
    } catch (error, stackTrace) {
      if (!_cancelled) await _fail(error, stackTrace);
    } finally {
      _processing = false;
      if (!finalPass && _dirty && !_finishing && !_result.isCompleted) {
        _scheduleInference();
      }
    }
  }

  void _stabilize(List<WhisperSegment> current) {
    final cutoff = _audioDuration - _config.confirmationLag;
    var stableCount = 0;
    final comparable = math.min(_previousPartial.length, current.length);
    while (stableCount < comparable) {
      final before = _previousPartial[stableCount];
      final now = current[stableCount];
      if (now.end > cutoff ||
          _normalized(before.text) != _normalized(now.text) ||
          (before.start - now.start).abs() > _timestampTolerance ||
          (before.end - now.end).abs() > _timestampTolerance) {
        break;
      }
      stableCount++;
    }
    if (stableCount > 0) _confirm(current.take(stableCount));
    _partial = current.where((s) => s.end > _confirmedEnd).toList();
    _previousPartial = List<WhisperSegment>.of(_partial);
  }

  void _confirm(Iterable<WhisperSegment> segments) {
    for (final segment in segments) {
      if (segment.end <= _confirmedEnd || _normalized(segment.text).isEmpty) {
        continue;
      }
      _confirmed.add(segment);
    }
  }

  WhisperSegment? _trimConfirmedOverlap(WhisperSegment segment) {
    if (segment.end <= _confirmedEnd) return null;
    if (segment.start >= _confirmedEnd || _confirmed.isEmpty) return segment;

    final remainingTokens = segment.tokens
        .where((token) =>
            token.end > _confirmedEnd && !token.text.startsWith('<|'))
        .toList(growable: false);
    var text = remainingTokens.map((token) => token.text).join();
    if (_normalized(text).isEmpty) {
      text = _removeWordOverlap(_segmentsText(_confirmed), segment.text);
    }
    if (_normalized(text).isEmpty) return null;
    return WhisperSegment(
      text: text,
      start:
          remainingTokens.isEmpty ? _confirmedEnd : remainingTokens.first.start,
      end: segment.end,
      tokens: remainingTokens,
      noSpeechProbability: segment.noSpeechProbability,
      speakerTurnNext: segment.speakerTurnNext,
    );
  }

  void _discardConfirmedAudio() {
    if (_confirmed.isEmpty || _samples.isEmpty) return;
    final confirmedSample = _confirmedEnd.inMicroseconds *
        _sampleRate ~/
        Duration.microsecondsPerSecond;
    _discardAudioThrough(math.max(0, confirmedSample - _overlapSamples));
  }

  void _discardAudioThrough(int absoluteSample) {
    final discardCount =
        math.min(_samples.length, absoluteSample - _bufferStartSample);
    if (discardCount <= 0) return;
    _samples.removeRange(0, discardCount);
    _bufferStartSample += discardCount;
  }

  Future<void> _finish() {
    if (_finishing) return _finishFuture ?? Future<void>.value();
    _finishing = true;
    return _finishFuture ??= _finishInternal();
  }

  Future<void> _finishInternal() async {
    if (_result.isCompleted || _cancelled) return;
    await _audioSubscription?.cancel();
    await _stopSourceSafely();
    while (_processing && !_result.isCompleted) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_result.isCompleted) return;

    if (_resampler case final resampler?) {
      final tail = resampler.close();
      _samples.addAll(tail);
      _totalSamples += tail.length;
    }

    if (_samples.isNotEmpty) {
      var previousStart = -1;
      while (_samples.isNotEmpty && !_result.isCompleted) {
        await _processOnce(finalPass: true);
        if (_bufferStartSample == previousStart) break;
        previousStart = _bufferStartSample;
        if (_samples.length <= _durationSamples(_config.windowDuration)) break;
      }
      if (_samples.isNotEmpty && _partial.isNotEmpty) {
        _confirm(_partial);
        _partial = const [];
      }
    }
    if (!_result.isCompleted) {
      final update = _buildUpdate(isFinal: true);
      _updates.add(update);
      unawaited(_updates.close());
      _result.complete(update);
      _release();
    }
  }

  Future<void> _fail(Object error, StackTrace stackTrace) async {
    if (_result.isCompleted) return;
    _finishing = true;
    _cancelInference?.call();
    await _audioSubscription?.cancel();
    await _stopSourceSafely();
    await _completeError(error, stackTrace);
  }

  Future<void> _completeError(Object error, StackTrace stackTrace) async {
    if (_result.isCompleted) return;
    _updates.addError(error, stackTrace);
    unawaited(_updates.close());
    _result.completeError(error, stackTrace);
    _release();
  }

  Future<void> _stopSourceSafely() async {
    try {
      await _stopSource?.call();
    } catch (_) {
      // Preserve the transcription or source error that initiated cleanup.
    }
  }

  void _emitUpdate({required bool isFinal}) {
    if (!_updates.isClosed) _updates.add(_buildUpdate(isFinal: isFinal));
  }

  WhisperStreamUpdate _buildUpdate({required bool isFinal}) =>
      WhisperStreamUpdate(
        confirmedText: _segmentsText(_confirmed),
        partialText: isFinal ? '' : _segmentsText(_partial),
        confirmedSegments: List.unmodifiable(_confirmed),
        partialSegments: isFinal ? const [] : List.unmodifiable(_partial),
        audioDuration: _audioDuration,
        isFinal: isFinal,
      );

  String? _contextPrompt() {
    final text = _segmentsText(_confirmed).trim();
    if (text.isEmpty) return null;
    const maxCharacters = 1000;
    return text.length <= maxCharacters
        ? text
        : text.substring(text.length - maxCharacters);
  }

  Duration get _confirmedEnd =>
      _confirmed.isEmpty ? Duration.zero : _confirmed.last.end;
  Duration get _audioDuration => Duration(
      microseconds:
          _totalSamples * Duration.microsecondsPerSecond ~/ _sampleRate);

  int _durationSamples(Duration duration) =>
      duration.inMicroseconds * _sampleRate ~/ Duration.microsecondsPerSecond;

  int get _overlapSamples => math.max(
        _durationSamples(_config.updateInterval),
        _durationSamples(_config.confirmationLag),
      );

  void _release() {
    if (_released) return;
    _released = true;
    _releaseEngine();
  }
}

final class _StreamingResampler {
  _StreamingResampler(this.inputRate, this.outputRate);

  final int inputRate;
  final int outputRate;
  double _position = 0;
  double? _previous;

  Float32List add(Float32List input) {
    if (input.isEmpty) return Float32List(0);
    final Float32List source;
    if (_previous == null) {
      source = input;
    } else {
      source = Float32List(input.length + 1)
        ..[0] = _previous!
        ..setRange(1, input.length + 1, input);
    }
    final output = <double>[];
    final step = inputRate / outputRate;
    while (_position + 1 < source.length) {
      final index = _position.floor();
      final fraction = _position - index;
      output.add(source[index] * (1 - fraction) + source[index + 1] * fraction);
      _position += step;
    }
    _position -= source.length - 1;
    _previous = source.last;
    return Float32List.fromList(output);
  }

  Float32List close() {
    if (_previous == null || _position > 0) return Float32List(0);
    final result = Float32List.fromList([_previous!]);
    _previous = null;
    return result;
  }
}

WhisperSegment _shiftSegment(WhisperSegment segment, Duration offset) =>
    WhisperSegment(
      text: segment.text,
      start: segment.start + offset,
      end: segment.end + offset,
      tokens: segment.tokens
          .map((token) => WhisperToken(
                id: token.id,
                text: token.text,
                start: _shiftTimestamp(token.start, offset),
                end: _shiftTimestamp(token.end, offset),
                probability: token.probability,
                logProbability: token.logProbability,
                timestampProbability: token.timestampProbability,
                timestampProbabilitySum: token.timestampProbabilitySum,
                dtwTimestamp: _shiftTimestamp(token.dtwTimestamp, offset),
                voiceLength: token.voiceLength,
              ))
          .toList(growable: false),
      noSpeechProbability: segment.noSpeechProbability,
      speakerTurnNext: segment.speakerTurnNext,
    );

String _segmentsText(Iterable<WhisperSegment> segments) =>
    segments.map((segment) => segment.text).join();

Duration _shiftTimestamp(Duration timestamp, Duration offset) =>
    timestamp.isNegative ? timestamp : timestamp + offset;

String _normalized(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _removeWordOverlap(String confirmed, String candidate) {
  final confirmedWords = confirmed.trim().split(RegExp(r'\s+'));
  final candidateWords = candidate.trim().split(RegExp(r'\s+'));
  if (candidateWords.isEmpty) return '';
  final maximum = math.min(confirmedWords.length, candidateWords.length);
  var overlap = 0;
  for (var length = maximum; length > 0; length--) {
    final confirmedTail = confirmedWords
        .sublist(confirmedWords.length - length)
        .map(_normalized)
        .toList();
    final candidateHead =
        candidateWords.sublist(0, length).map(_normalized).toList();
    var matches = true;
    for (var index = 0; index < length; index++) {
      if (confirmedTail[index] != candidateHead[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      overlap = length;
      break;
    }
  }
  final remaining = candidateWords.skip(overlap).join(' ');
  return remaining.isEmpty ? '' : ' $remaining';
}
