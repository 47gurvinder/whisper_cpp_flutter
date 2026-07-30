import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

void main() {
  test('rejects empty and duplicate item IDs before starting', () {
    expect(
      () => WhisperPcmBatchInput('', Float32List(1)),
      throwsArgumentError,
    );
    expect(
      () => WhisperBatchTask.start(
        inputs: [
          WhisperPcmBatchInput('same', Float32List(1)),
          WhisperPcmBatchInput('same', Float32List(1)),
        ],
        startInference: (_, __) async => _result('unused'),
        releaseEngine: () {},
      ),
      throwsArgumentError,
    );
  });

  test('processes strictly in order and only one inference at a time',
      () async {
    final inputs = List.generate(
      3,
      (index) => WhisperPcmBatchInput(
        'item-$index',
        Float32List(1)..[0] = index.toDouble(),
      ),
    );
    final started = <int>[];
    final gates = List.generate(3, (_) => Completer<WhisperResult>());
    var active = 0;
    var maximumActive = 0;
    var released = 0;
    final task = WhisperBatchTask.start(
      inputs: inputs,
      startInference: (samples, _) {
        final index = samples.single.toInt();
        started.add(index);
        active++;
        if (active > maximumActive) maximumActive = active;
        return gates[index].future.whenComplete(() => active--);
      },
      releaseEngine: () => released++,
    );
    final updates = <WhisperBatchProgress>[];
    task.updates.listen(updates.add);

    await _waitFor(() => started.length == 1);
    expect(started, [0]);
    gates[0].complete(_result('zero'));
    await _waitFor(() => started.length == 2);
    expect(started, [0, 1]);
    gates[1].complete(_result('one'));
    await _waitFor(() => started.length == 3);
    gates[2].complete(_result('two'));

    final results = await task.result;
    expect(results.map((item) => item.input.id), [
      'item-0',
      'item-1',
      'item-2',
    ]);
    expect(results.map((item) => item.result?.text), ['zero', 'one', 'two']);
    expect(maximumActive, 1);
    expect(updates.map((update) => update.completed), [1, 2, 3]);
    expect(updates.last.isFinal, isTrue);
    expect(released, 1);
  });

  test('uses item options over batch defaults', () async {
    const defaults = TranscribeOptions(language: 'en', threads: 2);
    const override = TranscribeOptions(language: 'fr', threads: 3);
    final seen = <TranscribeOptions>[];
    final task = WhisperBatchTask.start(
      inputs: [
        WhisperPcmBatchInput('default', Float32List(1)),
        WhisperPcmBatchInput('override', Float32List(1), options: override),
      ],
      defaultOptions: defaults,
      startInference: (_, options) async {
        seen.add(options);
        return _result('ok');
      },
      releaseEngine: () {},
    );

    await task.result;
    expect(seen[0], same(defaults));
    expect(seen[1], same(override));
  });

  test('passes PCM through and decodes WAV inputs', () async {
    final directory = await Directory.systemTemp.createTemp('whisper-batch-');
    addTearDown(() => directory.delete(recursive: true));
    final wav = File('${directory.path}/sample.wav');
    await wav.writeAsBytes(_wav16([0, 16384, -16384]));
    final pcm = Float32List.fromList([.25, -.25]);
    final lengths = <int>[];
    final values = <double>[];
    final task = WhisperBatchTask.start(
      inputs: [
        WhisperPcmBatchInput('pcm', pcm),
        WhisperWavBatchInput('wav', wav),
      ],
      startInference: (samples, _) async {
        lengths.add(samples.length);
        values.add(samples.length > 1 ? samples[1] : 0);
        return _result('ok');
      },
      releaseEngine: () {},
    );

    await task.result;
    expect(lengths, [2, 3]);
    expect(values[0], -.25);
    expect(values[1], closeTo(.5, .0001));
  });

  test('stops on the first error by default and always releases', () async {
    var calls = 0;
    var releases = 0;
    final task = WhisperBatchTask.start(
      inputs: [
        WhisperPcmBatchInput('bad', Float32List(1)),
        WhisperPcmBatchInput('never', Float32List(1)),
      ],
      startInference: (_, __) async {
        calls++;
        throw StateError('failed');
      },
      releaseEngine: () => releases++,
    );

    await expectLater(task.result, throwsStateError);
    expect(calls, 1);
    expect(releases, 1);
  });

  test('captures errors and continues when requested', () async {
    var calls = 0;
    final task = WhisperBatchTask.start(
      inputs: [
        WhisperPcmBatchInput('bad', Float32List(1)),
        WhisperPcmBatchInput('good', Float32List(1)),
      ],
      continueOnError: true,
      startInference: (_, __) async {
        calls++;
        if (calls == 1) throw FormatException('bad input');
        return _result('good');
      },
      releaseEngine: () {},
    );

    final results = await task.result;
    expect(results, hasLength(2));
    expect(results.first.isSuccess, isFalse);
    expect(results.first.error, isA<FormatException>());
    expect(results.last.result?.text, 'good');
  });

  test('cancels active inference, stops the batch, and releases once',
      () async {
    final pending = Completer<WhisperResult>();
    var cancellations = 0;
    var releases = 0;
    final task = WhisperBatchTask.start(
      inputs: [
        WhisperPcmBatchInput('active', Float32List(1)),
        WhisperPcmBatchInput('never', Float32List(1)),
      ],
      startInference: (_, __) => pending.future,
      cancelInference: () {
        cancellations++;
        pending.completeError(const WhisperException('native cancelled'));
      },
      releaseEngine: () => releases++,
    );
    await Future<void>.delayed(Duration.zero);

    await task.cancel();
    await task.cancel();
    await expectLater(task.result, throwsA(isA<WhisperException>()));
    expect(cancellations, 1);
    expect(releases, 1);
  });

  test('empty batches complete with a terminal progress update', () async {
    var released = false;
    final task = WhisperBatchTask.start(
      inputs: const [],
      startInference: (_, __) async => _result('unused'),
      releaseEngine: () => released = true,
    );

    final updates = await task.updates.toList();
    expect(await task.result, isEmpty);
    expect(updates, hasLength(1));
    expect(updates.single.fraction, 1);
    expect(updates.single.isFinal, isTrue);
    expect(released, isTrue);
  });
}

WhisperResult _result(String text) => WhisperResult(
      text: text,
      language: 'en',
      languageProbability: 1,
      segments: const [],
      processingTime: Duration.zero,
      systemInfo: 'test',
    );

Uint8List _wav16(List<int> samples) {
  final bytes = Uint8List(44 + samples.length * 2);
  final data = ByteData.sublistView(bytes);
  void ascii(int offset, String value) {
    bytes.setRange(offset, offset + value.length, value.codeUnits);
  }

  ascii(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    data.setInt16(44 + index * 2, samples[index], Endian.little);
  }
  return bytes;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not reached before timeout');
}
