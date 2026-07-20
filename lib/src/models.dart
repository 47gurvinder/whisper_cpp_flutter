import 'dart:typed_data';

enum WhisperSamplingStrategy { greedy, beamSearch }
enum WhisperLogLevel { none, error, warning, info, debug, trace }

final class WhisperException implements Exception {
  const WhisperException(this.message);
  final String message;
  @override String toString() => 'WhisperException: $message';
}

final class WhisperConfig {
  const WhisperConfig({
    this.useGpu = true,
    this.useFlashAttention = true,
    this.useDtw = false,
    this.dtwModel = 0,
  });
  final bool useGpu;
  final bool useFlashAttention;
  final bool useDtw;
  final int dtwModel;
}

final class TranscribeOptions {
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
  final WhisperSamplingStrategy strategy;
  final int threads, offsetMs, durationMs, maxTextContext, maxSegmentLength,
      maxTokensPerSegment, audioContext, greedyBestOf, beamSize,
      vadMinSpeechMs, vadMinSilenceMs, vadSpeechPadMs;
  final String language;
  final bool translate, detectLanguage, tokenTimestamps, splitOnWord,
      suppressBlank, suppressNonSpeechTokens, singleSegment, noContext,
      noTimestamps, printSpecialTokens, tinyDiarize, debugMode,
      carryInitialPrompt, enableVad;
  final String? initialPrompt, suppressRegex, vadModelPath;
  final double temperature, temperatureIncrement, entropyThreshold,
      timestampTokenThreshold, timestampTokenSumThreshold, maxInitialTimestamp,
      lengthPenalty, logProbabilityThreshold, noSpeechThreshold, beamPatience, vadThreshold,
      vadMaxSpeechSeconds, vadSamplesOverlap;
}

final class WhisperToken {
  const WhisperToken({required this.id, required this.text, required this.start,
    required this.end, required this.probability, required this.logProbability,
    required this.timestampProbability, required this.timestampProbabilitySum,
    required this.dtwTimestamp, required this.voiceLength});
  final int id;
  final String text;
  final Duration start, end;
  final double probability, logProbability;
  final double timestampProbability, timestampProbabilitySum, voiceLength;
  final Duration dtwTimestamp;
  factory WhisperToken.fromJson(Map<String, dynamic> j) => WhisperToken(
    id: j['id'], text: j['text'], start: Duration(milliseconds: j['t0']),
    end: Duration(milliseconds: j['t1']), probability: (j['p'] as num).toDouble(),
    logProbability: (j['plog'] as num).toDouble(),
    timestampProbability: (j['pt'] as num).toDouble(),
    timestampProbabilitySum: (j['ptsum'] as num).toDouble(),
    dtwTimestamp: Duration(milliseconds: j['t_dtw']),
    voiceLength: (j['vlen'] as num).toDouble());
}

final class WhisperSegment {
  const WhisperSegment({required this.text, required this.start, required this.end,
    required this.tokens, required this.noSpeechProbability,
    required this.speakerTurnNext});
  final String text;
  final Duration start, end;
  final List<WhisperToken> tokens;
  final double noSpeechProbability;
  final bool speakerTurnNext;
  factory WhisperSegment.fromJson(Map<String, dynamic> j) => WhisperSegment(
    text: j['text'], start: Duration(milliseconds: j['t0']),
    end: Duration(milliseconds: j['t1']),
    tokens: (j['tokens'] as List).map((e) => WhisperToken.fromJson(e)).toList(),
    noSpeechProbability: (j['no_speech_p'] as num).toDouble(),
    speakerTurnNext: j['speaker_turn_next']);
}

final class WhisperResult {
  const WhisperResult({required this.text, required this.language,
    required this.languageProbability, required this.segments,
    required this.processingTime, required this.systemInfo});
  final String text, language, systemInfo;
  final double languageProbability;
  final List<WhisperSegment> segments;
  final Duration processingTime;
  factory WhisperResult.fromJson(Map<String, dynamic> j) => WhisperResult(
    text: j['text'], language: j['language'],
    languageProbability: (j['language_probability'] as num).toDouble(),
    segments: (j['segments'] as List).map((e) => WhisperSegment.fromJson(e)).toList(),
    processingTime: Duration(microseconds: j['processing_us']),
    systemInfo: j['system_info']);
}

final class VadSegment {
  const VadSegment(this.start, this.end);
  final Duration start, end;
}

final class RecordingChunk {
  const RecordingChunk(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;
}
