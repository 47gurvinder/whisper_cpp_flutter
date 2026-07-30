import 'dart:typed_data';

/// Decoding algorithm used to select transcription tokens.
enum WhisperSamplingStrategy {
  /// Selects locally best candidates with optional repeated attempts.
  greedy,

  /// Searches multiple candidate sequences using a beam.
  beamSearch,
}

/// Reusable offline transcription profiles with different performance goals.
enum WhisperPerformanceMode {
  /// Prioritizes lower latency with fewer decoding candidates.
  responsive,

  /// Balances decoding quality and computation.
  balanced,

  /// Reduces decoding work and CPU concurrency.
  efficient,
}

/// Verbosity of native whisper.cpp diagnostic logging.
enum WhisperLogLevel {
  /// Disables native diagnostic logging.
  none,

  /// Reports errors only.
  error,

  /// Reports warnings and errors.
  warning,

  /// Reports general informational messages.
  info,

  /// Reports detailed debugging messages.
  debug,

  /// Reports the most detailed tracing messages.
  trace,
}

const _copyWithUnset = Object();

/// An error reported by the Dart wrapper or native whisper.cpp runtime.
final class WhisperException implements Exception {
  /// Creates an exception with a human-readable [message].
  const WhisperException(this.message);

  /// Description of the failure.
  final String message;

  @override
  String toString() => 'WhisperException: $message';
}

/// Native model-loading options.
final class WhisperConfig {
  /// Creates model-loading options.
  const WhisperConfig({
    this.useGpu = true,
    this.useFlashAttention = true,
    this.useDtw = false,
    this.dtwModel = 0,
  });

  /// Whether supported GPU acceleration should be enabled.
  final bool useGpu;

  /// Whether flash attention should be enabled when supported.
  final bool useFlashAttention;

  /// Whether dynamic-time-warping token timestamps should be enabled.
  final bool useDtw;

  /// whisper.cpp alignment-head preset used when [useDtw] is enabled.
  final int dtwModel;
}

/// Options controlling a transcription job.
///
/// Defaults follow whisper.cpp's general-purpose decoding configuration.
final class TranscribeOptions {
  /// Creates transcription options.
  const TranscribeOptions({
    this.strategy = WhisperSamplingStrategy.greedy,
    this.threads = 4,
    this.language = 'auto',
    this.translate = false,
    this.detectLanguage = false,
    this.offsetMs = 0,
    this.durationMs = 0,
    this.maxTextContext = 16384,
    this.maxSegmentLength = 0,
    this.maxTokensPerSegment = 0,
    this.audioContext = 0,
    this.tokenTimestamps = true,
    this.splitOnWord = false,
    this.suppressBlank = true,
    this.suppressNonSpeechTokens = false,
    this.singleSegment = false,
    this.noContext = true,
    this.noTimestamps = false,
    this.printSpecialTokens = false,
    this.tinyDiarize = false,
    this.debugMode = false,
    this.carryInitialPrompt = false,
    this.initialPrompt,
    this.suppressRegex,
    this.temperature = 0,
    this.timestampTokenThreshold = 0.01,
    this.timestampTokenSumThreshold = 0.01,
    this.maxInitialTimestamp = 1.0,
    this.lengthPenalty = -1.0,
    this.temperatureIncrement = 0.2,
    this.entropyThreshold = 2.4,
    this.logProbabilityThreshold = -1,
    this.noSpeechThreshold = 0.6,
    this.greedyBestOf = 5,
    this.beamSize = 5,
    this.beamPatience = -1,
    this.enableVad = false,
    this.vadModelPath,
    this.vadThreshold = 0.5,
    this.vadMinSpeechMs = 250,
    this.vadMinSilenceMs = 100,
    this.vadMaxSpeechSeconds = double.maxFinite,
    this.vadSpeechPadMs = 30,
    this.vadSamplesOverlap = 0.1,
  });

  /// Token decoding strategy.
  final WhisperSamplingStrategy strategy;

  /// Integer-valued decoding and VAD settings.
  ///
  /// Time values whose names end in `Ms` are expressed in milliseconds.
  /// A zero duration or limit asks whisper.cpp to use the available input or
  /// its native default.
  final int threads,
      offsetMs,
      durationMs,
      maxTextContext,
      maxSegmentLength,
      maxTokensPerSegment,
      audioContext,
      greedyBestOf,
      beamSize,
      vadMinSpeechMs,
      vadMinSilenceMs,
      vadSpeechPadMs;

  /// Language code to transcribe, or `auto` for automatic selection.
  final String language;

  /// Boolean decoding, timestamp, debugging, and VAD switches.
  final bool translate,
      detectLanguage,
      tokenTimestamps,
      splitOnWord,
      suppressBlank,
      suppressNonSpeechTokens,
      singleSegment,
      noContext,
      noTimestamps,
      printSpecialTokens,
      tinyDiarize,
      debugMode,
      carryInitialPrompt,
      enableVad;

  /// Optional prompt, suppression expression, and VAD model path.
  final String? initialPrompt, suppressRegex, vadModelPath;

  /// Floating-point decoding thresholds and VAD settings.
  ///
  /// [vadMaxSpeechSeconds] is measured in seconds; the other VAD duration
  /// fields are represented by their explicitly named integer properties.
  final double temperature,
      temperatureIncrement,
      entropyThreshold,
      timestampTokenThreshold,
      timestampTokenSumThreshold,
      maxInitialTimestamp,
      lengthPenalty,
      logProbabilityThreshold,
      noSpeechThreshold,
      beamPatience,
      vadThreshold,
      vadMaxSpeechSeconds,
      vadSamplesOverlap;

  /// Returns a copy with the supplied values replacing existing settings.
  ///
  /// Passing `null` for [initialPrompt], [suppressRegex], or [vadModelPath]
  /// explicitly clears that value. Omitting one of those arguments preserves
  /// the current value.
  TranscribeOptions copyWith({
    WhisperSamplingStrategy? strategy,
    int? threads,
    String? language,
    bool? translate,
    bool? detectLanguage,
    int? offsetMs,
    int? durationMs,
    int? maxTextContext,
    int? maxSegmentLength,
    int? maxTokensPerSegment,
    int? audioContext,
    bool? tokenTimestamps,
    bool? splitOnWord,
    bool? suppressBlank,
    bool? suppressNonSpeechTokens,
    bool? singleSegment,
    bool? noContext,
    bool? noTimestamps,
    bool? printSpecialTokens,
    bool? tinyDiarize,
    bool? debugMode,
    bool? carryInitialPrompt,
    Object? initialPrompt = _copyWithUnset,
    Object? suppressRegex = _copyWithUnset,
    double? temperature,
    double? timestampTokenThreshold,
    double? timestampTokenSumThreshold,
    double? maxInitialTimestamp,
    double? lengthPenalty,
    double? temperatureIncrement,
    double? entropyThreshold,
    double? logProbabilityThreshold,
    double? noSpeechThreshold,
    int? greedyBestOf,
    int? beamSize,
    double? beamPatience,
    bool? enableVad,
    Object? vadModelPath = _copyWithUnset,
    double? vadThreshold,
    int? vadMinSpeechMs,
    int? vadMinSilenceMs,
    double? vadMaxSpeechSeconds,
    int? vadSpeechPadMs,
    double? vadSamplesOverlap,
  }) =>
      TranscribeOptions(
        strategy: strategy ?? this.strategy,
        threads: threads ?? this.threads,
        language: language ?? this.language,
        translate: translate ?? this.translate,
        detectLanguage: detectLanguage ?? this.detectLanguage,
        offsetMs: offsetMs ?? this.offsetMs,
        durationMs: durationMs ?? this.durationMs,
        maxTextContext: maxTextContext ?? this.maxTextContext,
        maxSegmentLength: maxSegmentLength ?? this.maxSegmentLength,
        maxTokensPerSegment: maxTokensPerSegment ?? this.maxTokensPerSegment,
        audioContext: audioContext ?? this.audioContext,
        tokenTimestamps: tokenTimestamps ?? this.tokenTimestamps,
        splitOnWord: splitOnWord ?? this.splitOnWord,
        suppressBlank: suppressBlank ?? this.suppressBlank,
        suppressNonSpeechTokens:
            suppressNonSpeechTokens ?? this.suppressNonSpeechTokens,
        singleSegment: singleSegment ?? this.singleSegment,
        noContext: noContext ?? this.noContext,
        noTimestamps: noTimestamps ?? this.noTimestamps,
        printSpecialTokens: printSpecialTokens ?? this.printSpecialTokens,
        tinyDiarize: tinyDiarize ?? this.tinyDiarize,
        debugMode: debugMode ?? this.debugMode,
        carryInitialPrompt: carryInitialPrompt ?? this.carryInitialPrompt,
        initialPrompt: identical(initialPrompt, _copyWithUnset)
            ? this.initialPrompt
            : initialPrompt as String?,
        suppressRegex: identical(suppressRegex, _copyWithUnset)
            ? this.suppressRegex
            : suppressRegex as String?,
        temperature: temperature ?? this.temperature,
        timestampTokenThreshold:
            timestampTokenThreshold ?? this.timestampTokenThreshold,
        timestampTokenSumThreshold:
            timestampTokenSumThreshold ?? this.timestampTokenSumThreshold,
        maxInitialTimestamp: maxInitialTimestamp ?? this.maxInitialTimestamp,
        lengthPenalty: lengthPenalty ?? this.lengthPenalty,
        temperatureIncrement: temperatureIncrement ?? this.temperatureIncrement,
        entropyThreshold: entropyThreshold ?? this.entropyThreshold,
        logProbabilityThreshold:
            logProbabilityThreshold ?? this.logProbabilityThreshold,
        noSpeechThreshold: noSpeechThreshold ?? this.noSpeechThreshold,
        greedyBestOf: greedyBestOf ?? this.greedyBestOf,
        beamSize: beamSize ?? this.beamSize,
        beamPatience: beamPatience ?? this.beamPatience,
        enableVad: enableVad ?? this.enableVad,
        vadModelPath: identical(vadModelPath, _copyWithUnset)
            ? this.vadModelPath
            : vadModelPath as String?,
        vadThreshold: vadThreshold ?? this.vadThreshold,
        vadMinSpeechMs: vadMinSpeechMs ?? this.vadMinSpeechMs,
        vadMinSilenceMs: vadMinSilenceMs ?? this.vadMinSilenceMs,
        vadMaxSpeechSeconds: vadMaxSpeechSeconds ?? this.vadMaxSpeechSeconds,
        vadSpeechPadMs: vadSpeechPadMs ?? this.vadSpeechPadMs,
        vadSamplesOverlap: vadSamplesOverlap ?? this.vadSamplesOverlap,
      );

  /// Applies the fields controlled by [mode] while preserving every other
  /// transcription option.
  ///
  /// Efficient mode reduces decoding work and CPU concurrency. It does not
  /// guarantee lower latency or imply measured energy or battery savings.
  TranscribeOptions withPerformanceMode(WhisperPerformanceMode mode) {
    return switch (mode) {
      WhisperPerformanceMode.responsive => copyWith(
          threads: 4,
          greedyBestOf: 1,
          tokenTimestamps: false,
          noTimestamps: true,
        ),
      WhisperPerformanceMode.balanced => copyWith(
          threads: 4,
          greedyBestOf: 5,
          tokenTimestamps: true,
          noTimestamps: false,
        ),
      WhisperPerformanceMode.efficient => copyWith(
          threads: 2,
          greedyBestOf: 1,
          tokenTimestamps: false,
          noTimestamps: true,
        ),
    };
  }
}

/// A decoded whisper.cpp token and its timing/probability metadata.
final class WhisperToken {
  /// Creates a decoded token.
  const WhisperToken(
      {required this.id,
      required this.text,
      required this.start,
      required this.end,
      required this.probability,
      required this.logProbability,
      required this.timestampProbability,
      required this.timestampProbabilitySum,
      required this.dtwTimestamp,
      required this.voiceLength});

  /// Native whisper.cpp token identifier.
  final int id;

  /// Decoded text represented by this token.
  final String text;

  /// Start and end offsets within the input audio.
  final Duration start, end;

  /// Token probability and log probability.
  final double probability, logProbability;

  /// Timestamp probabilities and voice-length metadata.
  final double timestampProbability, timestampProbabilitySum, voiceLength;

  /// Dynamic-time-warping timestamp, or a negative duration when unavailable.
  final Duration dtwTimestamp;

  /// Decodes a token from the native bridge JSON representation.
  factory WhisperToken.fromJson(Map<String, dynamic> j) => WhisperToken(
      id: j['id'],
      text: j['text'],
      start: Duration(milliseconds: j['t0']),
      end: Duration(milliseconds: j['t1']),
      probability: (j['p'] as num).toDouble(),
      logProbability: (j['plog'] as num).toDouble(),
      timestampProbability: (j['pt'] as num).toDouble(),
      timestampProbabilitySum: (j['ptsum'] as num).toDouble(),
      dtwTimestamp: Duration(milliseconds: j['t_dtw']),
      voiceLength: (j['vlen'] as num).toDouble());

  /// Encodes this token using the native bridge JSON schema.
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        't0': start.inMilliseconds,
        't1': end.inMilliseconds,
        'p': probability,
        'plog': logProbability,
        'pt': timestampProbability,
        'ptsum': timestampProbabilitySum,
        't_dtw': dtwTimestamp.inMilliseconds,
        'vlen': voiceLength,
      };
}

/// A contiguous transcription segment.
final class WhisperSegment {
  /// Creates a transcription segment.
  const WhisperSegment(
      {required this.text,
      required this.start,
      required this.end,
      required this.tokens,
      required this.noSpeechProbability,
      required this.speakerTurnNext});

  /// Transcribed text in this segment.
  final String text;

  /// Start and end offsets within the input audio.
  final Duration start, end;

  /// Tokens decoded for this segment.
  final List<WhisperToken> tokens;

  /// Estimated probability that the segment contains no speech.
  final double noSpeechProbability;

  /// Whether whisper.cpp detected a speaker turn after this segment.
  final bool speakerTurnNext;

  /// Decodes a segment from the native bridge JSON representation.
  factory WhisperSegment.fromJson(Map<String, dynamic> j) => WhisperSegment(
      text: j['text'],
      start: Duration(milliseconds: j['t0']),
      end: Duration(milliseconds: j['t1']),
      tokens:
          (j['tokens'] as List).map((e) => WhisperToken.fromJson(e)).toList(),
      noSpeechProbability: (j['no_speech_p'] as num).toDouble(),
      speakerTurnNext: j['speaker_turn_next']);

  /// Encodes this segment using the native bridge JSON schema.
  ///
  /// Token metadata can be omitted when a smaller export is preferred.
  Map<String, dynamic> toJson({bool includeTokens = true}) => {
        'text': text,
        't0': start.inMilliseconds,
        't1': end.inMilliseconds,
        if (includeTokens)
          'tokens': tokens.map((token) => token.toJson()).toList(),
        'no_speech_p': noSpeechProbability,
        'speaker_turn_next': speakerTurnNext,
      };
}

/// Completed transcription output.
final class WhisperResult {
  /// Creates a transcription result.
  const WhisperResult(
      {required this.text,
      required this.language,
      required this.languageProbability,
      required this.segments,
      required this.processingTime,
      required this.systemInfo});

  /// Full text, detected language, and native system description.
  final String text, language, systemInfo;

  /// Confidence assigned to [language], or a negative value when unavailable.
  final double languageProbability;

  /// Time-ordered transcription segments.
  final List<WhisperSegment> segments;

  /// Native processing time, excluding Dart isolate and transfer overhead.
  final Duration processingTime;

  /// Decodes a result from the native bridge JSON representation.
  factory WhisperResult.fromJson(Map<String, dynamic> j) => WhisperResult(
      text: j['text'],
      language: j['language'],
      languageProbability: (j['language_probability'] as num).toDouble(),
      segments: (j['segments'] as List)
          .map((e) => WhisperSegment.fromJson(e))
          .toList(),
      processingTime: Duration(microseconds: j['processing_us']),
      systemInfo: j['system_info']);

  /// Encodes this result using the native bridge JSON schema.
  ///
  /// Token metadata can be omitted when a smaller export is preferred.
  Map<String, dynamic> toJson({bool includeTokens = true}) => {
        'text': text,
        'language': language,
        'language_probability': languageProbability,
        'segments': segments
            .map((segment) => segment.toJson(includeTokens: includeTokens))
            .toList(),
        'processing_us': processingTime.inMicroseconds,
        'system_info': systemInfo,
      };
}

/// A speech interval returned by voice activity detection.
final class VadSegment {
  /// Creates an interval from inclusive [start] to exclusive [end].
  const VadSegment(this.start, this.end);

  /// Start and end offsets within the analyzed audio.
  final Duration start, end;
}

/// A chunk of mono floating-point PCM audio.
final class RecordingChunk {
  /// Creates a chunk with [samples] recorded at [sampleRate] hertz.
  const RecordingChunk(this.samples, this.sampleRate);

  /// Normalized mono PCM samples, conventionally in the range -1 to 1.
  final Float32List samples;

  /// Number of samples per second.
  final int sampleRate;
}
