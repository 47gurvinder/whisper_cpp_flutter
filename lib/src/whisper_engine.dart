import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'batch.dart';
import 'models.dart';
import 'native_bindings.dart';
import 'recorder.dart';
import 'streaming.dart';

final class _ModelLoadInvocation {
  const _ModelLoadInvocation(this.modelPath, this.useGpu,
      this.useFlashAttention, this.useDtw, this.dtwModel);
  final String modelPath;
  final bool useGpu, useFlashAttention, useDtw;
  final int dtwModel;

  int run() {
    final n = NativeBindings.instance;
    final path = modelPath.toNativeUtf8();
    try {
      final context = n.contextCreate(path, useGpu ? 1 : 0,
          useFlashAttention ? 1 : 0, useDtw ? 1 : 0, dtwModel);
      if (context == nullptr) {
        throw WhisperException(n.lastError().toDartString());
      }
      return context.address;
    } finally {
      malloc.free(path);
    }
  }
}

final class _TranscriptionInvocation {
  const _TranscriptionInvocation(
      this.contextAddress, this.jobAddress, this.pcm16k);
  final int contextAddress, jobAddress;
  final Float32List pcm16k;

  WhisperResult run() {
    final n = NativeBindings.instance;
    final context = Pointer<Void>.fromAddress(contextAddress);
    final job = Pointer<Void>.fromAddress(jobAddress);
    final samples = malloc<Float>(pcm16k.length);
    samples.asTypedList(pcm16k.length).setAll(0, pcm16k);
    try {
      final out = n.run(context, job, samples, pcm16k.length);
      if (out == nullptr) {
        throw WhisperException(n.lastError().toDartString());
      }
      try {
        return WhisperResult.fromJson(jsonDecode(out.toDartString()));
      } finally {
        n.stringFree(out);
      }
    } finally {
      malloc.free(samples);
    }
  }
}

/// Handle for one asynchronous transcription job.
final class WhisperTask {
  WhisperTask._(this._job, this.result) {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_progress.isClosed) {
        _progress.add(NativeBindings.instance.progress(_job));
      }
    });
    void done() {
      _timer.cancel();
      _progress.close();
      NativeBindings.instance.jobFree(_job);
    }

    result.then<void>((_) => done(),
        onError: (Object _, StackTrace __) => done());
  }
  final Pointer<Void> _job;

  /// Completes with the transcription or with the native processing error.
  final Future<WhisperResult> result;
  final _progress = StreamController<int>.broadcast();
  late final Timer _timer;

  /// Distinct native progress percentages from 0 through 100.
  Stream<int> get progress => _progress.stream.distinct();

  /// Requests cooperative cancellation of the native job.
  ///
  /// The [result] future subsequently completes with a [WhisperException].
  void cancel() => NativeBindings.instance.cancel(_job);
}

/// A loaded whisper.cpp model context used to run transcription jobs.
///
/// An engine accepts one transcription at a time. Call [dispose] after all jobs
/// and streaming tasks have completed.
final class WhisperEngine {
  WhisperEngine._(this._context);
  final Pointer<Void> _context;
  bool _disposed = false;
  int _activeJobs = 0;
  bool _streamReserved = false;
  bool _batchReserved = false;

  /// Version string reported by the linked whisper.cpp library.
  static String get version => NativeBindings.instance.version().toDartString();

  /// Native backend and hardware information reported by whisper.cpp.
  static String get systemInfo =>
      NativeBindings.instance.systemInfo().toDartString();

  /// Runs whisper.cpp's low-level memory and matrix benchmarks.
  ///
  /// [threads] controls CPU concurrency. The returned keys are supplied by the
  /// native library and include textual benchmark measurements.
  static Map<String, dynamic> benchmark({int threads = 4}) {
    final n = NativeBindings.instance, out = n.benchmark(threads);
    try {
      return (jsonDecode(out.toDartString()) as Map).cast<String, dynamic>();
    } finally {
      n.stringFree(out);
    }
  }

  /// Metadata describing the model loaded into this engine.
  ///
  /// Throws [WhisperException] after [dispose].
  Map<String, dynamic> get modelInfo {
    if (_disposed) throw const WhisperException('Engine is disposed');
    final n = NativeBindings.instance, out = n.modelInfo(_context);
    if (out == nullptr) throw WhisperException(n.lastError().toDartString());
    try {
      return (jsonDecode(out.toDartString()) as Map).cast<String, dynamic>();
    } finally {
      n.stringFree(out);
    }
  }

  /// Converts [text] into model vocabulary token identifiers.
  ///
  /// Throws [WhisperException] after [dispose] or if native tokenization fails.
  List<int> tokenize(String text) {
    if (_disposed) throw const WhisperException('Engine is disposed');
    final n = NativeBindings.instance, input = text.toNativeUtf8();
    try {
      final out = n.tokenize(_context, input);
      if (out == nullptr) throw WhisperException(n.lastError().toDartString());
      try {
        return (jsonDecode(out.toDartString()) as List).cast<int>();
      } finally {
        n.stringFree(out);
      }
    } finally {
      malloc.free(input);
    }
  }

  /// Loads a model from a readable local filesystem path.
  ///
  /// The model may come from any source, including a download performed by the
  /// application and stored in its cache directory. `WhisperModelManager` is
  /// optional; this method does not download, copy, or take ownership of the
  /// model file. The caller must keep the file available until this engine is
  /// disposed.
  static Future<WhisperEngine> load(String modelPath,
      {WhisperConfig config = const WhisperConfig()}) async {
    final invocation = _ModelLoadInvocation(modelPath, config.useGpu,
        config.useFlashAttention, config.useDtw, config.dtwModel);
    final address = await Isolate.run<int>(invocation.run);
    return WhisperEngine._(Pointer<Void>.fromAddress(address));
  }

  /// Starts transcription of mono 16 kHz floating-point [pcm16k].
  ///
  /// The returned task provides progress and cancellation. Starting another
  /// job or stream on this engine before it completes throws a
  /// [WhisperException].
  WhisperTask transcribe(Float32List pcm16k,
      {TranscribeOptions options = const TranscribeOptions()}) {
    if (_streamReserved || _batchReserved) {
      throw const WhisperException(
          'This engine is reserved by an active transcription task');
    }
    return _transcribeInternal(pcm16k, options: options);
  }

  /// Transcribes [inputs] sequentially while reusing this loaded engine.
  ///
  /// By default the first loading or inference error terminates the batch.
  /// Set [continueOnError] to capture item failures and continue. Starting
  /// another job or stream on this engine before the batch completes throws a
  /// [WhisperException].
  WhisperBatchTask transcribeBatch(
    List<WhisperBatchInput> inputs, {
    TranscribeOptions defaultOptions = const TranscribeOptions(),
    bool continueOnError = false,
  }) {
    _reserveBatch();
    WhisperTask? activeInference;
    try {
      return WhisperBatchTask.start(
        inputs: inputs,
        defaultOptions: defaultOptions,
        continueOnError: continueOnError,
        startInference: (samples, options) {
          final task = _transcribeInternal(samples, options: options);
          activeInference = task;
          return task.result.whenComplete(() {
            if (identical(activeInference, task)) activeInference = null;
          });
        },
        cancelInference: () => activeInference?.cancel(),
        releaseEngine: () => _batchReserved = false,
      );
    } catch (_) {
      _batchReserved = false;
      rethrow;
    }
  }

  /// Continuously transcribes an arbitrary stream of mono PCM chunks.
  ///
  /// Chunk sample rates are resampled to 16 kHz when necessary, but may not
  /// change during a stream. The engine remains reserved until the returned
  /// task is stopped, cancelled, completed, or failed.
  WhisperStreamTask transcribeStream(
    Stream<RecordingChunk> audio, {
    TranscribeOptions options = const TranscribeOptions(),
    WhisperStreamConfig config = const WhisperStreamConfig(),
  }) {
    return _startStream(audio, options: options, config: config);
  }

  /// Requests microphone permission and starts live transcription in one call.
  ///
  /// Throws [WhisperException] if permission is denied. Stopping or cancelling
  /// the returned task also stops the owned microphone recorder.
  Future<WhisperStreamTask> transcribeMicrophone({
    TranscribeOptions options = const TranscribeOptions(),
    WhisperStreamConfig config = const WhisperStreamConfig(),
  }) async {
    _reserveStream(config);
    final recorder = WhisperRecorder();
    try {
      if (!await recorder.requestPermission()) {
        throw const WhisperException('Microphone permission was not granted');
      }
      final audio = await recorder.start();
      return _startStream(
        audio,
        options: options,
        config: config,
        stopSource: recorder.stop,
        alreadyReserved: true,
      );
    } catch (_) {
      _streamReserved = false;
      await recorder.stop();
      rethrow;
    }
  }

  WhisperStreamTask _startStream(
    Stream<RecordingChunk> audio, {
    required TranscribeOptions options,
    required WhisperStreamConfig config,
    Future<void> Function()? stopSource,
    bool alreadyReserved = false,
  }) {
    if (!alreadyReserved) _reserveStream(config);
    WhisperTask? activeInference;
    try {
      return WhisperStreamTask.start(
        audio: audio,
        config: config,
        startInference: (samples, contextPrompt) {
          final task = _transcribeInternal(
            samples,
            options: options,
            streaming: true,
            contextPrompt: contextPrompt,
          );
          activeInference = task;
          return task.result.whenComplete(() {
            if (identical(activeInference, task)) activeInference = null;
          });
        },
        cancelInference: () => activeInference?.cancel(),
        releaseEngine: () => _streamReserved = false,
        stopSource: stopSource,
      );
    } catch (_) {
      _streamReserved = false;
      rethrow;
    }
  }

  void _reserveStream(WhisperStreamConfig config) {
    if (_disposed) throw const WhisperException('Engine is disposed');
    if (_activeJobs > 0 || _streamReserved || _batchReserved) {
      throw const WhisperException(
          'This engine already has an active transcription job');
    }
    config.validate();
    _streamReserved = true;
  }

  void _reserveBatch() {
    if (_disposed) throw const WhisperException('Engine is disposed');
    if (_activeJobs > 0 || _streamReserved || _batchReserved) {
      throw const WhisperException(
          'This engine already has an active transcription job');
    }
    _batchReserved = true;
  }

  WhisperTask _transcribeInternal(
    Float32List pcm16k, {
    required TranscribeOptions options,
    bool streaming = false,
    String? contextPrompt,
  }) {
    if (_disposed) throw const WhisperException('Engine is disposed');
    if (_activeJobs > 0) {
      throw const WhisperException(
          'This engine already has an active transcription job');
    }
    final n = NativeBindings.instance;
    final job = n.jobCreate(options.strategy.index);
    if (job == nullptr) {
      throw WhisperException(n.lastError().toDartString());
    }
    void i(String k, int v) {
      final p = k.toNativeUtf8();
      n.setInt(job, p, v);
      malloc.free(p);
    }

    void d(String k, double v) {
      final p = k.toNativeUtf8();
      n.setDouble(job, p, v);
      malloc.free(p);
    }

    void s(String k, String v) {
      final a = k.toNativeUtf8(), b = v.toNativeUtf8();
      n.setString(job, a, b);
      malloc.free(a);
      malloc.free(b);
    }

    i('threads', options.threads);
    i('translate', options.translate ? 1 : 0);
    i('detect_language', options.detectLanguage ? 1 : 0);
    i('offset_ms', options.offsetMs);
    i('duration_ms', options.durationMs);
    i('max_text_ctx', options.maxTextContext);
    i('max_len', options.maxSegmentLength);
    i('max_tokens', options.maxTokensPerSegment);
    i('audio_ctx', options.audioContext);
    i('token_timestamps', streaming ? 1 : (options.tokenTimestamps ? 1 : 0));
    i('split_on_word', options.splitOnWord ? 1 : 0);
    i('suppress_blank', options.suppressBlank ? 1 : 0);
    i('suppress_nst', options.suppressNonSpeechTokens ? 1 : 0);
    i('single_segment', streaming ? 0 : (options.singleSegment ? 1 : 0));
    i('no_context', streaming ? 1 : (options.noContext ? 1 : 0));
    i('no_timestamps', streaming ? 0 : (options.noTimestamps ? 1 : 0));
    i('print_special', options.printSpecialTokens ? 1 : 0);
    i('greedy_best_of', options.greedyBestOf);
    i('tdrz', options.tinyDiarize ? 1 : 0);
    i('debug_mode', options.debugMode ? 1 : 0);
    i('carry_initial_prompt', options.carryInitialPrompt ? 1 : 0);
    i('beam_size', options.beamSize);
    i('vad', options.enableVad ? 1 : 0);
    i('vad_min_speech_ms', options.vadMinSpeechMs);
    i('vad_min_silence_ms', options.vadMinSilenceMs);
    i('vad_speech_pad_ms', options.vadSpeechPadMs);
    s('language', options.language);
    final prompt = [options.initialPrompt, contextPrompt]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join('\n');
    if (prompt.isNotEmpty) s('initial_prompt', prompt);
    if (options.suppressRegex != null) {
      s('suppress_regex', options.suppressRegex!);
    }
    if (options.vadModelPath != null) {
      s('vad_model_path', options.vadModelPath!);
    }
    d('temperature', options.temperature);
    d('temperature_inc', options.temperatureIncrement);
    d('thold_pt', options.timestampTokenThreshold);
    d('thold_ptsum', options.timestampTokenSumThreshold);
    d('max_initial_ts', options.maxInitialTimestamp);
    d('length_penalty', options.lengthPenalty);
    d('entropy_thold', options.entropyThreshold);
    d('logprob_thold', options.logProbabilityThreshold);
    d('no_speech_thold', options.noSpeechThreshold);
    d('beam_patience', options.beamPatience);
    d('vad_threshold', options.vadThreshold);
    d('vad_max_speech_s', options.vadMaxSpeechSeconds);
    d('vad_samples_overlap', options.vadSamplesOverlap);
    _activeJobs++;
    final invocation =
        _TranscriptionInvocation(_context.address, job.address, pcm16k);
    final future = Isolate.run<WhisperResult>(invocation.run);
    future.then<void>((_) => _activeJobs--, onError: (Object _, StackTrace __) {
      _activeJobs--;
    });
    return WhisperTask._(job, future);
  }

  /// Releases the native model context.
  ///
  /// Disposal is idempotent after the first successful call. It throws a
  /// [WhisperException] while a transcription or stream is active.
  void dispose() {
    if (_activeJobs > 0 || _streamReserved || _batchReserved) {
      throw const WhisperException(
          'Cannot dispose an engine while transcription is running');
    }
    if (!_disposed) {
      NativeBindings.instance.contextFree(_context);
      _disposed = true;
    }
  }
}
