import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'models.dart';
import 'native_bindings.dart';

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

final class WhisperException implements Exception {
  const WhisperException(this.message);
  final String message;
  @override String toString() => 'WhisperException: $message';
}

final class WhisperTask {
  WhisperTask._(this._job, this.result) {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_progress.isClosed) _progress.add(NativeBindings.instance.progress(_job));
    });
    void done() {
      _timer.cancel();
      _progress.close();
      NativeBindings.instance.jobFree(_job);
    }
    result.then<void>((_) => done(), onError: (Object _, StackTrace __) => done());
  }
  final Pointer<Void> _job;
  final Future<WhisperResult> result;
  final _progress = StreamController<int>.broadcast();
  late final Timer _timer;
  Stream<int> get progress => _progress.stream.distinct();
  void cancel() => NativeBindings.instance.cancel(_job);
}

final class WhisperEngine {
  WhisperEngine._(this._context);
  final Pointer<Void> _context;
  bool _disposed = false;
  int _activeJobs = 0;

  static String get version => NativeBindings.instance.version().toDartString();
  static String get systemInfo => NativeBindings.instance.systemInfo().toDartString();
  static Map<String,dynamic> benchmark({int threads=4}) {
    final n=NativeBindings.instance,out=n.benchmark(threads);
    try{return (jsonDecode(out.toDartString()) as Map).cast<String,dynamic>();}finally{n.stringFree(out);}
  }

  Map<String,dynamic> get modelInfo {
    if(_disposed)throw const WhisperException('Engine is disposed');
    final n=NativeBindings.instance,out=n.modelInfo(_context);
    if(out==nullptr)throw WhisperException(n.lastError().toDartString());
    try{return (jsonDecode(out.toDartString()) as Map).cast<String,dynamic>();}finally{n.stringFree(out);}
  }

  List<int> tokenize(String text) {
    if(_disposed)throw const WhisperException('Engine is disposed');
    final n=NativeBindings.instance,input=text.toNativeUtf8();
    try{final out=n.tokenize(_context,input);if(out==nullptr)throw WhisperException(n.lastError().toDartString());try{return (jsonDecode(out.toDartString()) as List).cast<int>();}finally{n.stringFree(out);}}finally{malloc.free(input);}
  }

  static Future<WhisperEngine> load(String modelPath,
      {WhisperConfig config = const WhisperConfig()}) async {
    final invocation = _ModelLoadInvocation(modelPath, config.useGpu,
        config.useFlashAttention, config.useDtw, config.dtwModel);
    final address = await Isolate.run<int>(invocation.run);
    return WhisperEngine._(Pointer<Void>.fromAddress(address));
  }

  WhisperTask transcribe(Float32List pcm16k,
      {TranscribeOptions options = const TranscribeOptions()}) {
    if (_disposed) throw const WhisperException('Engine is disposed');
    if (_activeJobs > 0) throw const WhisperException('This engine already has an active transcription job');
    final n = NativeBindings.instance;
    final job = n.jobCreate(options.strategy.index);
    void i(String k, int v) { final p=k.toNativeUtf8(); n.setInt(job,p,v); malloc.free(p); }
    void d(String k, double v) { final p=k.toNativeUtf8(); n.setDouble(job,p,v); malloc.free(p); }
    void s(String k, String v) { final a=k.toNativeUtf8(), b=v.toNativeUtf8(); n.setString(job,a,b); malloc.free(a); malloc.free(b); }
    i('threads', options.threads); i('translate', options.translate?1:0);
    i('detect_language', options.detectLanguage?1:0); i('offset_ms', options.offsetMs);
    i('duration_ms', options.durationMs); i('max_text_ctx', options.maxTextContext);
    i('max_len', options.maxSegmentLength); i('max_tokens', options.maxTokensPerSegment);
    i('audio_ctx', options.audioContext); i('token_timestamps', options.tokenTimestamps?1:0);
    i('split_on_word', options.splitOnWord?1:0); i('suppress_blank', options.suppressBlank?1:0);
    i('suppress_nst', options.suppressNonSpeechTokens?1:0); i('single_segment', options.singleSegment?1:0);
    i('no_context', options.noContext?1:0); i('no_timestamps', options.noTimestamps?1:0);
    i('print_special', options.printSpecialTokens?1:0); i('greedy_best_of', options.greedyBestOf);
    i('tdrz', options.tinyDiarize?1:0); i('debug_mode', options.debugMode?1:0);
    i('carry_initial_prompt', options.carryInitialPrompt?1:0);
    i('beam_size', options.beamSize); i('vad', options.enableVad?1:0);
    i('vad_min_speech_ms', options.vadMinSpeechMs); i('vad_min_silence_ms', options.vadMinSilenceMs);
    i('vad_speech_pad_ms', options.vadSpeechPadMs); s('language', options.language);
    if (options.initialPrompt != null) s('initial_prompt', options.initialPrompt!);
    if (options.suppressRegex != null) s('suppress_regex', options.suppressRegex!);
    if (options.vadModelPath != null) s('vad_model_path', options.vadModelPath!);
    d('temperature', options.temperature); d('temperature_inc', options.temperatureIncrement);
    d('thold_pt', options.timestampTokenThreshold); d('thold_ptsum', options.timestampTokenSumThreshold);
    d('max_initial_ts', options.maxInitialTimestamp); d('length_penalty', options.lengthPenalty);
    d('entropy_thold', options.entropyThreshold); d('logprob_thold', options.logProbabilityThreshold);
    d('no_speech_thold', options.noSpeechThreshold); d('beam_patience', options.beamPatience);
    d('vad_threshold', options.vadThreshold); d('vad_max_speech_s', options.vadMaxSpeechSeconds);
    d('vad_samples_overlap', options.vadSamplesOverlap);
    _activeJobs++;
    final invocation =
        _TranscriptionInvocation(_context.address, job.address, pcm16k);
    final future = Isolate.run<WhisperResult>(invocation.run);
    future.then<void>((_) => _activeJobs--, onError: (Object _, StackTrace __) { _activeJobs--; });
    return WhisperTask._(job, future);
  }

  void dispose() { if (_activeJobs>0) throw const WhisperException('Cannot dispose an engine while transcription is running'); if (!_disposed) { NativeBindings.instance.contextFree(_context); _disposed=true; } }
}
