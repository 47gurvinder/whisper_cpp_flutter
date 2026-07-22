import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
// Benchmark report models are intentionally internal to the repository tooling.
// ignore: implementation_imports
import 'package:whisper_cpp_flutter_plus/src/benchmark_report.dart';

typedef BenchmarkProgress = void Function(String message, double? fraction);

final class BenchmarkCancelledException implements Exception {
  const BenchmarkCancelledException();

  @override
  String toString() => 'Benchmark cancelled';
}

final class BenchmarkRunController {
  bool _cancelled = false;
  WhisperTask? _activeTask;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _activeTask?.cancel();
  }

  void _check() {
    if (_cancelled) throw const BenchmarkCancelledException();
  }
}

final class _BenchmarkPreparationInvocation {
  const _BenchmarkPreparationInvocation(this.audioBytes, this.modelPath);

  final Uint8List audioBytes;
  final String modelPath;

  Future<_BenchmarkPreparation> run() async {
    final audioHash = sha256.convert(audioBytes).toString();
    final samples = WhisperAudio.decodeWav(audioBytes);
    final modelHash = await sha256.bind(File(modelPath).openRead()).first;
    return _BenchmarkPreparation(
      samples: samples,
      audioHash: audioHash,
      modelHash: modelHash.toString(),
    );
  }
}

final class _BenchmarkPreparation {
  const _BenchmarkPreparation({
    required this.samples,
    required this.audioHash,
    required this.modelHash,
  });

  final Float32List samples;
  final String audioHash;
  final String modelHash;
}

final class WhisperBenchmarkRunner {
  const WhisperBenchmarkRunner();

  static const modelName = 'ggml-tiny.en.bin';
  static final modelUrl = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
    'ggml-tiny.en.bin',
  );
  static const audioAsset = 'assets/benchmark/jfk.wav';
  static const audioName = 'jfk.wav';
  static const audioSha256 =
      '59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e';
  static const referenceTranscript =
      'And so my fellow Americans, ask not what your country can do for you, '
      'ask what you can do for your country.';
  static const measuredRunCount = 5;
  static const maximumAcceptedWordErrorRate = .25;
  static const _deviceChannel = MethodChannel('whisper_cpp_flutter/recorder');

  static const modelConfiguration = WhisperConfig(
    useGpu: true,
    useFlashAttention: true,
    useDtw: false,
    dtwModel: 0,
  );

  static const transcriptionOptions = TranscribeOptions(
    strategy: WhisperSamplingStrategy.greedy,
    threads: 4,
    language: 'en',
    translate: false,
    detectLanguage: false,
    offsetMs: 0,
    durationMs: 0,
    maxTextContext: 16384,
    maxSegmentLength: 0,
    maxTokensPerSegment: 0,
    audioContext: 0,
    tokenTimestamps: true,
    splitOnWord: false,
    suppressBlank: true,
    suppressNonSpeechTokens: false,
    singleSegment: false,
    noContext: true,
    noTimestamps: false,
    printSpecialTokens: false,
    tinyDiarize: false,
    debugMode: false,
    carryInitialPrompt: false,
    initialPrompt: null,
    suppressRegex: null,
    temperature: 0,
    timestampTokenThreshold: .01,
    timestampTokenSumThreshold: .01,
    maxInitialTimestamp: 1,
    lengthPenalty: -1,
    temperatureIncrement: .2,
    entropyThreshold: 2.4,
    logProbabilityThreshold: -1,
    noSpeechThreshold: .6,
    greedyBestOf: 5,
    beamSize: 5,
    beamPatience: -1,
    enableVad: false,
    vadModelPath: null,
    vadThreshold: .5,
    vadMinSpeechMs: 250,
    vadMinSilenceMs: 100,
    vadMaxSpeechSeconds: double.maxFinite,
    vadSpeechPadMs: 30,
    vadSamplesOverlap: .1,
  );

  Future<File> resolveCanonicalModel({
    required BenchmarkRunController controller,
    BenchmarkProgress? onProgress,
  }) async {
    controller._check();
    final manager = WhisperModelManager();
    final cached = await manager.find(modelName);
    controller._check();
    if (cached != null) return cached;
    onProgress?.call('Downloading $modelName outside measured time…', null);
    await for (final progress in manager.download(modelUrl, modelName)) {
      controller._check();
      onProgress?.call(
          'Downloading $modelName outside measured time…', progress.fraction);
    }
    final downloaded = await manager.find(modelName);
    if (downloaded == null) throw StateError('Downloaded model was not found');
    return downloaded;
  }

  Future<WhisperBenchmarkReport> run({
    required File modelFile,
    required BenchmarkRunController controller,
    BenchmarkProgress? onProgress,
  }) async {
    onProgress?.call(
        'Preparing audio and model metadata off the UI thread…', null);
    final audioData = await rootBundle.load(audioAsset);
    final audioBytes = audioData.buffer.asUint8List(
      audioData.offsetInBytes,
      audioData.lengthInBytes,
    );
    final preparation = await Isolate.run(
      _BenchmarkPreparationInvocation(audioBytes, modelFile.path).run,
    );
    controller._check();
    if (preparation.audioHash != audioSha256) {
      throw StateError(
        'Benchmark audio SHA-256 mismatch: ${preparation.audioHash}',
      );
    }
    final samples = preparation.samples;
    if (samples.length != 176000) {
      throw StateError(
          'Expected 176000 audio samples, found ${samples.length}');
    }
    final audioDurationUs =
        samples.length * Duration.microsecondsPerSecond ~/ 16000;
    final modelLength = await modelFile.length();
    final device = await _readDeviceInfo();
    controller._check();

    WhisperEngine? engine;
    final loadWatch = Stopwatch()..start();
    onProgress?.call('Loading $modelName…', null);
    try {
      engine = await WhisperEngine.load(
        modelFile.path,
        config: modelConfiguration,
      );
      loadWatch.stop();
      controller._check();
      final modelInfo = engine.modelInfo;

      onProgress?.call('Running unmeasured warm-up…', null);
      final warmup = await _runIteration(
        engine,
        samples,
        index: 0,
        audioDurationUs: audioDurationUs,
        controller: controller,
      );

      final iterations = <BenchmarkIteration>[];
      for (var index = 1; index <= measuredRunCount; index++) {
        controller._check();
        onProgress?.call(
          'Running measured transcription $index of $measuredRunCount…',
          index / measuredRunCount,
        );
        iterations.add(await _runIteration(
          engine,
          samples,
          index: index,
          audioDurationUs: audioDurationUs,
          controller: controller,
        ));
      }
      _validateIterations(iterations);
      final environment = <String, dynamic>{
        'operating_system': Platform.operatingSystem,
        'operating_system_version': Platform.operatingSystemVersion,
        'number_of_processors': Platform.numberOfProcessors,
        'build_mode': kReleaseMode
            ? 'release'
            : kProfileMode
                ? 'profile'
                : 'debug',
        'whisper_version': WhisperEngine.version,
        'system_info': WhisperEngine.systemInfo,
        'device': device,
      };
      final report = WhisperBenchmarkReport(
        schemaVersion: 2,
        createdAtUtc: DateTime.now().toUtc(),
        environment: environment,
        model: {
          'name': _fileName(modelFile.path),
          'bytes': modelLength,
          'sha256': preparation.modelHash,
          'info': modelInfo,
        },
        audio: {
          'name': audioName,
          'asset': audioAsset,
          'bytes': audioBytes.length,
          'sha256': preparation.audioHash,
          'sample_rate': 16000,
          'sample_count': samples.length,
          'duration_us': audioDurationUs,
          'reference_transcript': referenceTranscript,
        },
        configuration: _configurationJson(),
        modelLoadMicroseconds: loadWatch.elapsedMicroseconds,
        warmup: warmup,
        iterations: List.unmodifiable(iterations),
        statistics: _statistics(iterations),
        accuracy: {
          'expected_transcript': referenceTranscript,
          'normalized_expected_transcript':
              normalizeBenchmarkTranscript(referenceTranscript),
          'maximum_accepted_word_error_rate': maximumAcceptedWordErrorRate,
          'maximum_observed_word_error_rate':
              iterations.map((value) => value.wordErrorRate).reduce(mathMax),
          'transcripts_consistent': true,
        },
      );
      report.validate(expectedIterations: measuredRunCount);
      onProgress?.call('Benchmark complete.', 1);
      return report;
    } finally {
      loadWatch.stop();
      engine?.dispose();
    }
  }

  Future<BenchmarkIteration> _runIteration(
    WhisperEngine engine,
    Float32List samples, {
    required int index,
    required int audioDurationUs,
    required BenchmarkRunController controller,
  }) async {
    controller._check();
    final watch = Stopwatch()..start();
    final task = engine.transcribe(samples, options: transcriptionOptions);
    controller._activeTask = task;
    final WhisperResult result;
    try {
      result = await task.result;
    } catch (_) {
      if (controller.isCancelled) {
        throw const BenchmarkCancelledException();
      }
      rethrow;
    } finally {
      if (identical(controller._activeTask, task)) {
        controller._activeTask = null;
      }
    }
    watch.stop();
    controller._check();
    final wallUs = watch.elapsedMicroseconds;
    final nativeUs = result.processingTime.inMicroseconds;
    if (wallUs <= 0 || nativeUs <= 0) {
      throw StateError('Benchmark produced a non-positive duration');
    }
    final transcript = result.text.trim();
    return BenchmarkIteration(
      index: index,
      wallMicroseconds: wallUs,
      nativeMicroseconds: nativeUs,
      overheadMicroseconds: wallUs - nativeUs,
      realTimeFactor: wallUs / audioDurationUs,
      transcript: transcript,
      normalizedTranscript: normalizeBenchmarkTranscript(transcript),
      wordErrorRate: benchmarkWordErrorRate(referenceTranscript, transcript),
    );
  }

  void _validateIterations(List<BenchmarkIteration> iterations) {
    if (iterations.length != measuredRunCount) {
      throw StateError('Expected $measuredRunCount measured iterations');
    }
    final transcript = iterations.first.normalizedTranscript;
    for (final iteration in iterations) {
      if (!iteration.realTimeFactor.isFinite ||
          !iteration.wordErrorRate.isFinite ||
          iteration.normalizedTranscript != transcript) {
        throw StateError('Measured transcripts or metrics are inconsistent');
      }
      if (iteration.wordErrorRate > maximumAcceptedWordErrorRate) {
        throw StateError(
          'JFK word error rate ${iteration.wordErrorRate.toStringAsFixed(3)} '
          'exceeds $maximumAcceptedWordErrorRate',
        );
      }
    }
  }

  Map<String, BenchmarkStatistics> _statistics(
    List<BenchmarkIteration> iterations,
  ) =>
      {
        'wall_us': BenchmarkStatistics.calculate(
          iterations.map((value) => value.wallMicroseconds).toList(),
        ),
        'native_us': BenchmarkStatistics.calculate(
          iterations.map((value) => value.nativeMicroseconds).toList(),
        ),
        'overhead_us': BenchmarkStatistics.calculate(
          iterations.map((value) => value.overheadMicroseconds).toList(),
        ),
        'real_time_factor': BenchmarkStatistics.calculate(
          iterations.map((value) => value.realTimeFactor).toList(),
        ),
      };

  Map<String, dynamic> _configurationJson() => {
        'model': {
          'use_gpu': modelConfiguration.useGpu,
          'use_flash_attention': modelConfiguration.useFlashAttention,
          'use_dtw': modelConfiguration.useDtw,
          'dtw_model': modelConfiguration.dtwModel,
        },
        'transcription': {
          'strategy': transcriptionOptions.strategy.name,
          'threads': transcriptionOptions.threads,
          'language': transcriptionOptions.language,
          'translate': transcriptionOptions.translate,
          'detect_language': transcriptionOptions.detectLanguage,
          'offset_ms': transcriptionOptions.offsetMs,
          'duration_ms': transcriptionOptions.durationMs,
          'max_text_context': transcriptionOptions.maxTextContext,
          'max_segment_length': transcriptionOptions.maxSegmentLength,
          'max_tokens_per_segment': transcriptionOptions.maxTokensPerSegment,
          'audio_context': transcriptionOptions.audioContext,
          'token_timestamps': transcriptionOptions.tokenTimestamps,
          'split_on_word': transcriptionOptions.splitOnWord,
          'suppress_blank': transcriptionOptions.suppressBlank,
          'suppress_non_speech_tokens':
              transcriptionOptions.suppressNonSpeechTokens,
          'single_segment': transcriptionOptions.singleSegment,
          'no_context': transcriptionOptions.noContext,
          'no_timestamps': transcriptionOptions.noTimestamps,
          'print_special_tokens': transcriptionOptions.printSpecialTokens,
          'tiny_diarize': transcriptionOptions.tinyDiarize,
          'debug_mode': transcriptionOptions.debugMode,
          'carry_initial_prompt': transcriptionOptions.carryInitialPrompt,
          'initial_prompt': transcriptionOptions.initialPrompt,
          'suppress_regex': transcriptionOptions.suppressRegex,
          'temperature': transcriptionOptions.temperature,
          'timestamp_token_threshold':
              transcriptionOptions.timestampTokenThreshold,
          'timestamp_token_sum_threshold':
              transcriptionOptions.timestampTokenSumThreshold,
          'max_initial_timestamp': transcriptionOptions.maxInitialTimestamp,
          'length_penalty': transcriptionOptions.lengthPenalty,
          'temperature_increment': transcriptionOptions.temperatureIncrement,
          'entropy_threshold': transcriptionOptions.entropyThreshold,
          'log_probability_threshold':
              transcriptionOptions.logProbabilityThreshold,
          'no_speech_threshold': transcriptionOptions.noSpeechThreshold,
          'greedy_best_of': transcriptionOptions.greedyBestOf,
          'beam_size': transcriptionOptions.beamSize,
          'beam_patience': transcriptionOptions.beamPatience,
          'enable_vad': transcriptionOptions.enableVad,
          'vad_model_path': transcriptionOptions.vadModelPath,
          'vad_threshold': transcriptionOptions.vadThreshold,
          'vad_min_speech_ms': transcriptionOptions.vadMinSpeechMs,
          'vad_min_silence_ms': transcriptionOptions.vadMinSilenceMs,
          'vad_max_speech_seconds': transcriptionOptions.vadMaxSpeechSeconds,
          'vad_speech_pad_ms': transcriptionOptions.vadSpeechPadMs,
          'vad_samples_overlap': transcriptionOptions.vadSamplesOverlap,
        },
        'warmup_runs': 1,
        'measured_runs': measuredRunCount,
      };

  Future<Map<String, dynamic>> _readDeviceInfo() async {
    try {
      final value = await _deviceChannel.invokeMapMethod<String, dynamic>(
        'deviceInfo',
      );
      if (value != null) return value;
    } on PlatformException {
      // Fall back to stable process information for unsupported platforms.
    } on MissingPluginException {
      // Unit tests and unsupported platforms do not register the plugin.
    }
    return {
      'manufacturer': 'unknown',
      'model': Platform.localHostname,
      'device': Platform.operatingSystem,
      'hardware': 'unknown',
      'architecture': WhisperEngine.systemInfo,
      'identity': '${Platform.operatingSystem}/${Platform.localHostname}',
    };
  }
}

double mathMax(double left, double right) => left > right ? left : right;

String _fileName(String path) => Uri.file(path).pathSegments.last;
