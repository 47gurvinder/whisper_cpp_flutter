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

const benchmarkExecutionOrder = <List<WhisperPerformanceMode>>[
  [
    WhisperPerformanceMode.responsive,
    WhisperPerformanceMode.balanced,
    WhisperPerformanceMode.efficient,
  ],
  [
    WhisperPerformanceMode.balanced,
    WhisperPerformanceMode.efficient,
    WhisperPerformanceMode.responsive,
  ],
  [
    WhisperPerformanceMode.efficient,
    WhisperPerformanceMode.responsive,
    WhisperPerformanceMode.balanced,
  ],
];

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
  static const measuredRunCount = 3;
  static const maximumAcceptedWordErrorRate = .25;
  static const _deviceChannel = MethodChannel('whisper_cpp_flutter/recorder');

  static const modelConfiguration = WhisperConfig(
    useGpu: true,
    useFlashAttention: true,
    useDtw: false,
    dtwModel: 0,
  );

  static const baseTranscriptionOptions = TranscribeOptions(
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
    try {
      final cached = await manager.find(modelName);
      controller._check();
      if (cached != null) return cached;
      onProgress?.call('Downloading $modelName outside measured time…', null);
      await for (final progress in manager.download(modelUrl, modelName)) {
        controller._check();
        onProgress?.call(
          'Downloading $modelName outside measured time…',
          progress.fraction,
        );
      }
      final downloaded = await manager.find(modelName);
      if (downloaded == null) {
        throw StateError('Downloaded model was not found.');
      }
      return downloaded;
    } finally {
      manager.close();
    }
  }

  Future<WhisperBenchmarkReport> run({
    required File modelFile,
    required BenchmarkRunController controller,
    BenchmarkProgress? onProgress,
  }) async {
    onProgress?.call(
      'Preparing audio and model metadata off the UI thread…',
      null,
    );
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
      final warmups = <WhisperPerformanceMode, BenchmarkIteration>{};
      final iterations = {
        for (final mode in WhisperPerformanceMode.values)
          mode: <BenchmarkIteration>[],
      };
      const totalTranscriptions = 12;
      var completedTranscriptions = 0;

      for (final mode in WhisperPerformanceMode.values) {
        controller._check();
        onProgress?.call(
          'Warming up ${_modeLabel(mode)} '
          '(${warmups.length + 1} of ${WhisperPerformanceMode.values.length})…',
          completedTranscriptions / totalTranscriptions,
        );
        warmups[mode] = await _runIteration(
          engine,
          samples,
          options: baseTranscriptionOptions.withPerformanceMode(mode),
          index: 0,
          audioDurationUs: audioDurationUs,
          controller: controller,
        );
        completedTranscriptions++;
      }

      for (var round = 0; round < benchmarkExecutionOrder.length; round++) {
        for (final mode in benchmarkExecutionOrder[round]) {
          controller._check();
          onProgress?.call(
            'Measured round ${round + 1} of $measuredRunCount · '
            '${_modeLabel(mode)}…',
            completedTranscriptions / totalTranscriptions,
          );
          iterations[mode]!.add(await _runIteration(
            engine,
            samples,
            options: baseTranscriptionOptions.withPerformanceMode(mode),
            index: round + 1,
            audioDurationUs: audioDurationUs,
            controller: controller,
          ));
          completedTranscriptions++;
        }
      }

      final modeReports = <BenchmarkModeReport>[];
      for (final mode in WhisperPerformanceMode.values) {
        final modeIterations = iterations[mode]!;
        _validateModeIterations(mode, modeIterations);
        final options = baseTranscriptionOptions.withPerformanceMode(mode);
        modeReports.add(BenchmarkModeReport(
          mode: mode.name,
          configuration: configurationForMode(mode, options),
          warmup: warmups[mode]!,
          iterations: List.unmodifiable(modeIterations),
          statistics: _statistics(modeIterations),
          accuracy: {
            'expected_transcript': referenceTranscript,
            'normalized_expected_transcript':
                normalizeBenchmarkTranscript(referenceTranscript),
            'maximum_accepted_word_error_rate': maximumAcceptedWordErrorRate,
            'maximum_observed_word_error_rate': modeIterations
                .map((value) => value.wordErrorRate)
                .reduce(_maximum),
            'transcripts_consistent': true,
          },
        ));
      }

      final report = WhisperBenchmarkReport(
        schemaVersion: 3,
        createdAtUtc: DateTime.now().toUtc(),
        environment: {
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
        },
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
        benchmarkConfiguration: {
          'warmup_runs_per_mode': 1,
          'measured_runs_per_mode': measuredRunCount,
          'execution_order': benchmarkExecutionOrder
              .map((round) => round.map((mode) => mode.name).toList())
              .toList(),
        },
        modelLoadMicroseconds: loadWatch.elapsedMicroseconds,
        modes: List.unmodifiable(modeReports),
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
    required TranscribeOptions options,
    required int index,
    required int audioDurationUs,
    required BenchmarkRunController controller,
  }) async {
    controller._check();
    final watch = Stopwatch()..start();
    final task = engine.transcribe(samples, options: options);
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

  void _validateModeIterations(
    WhisperPerformanceMode mode,
    List<BenchmarkIteration> iterations,
  ) {
    if (iterations.length != measuredRunCount) {
      throw StateError(
        'Expected $measuredRunCount measured ${mode.name} iterations',
      );
    }
    final transcript = iterations.first.normalizedTranscript;
    for (final iteration in iterations) {
      if (!iteration.realTimeFactor.isFinite ||
          !iteration.wordErrorRate.isFinite ||
          iteration.normalizedTranscript != transcript) {
        throw StateError('${_modeLabel(mode)} results are inconsistent');
      }
      if (iteration.wordErrorRate > maximumAcceptedWordErrorRate) {
        throw StateError(
          '${_modeLabel(mode)} JFK word error rate '
          '${iteration.wordErrorRate.toStringAsFixed(3)} exceeds '
          '$maximumAcceptedWordErrorRate',
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

  Map<String, dynamic> configurationForMode(
    WhisperPerformanceMode mode,
    TranscribeOptions options,
  ) =>
      {
        'mode': mode.name,
        'model': {
          'use_gpu': modelConfiguration.useGpu,
          'use_flash_attention': modelConfiguration.useFlashAttention,
          'use_dtw': modelConfiguration.useDtw,
          'dtw_model': modelConfiguration.dtwModel,
        },
        'transcription': {
          'strategy': options.strategy.name,
          'threads': options.threads,
          'language': options.language,
          'translate': options.translate,
          'detect_language': options.detectLanguage,
          'offset_ms': options.offsetMs,
          'duration_ms': options.durationMs,
          'max_text_context': options.maxTextContext,
          'max_segment_length': options.maxSegmentLength,
          'max_tokens_per_segment': options.maxTokensPerSegment,
          'audio_context': options.audioContext,
          'token_timestamps': options.tokenTimestamps,
          'split_on_word': options.splitOnWord,
          'suppress_blank': options.suppressBlank,
          'suppress_non_speech_tokens': options.suppressNonSpeechTokens,
          'single_segment': options.singleSegment,
          'no_context': options.noContext,
          'no_timestamps': options.noTimestamps,
          'print_special_tokens': options.printSpecialTokens,
          'tiny_diarize': options.tinyDiarize,
          'debug_mode': options.debugMode,
          'carry_initial_prompt': options.carryInitialPrompt,
          'initial_prompt': options.initialPrompt,
          'suppress_regex': options.suppressRegex,
          'temperature': options.temperature,
          'timestamp_token_threshold': options.timestampTokenThreshold,
          'timestamp_token_sum_threshold': options.timestampTokenSumThreshold,
          'max_initial_timestamp': options.maxInitialTimestamp,
          'length_penalty': options.lengthPenalty,
          'temperature_increment': options.temperatureIncrement,
          'entropy_threshold': options.entropyThreshold,
          'log_probability_threshold': options.logProbabilityThreshold,
          'no_speech_threshold': options.noSpeechThreshold,
          'greedy_best_of': options.greedyBestOf,
          'beam_size': options.beamSize,
          'beam_patience': options.beamPatience,
          'enable_vad': options.enableVad,
          'vad_model_path': options.vadModelPath,
          'vad_threshold': options.vadThreshold,
          'vad_min_speech_ms': options.vadMinSpeechMs,
          'vad_min_silence_ms': options.vadMinSilenceMs,
          'vad_max_speech_seconds': options.vadMaxSpeechSeconds,
          'vad_speech_pad_ms': options.vadSpeechPadMs,
          'vad_samples_overlap': options.vadSamplesOverlap,
        },
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

double _maximum(double left, double right) => left > right ? left : right;

String _fileName(String path) => Uri.file(path).pathSegments.last;

String _modeLabel(WhisperPerformanceMode mode) => switch (mode) {
      WhisperPerformanceMode.responsive => 'Responsive',
      WhisperPerformanceMode.balanced => 'Balanced',
      WhisperPerformanceMode.efficient => 'Efficient',
    };
