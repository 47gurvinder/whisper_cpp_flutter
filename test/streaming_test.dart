import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

void main() {
  group('WhisperStreamConfig', () {
    test('validates timing relationships', () {
      expect(
        () =>
            const WhisperStreamConfig(updateInterval: Duration.zero).validate(),
        throwsArgumentError,
      );
      expect(
        () => const WhisperStreamConfig(
          updateInterval: Duration(seconds: 2),
          windowDuration: Duration(seconds: 2),
        ).validate(),
        throwsArgumentError,
      );
      expect(
        () => const WhisperStreamConfig(
          windowDuration: Duration(seconds: 2),
          confirmationLag: Duration(seconds: 2),
        ).validate(),
        throwsArgumentError,
      );
    });
  });

  test('emits append-only confirmed text and a revisable partial tail',
      () async {
    final audio = StreamController<RecordingChunk>(sync: true);
    final calls = <int>[];
    var released = false;
    final task = WhisperStreamTask.start(
      audio: audio.stream,
      config: const WhisperStreamConfig(
        updateInterval: Duration(milliseconds: 100),
        windowDuration: Duration(seconds: 2),
        confirmationLag: Duration(milliseconds: 50),
      ),
      startInference: (samples, _) async {
        calls.add(samples.length);
        if (calls.length == 1) {
          return _result([_segment(' hello', 0, 40)]);
        }
        return _result([
          _segment(' hello', 0, 40),
          _segment(' world', 100, 180),
        ]);
      },
      releaseEngine: () => released = true,
    );
    final updates = <WhisperStreamUpdate>[];
    final subscription = task.updates.listen(updates.add);

    audio.add(RecordingChunk(Float32List(1600), 16000));
    await _waitFor(() => updates.length == 1);
    expect(updates.single.confirmedText, isEmpty);
    expect(updates.single.partialText, ' hello');

    audio.add(RecordingChunk(Float32List(1600), 16000));
    await _waitFor(() => updates.length == 2);
    expect(updates.last.confirmedText, ' hello');
    expect(updates.last.partialText, ' world');

    final complete = await task.stop();
    expect(complete.isFinal, isTrue);
    expect(complete.confirmedText, ' hello world');
    expect(complete.partialText, isEmpty);
    expect(complete.confirmedSegments.map((s) => s.start.inMilliseconds),
        [0, 100]);
    expect(released, isTrue);
    await subscription.cancel();
    await audio.close();
  });

  test('coalesces inference triggers while preserving buffered audio',
      () async {
    final audio = StreamController<RecordingChunk>(sync: true);
    final firstInference = Completer<WhisperResult>();
    final lengths = <int>[];
    final task = WhisperStreamTask.start(
      audio: audio.stream,
      config: const WhisperStreamConfig(
        updateInterval: Duration(milliseconds: 100),
        windowDuration: Duration(seconds: 2),
        confirmationLag: Duration(milliseconds: 50),
      ),
      startInference: (samples, _) {
        lengths.add(samples.length);
        return lengths.length == 1
            ? firstInference.future
            : Future.value(_result(const []));
      },
      releaseEngine: () {},
    );
    task.updates.listen((_) {});

    audio.add(RecordingChunk(Float32List(1600), 16000));
    await _waitFor(() => lengths.length == 1);
    audio.add(RecordingChunk(Float32List(1600), 16000));
    audio.add(RecordingChunk(Float32List(1600), 16000));
    audio.add(RecordingChunk(Float32List(1600), 16000));
    expect(lengths, [1600]);

    firstInference.complete(_result(const []));
    await _waitFor(() => lengths.length == 2);
    expect(lengths[1], 6400);
    await task.stop();
    await audio.close();
  });

  test('advances full silent windows instead of pinning the audio buffer',
      () async {
    final audio = StreamController<RecordingChunk>(sync: true);
    final windowStarts = <int>[];
    var processedSamples = 0;
    final task = WhisperStreamTask.start(
      audio: audio.stream,
      config: const WhisperStreamConfig(
        updateInterval: Duration(milliseconds: 100),
        windowDuration: Duration(milliseconds: 300),
        confirmationLag: Duration(milliseconds: 100),
      ),
      startInference: (samples, _) async {
        windowStarts.add(processedSamples);
        processedSamples += samples.length - 1600;
        return _result(const []);
      },
      releaseEngine: () {},
    );
    task.updates.listen((_) {});

    audio.add(RecordingChunk(Float32List(12800), 16000));
    await _waitFor(() => windowStarts.length >= 3);
    final complete = await task.stop();
    expect(complete.audioDuration, const Duration(milliseconds: 800));
    expect(windowStarts.length, greaterThanOrEqualTo(3));
    await audio.close();
  });

  test('rebases timestamps and removes overlap across rolling windows',
      () async {
    final audio = StreamController<RecordingChunk>(sync: true);
    var calls = 0;
    final task = WhisperStreamTask.start(
      audio: audio.stream,
      config: const WhisperStreamConfig(
        updateInterval: Duration(milliseconds: 100),
        windowDuration: Duration(milliseconds: 300),
        confirmationLag: Duration(milliseconds: 100),
      ),
      startInference: (_, __) async {
        calls++;
        final chunk = calls > 4 ? 4 : calls;
        return _result([_segment(' chunk$chunk', 0, 50)]);
      },
      releaseEngine: () {},
    );
    task.updates.listen((_) {});

    audio.add(RecordingChunk(Float32List(12800), 16000));
    await _waitFor(() => calls >= 4);
    final complete = await task.stop();
    expect(complete.confirmedText, ' chunk1 chunk2 chunk3 chunk4');
    expect(
      complete.confirmedSegments.map((segment) => segment.start.inMilliseconds),
      [0, 200, 400, 600],
    );
    await audio.close();
  });

  test('resamples continuously and rejects a sample-rate change', () async {
    final resampleAudio = StreamController<RecordingChunk>(sync: true);
    var inferenceLength = 0;
    final resampleTask = WhisperStreamTask.start(
      audio: resampleAudio.stream,
      config: const WhisperStreamConfig(
        updateInterval: Duration(seconds: 1),
        windowDuration: Duration(seconds: 2),
        confirmationLag: Duration(seconds: 1),
      ),
      startInference: (samples, _) async {
        inferenceLength = samples.length;
        return _result(const []);
      },
      releaseEngine: () {},
    );
    resampleAudio.add(RecordingChunk(Float32List(800), 8000));
    final complete = await resampleTask.stop();
    expect(inferenceLength, closeTo(1600, 2));
    expect(complete.audioDuration.inMilliseconds, closeTo(100, 1));
    await resampleAudio.close();

    final invalidAudio = StreamController<RecordingChunk>(sync: true);
    var released = false;
    final invalidTask = WhisperStreamTask.start(
      audio: invalidAudio.stream,
      config: const WhisperStreamConfig(),
      startInference: (_, __) async => _result(const []),
      releaseEngine: () => released = true,
    );
    invalidTask.updates.listen((_) {}, onError: (_) {});
    invalidAudio.add(RecordingChunk(Float32List(8), 8000));
    invalidAudio.add(RecordingChunk(Float32List(8), 16000));
    await expectLater(invalidTask.result, throwsA(isA<FormatException>()));
    expect(released, isTrue);
    await invalidAudio.close();
  });

  test('cancel aborts active inference, releases once, and is idempotent',
      () async {
    final audio = StreamController<RecordingChunk>(sync: true);
    final pending = Completer<WhisperResult>();
    var cancellations = 0;
    var releases = 0;
    final task = WhisperStreamTask.start(
      audio: audio.stream,
      config: const WhisperStreamConfig(
        updateInterval: Duration(milliseconds: 100),
        windowDuration: Duration(seconds: 2),
        confirmationLag: Duration(milliseconds: 100),
      ),
      startInference: (_, __) => pending.future,
      cancelInference: () => cancellations++,
      releaseEngine: () => releases++,
    );
    task.updates.listen((_) {}, onError: (_) {});
    audio.add(RecordingChunk(Float32List(1600), 16000));
    await Future<void>.delayed(Duration.zero);

    await task.cancel();
    await task.cancel();
    await expectLater(task.result, throwsA(isA<WhisperException>()));
    expect(cancellations, 1);
    expect(releases, 1);
    await audio.close();
  });
}

WhisperResult _result(List<WhisperSegment> segments) => WhisperResult(
      text: segments.map((segment) => segment.text).join(),
      language: 'en',
      languageProbability: 1,
      segments: segments,
      processingTime: Duration.zero,
      systemInfo: 'test',
    );

WhisperSegment _segment(String text, int startMs, int endMs) => WhisperSegment(
      text: text,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      tokens: const [],
      noSpeechProbability: 0,
      speakerTurnNext: false,
    );

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not reached before timeout');
}
