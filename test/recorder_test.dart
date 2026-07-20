import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('whisper_cpp_flutter/recorder');
  const audio = MethodChannel('whisper_cpp_flutter/audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(audio, null);
  });

  test('reports permission denial', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      expect(call.method, 'requestPermission');
      return false;
    });

    expect(await WhisperRecorder().requestPermission(), isFalse);
  });

  test('enforces one active microphone and cleans up on stop', () async {
    final methodCalls = <String>[];
    messenger.setMockMethodCallHandler(methods, (call) async {
      methodCalls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(audio, (call) async => null);

    final first = WhisperRecorder();
    final second = WhisperRecorder();
    await first.start(sampleRate: 16000, chunkMilliseconds: 80);
    await expectLater(second.start(), throwsStateError);
    await first.stop();

    expect(methodCalls, ['start', 'stop']);
    await second.start();
    await second.stop();
  });

  test('validates capture settings before invoking the platform', () async {
    final recorder = WhisperRecorder();
    await expectLater(recorder.start(sampleRate: 0), throwsArgumentError);
    await expectLater(
      recorder.start(chunkMilliseconds: 0),
      throwsArgumentError,
    );
  });
}
