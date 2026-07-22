import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

void main() {
  group('TranscribeOptions.copyWith', () {
    test('can replace every option', () {
      const original = TranscribeOptions();
      final copied = original.copyWith(
        strategy: WhisperSamplingStrategy.beamSearch,
        threads: 8,
        language: 'fr',
        translate: true,
        detectLanguage: true,
        offsetMs: 1,
        durationMs: 2,
        maxTextContext: 3,
        maxSegmentLength: 4,
        maxTokensPerSegment: 5,
        audioContext: 6,
        tokenTimestamps: false,
        splitOnWord: true,
        suppressBlank: false,
        suppressNonSpeechTokens: true,
        singleSegment: true,
        noContext: false,
        noTimestamps: true,
        printSpecialTokens: true,
        tinyDiarize: true,
        debugMode: true,
        carryInitialPrompt: true,
        initialPrompt: 'prompt',
        suppressRegex: 'regex',
        temperature: .1,
        timestampTokenThreshold: .2,
        timestampTokenSumThreshold: .3,
        maxInitialTimestamp: .4,
        lengthPenalty: .5,
        temperatureIncrement: .6,
        entropyThreshold: .7,
        logProbabilityThreshold: .8,
        noSpeechThreshold: .9,
        greedyBestOf: 7,
        beamSize: 9,
        beamPatience: 1.1,
        enableVad: true,
        vadModelPath: '/vad.bin',
        vadThreshold: 1.2,
        vadMinSpeechMs: 10,
        vadMinSilenceMs: 11,
        vadMaxSpeechSeconds: 1.3,
        vadSpeechPadMs: 12,
        vadSamplesOverlap: 1.4,
      );

      expect(copied.strategy, WhisperSamplingStrategy.beamSearch);
      expect(copied.threads, 8);
      expect(copied.language, 'fr');
      expect(copied.translate, isTrue);
      expect(copied.detectLanguage, isTrue);
      expect(copied.offsetMs, 1);
      expect(copied.durationMs, 2);
      expect(copied.maxTextContext, 3);
      expect(copied.maxSegmentLength, 4);
      expect(copied.maxTokensPerSegment, 5);
      expect(copied.audioContext, 6);
      expect(copied.tokenTimestamps, isFalse);
      expect(copied.splitOnWord, isTrue);
      expect(copied.suppressBlank, isFalse);
      expect(copied.suppressNonSpeechTokens, isTrue);
      expect(copied.singleSegment, isTrue);
      expect(copied.noContext, isFalse);
      expect(copied.noTimestamps, isTrue);
      expect(copied.printSpecialTokens, isTrue);
      expect(copied.tinyDiarize, isTrue);
      expect(copied.debugMode, isTrue);
      expect(copied.carryInitialPrompt, isTrue);
      expect(copied.initialPrompt, 'prompt');
      expect(copied.suppressRegex, 'regex');
      expect(copied.temperature, .1);
      expect(copied.timestampTokenThreshold, .2);
      expect(copied.timestampTokenSumThreshold, .3);
      expect(copied.maxInitialTimestamp, .4);
      expect(copied.lengthPenalty, .5);
      expect(copied.temperatureIncrement, .6);
      expect(copied.entropyThreshold, .7);
      expect(copied.logProbabilityThreshold, .8);
      expect(copied.noSpeechThreshold, .9);
      expect(copied.greedyBestOf, 7);
      expect(copied.beamSize, 9);
      expect(copied.beamPatience, 1.1);
      expect(copied.enableVad, isTrue);
      expect(copied.vadModelPath, '/vad.bin');
      expect(copied.vadThreshold, 1.2);
      expect(copied.vadMinSpeechMs, 10);
      expect(copied.vadMinSilenceMs, 11);
      expect(copied.vadMaxSpeechSeconds, 1.3);
      expect(copied.vadSpeechPadMs, 12);
      expect(copied.vadSamplesOverlap, 1.4);
    });

    test('preserves omitted fields and can clear nullable fields', () {
      const original = TranscribeOptions(
        language: 'de',
        initialPrompt: 'prompt',
        suppressRegex: 'regex',
        vadModelPath: '/vad.bin',
      );

      final unchanged = original.copyWith();
      expect(unchanged.language, 'de');
      expect(unchanged.initialPrompt, 'prompt');
      expect(unchanged.suppressRegex, 'regex');
      expect(unchanged.vadModelPath, '/vad.bin');

      final cleared = original.copyWith(
        initialPrompt: null,
        suppressRegex: null,
        vadModelPath: null,
      );
      expect(cleared.initialPrompt, isNull);
      expect(cleared.suppressRegex, isNull);
      expect(cleared.vadModelPath, isNull);
    });
  });

  group('Whisper performance modes', () {
    const source = TranscribeOptions(
      strategy: WhisperSamplingStrategy.beamSearch,
      threads: 99,
      language: 'es',
      translate: true,
      tokenTimestamps: true,
      noTimestamps: false,
      initialPrompt: 'keep me',
      greedyBestOf: 99,
      beamSize: 12,
      enableVad: true,
      vadThreshold: .75,
    );

    test('responsive applies its controlled fields', () {
      final options =
          source.withPerformanceMode(WhisperPerformanceMode.responsive);
      _expectControlled(options, 4, 1, false, true);
      _expectUnrelatedPreserved(options);
    });

    test('balanced applies its controlled fields', () {
      final options =
          source.withPerformanceMode(WhisperPerformanceMode.balanced);
      _expectControlled(options, 4, 5, true, false);
      _expectUnrelatedPreserved(options);
    });

    test('efficient applies its controlled fields', () {
      final options =
          source.withPerformanceMode(WhisperPerformanceMode.efficient);
      _expectControlled(options, 2, 1, false, true);
      _expectUnrelatedPreserved(options);
    });
  });
}

void _expectControlled(
  TranscribeOptions options,
  int threads,
  int greedyBestOf,
  bool tokenTimestamps,
  bool noTimestamps,
) {
  expect(options.threads, threads);
  expect(options.greedyBestOf, greedyBestOf);
  expect(options.tokenTimestamps, tokenTimestamps);
  expect(options.noTimestamps, noTimestamps);
}

void _expectUnrelatedPreserved(TranscribeOptions options) {
  expect(options.strategy, WhisperSamplingStrategy.beamSearch);
  expect(options.language, 'es');
  expect(options.translate, isTrue);
  expect(options.initialPrompt, 'keep me');
  expect(options.beamSize, 12);
  expect(options.enableVad, isTrue);
  expect(options.vadThreshold, .75);
}
