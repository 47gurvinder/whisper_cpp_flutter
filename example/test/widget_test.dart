import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';
import 'package:whisper_cpp_flutter_plus_example/diarization_page.dart';
import 'package:whisper_cpp_flutter_plus_example/main.dart';

void main() {
  testWidgets('shows the transcription workflow', (tester) async {
    await tester.pumpWidget(const WhisperExampleApp());

    expect(find.text('Offline speech to text'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.textContaining('complete recording'), findsOneWidget);
    expect(find.textContaining('live text'), findsOneWidget);
    expect(find.text('Voice activity detection'), findsOneWidget);
    expect(find.text('Try local diarization'), findsOneWidget);
    expect(find.textContaining('Filter silence'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('opens the local diarization page', (tester) async {
    await tester.pumpWidget(const WhisperExampleApp());

    await tester.tap(find.text('Try local diarization'));
    await tester.pumpAndSettle();

    expect(find.text('Local diarization'), findsOneWidget);
    expect(find.text('Who spoke when?'), findsOneWidget);
    expect(find.textContaining('two voices'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
  });

  test('builds transcription options for TinyDiarize', () {
    final options = buildDiarizationOptions();

    expect(options.language, 'en');
    expect(options.tokenTimestamps, isTrue);
    expect(options.tinyDiarize, isTrue);
  });

  test('builds transcription options with VAD enabled', () {
    final options = buildExampleTranscribeOptions(
      enableVad: true,
      vadModelPath: '/models/ggml-silero-v6.2.0.bin',
      tokenTimestamps: true,
    );

    expect(options.language, 'en');
    expect(options.tokenTimestamps, isTrue);
    expect(options.enableVad, isTrue);
    expect(options.vadModelPath, '/models/ggml-silero-v6.2.0.bin');
  });

  test('builds transcription options with VAD disabled', () {
    final options = buildExampleTranscribeOptions(
      enableVad: false,
      vadModelPath: '/models/ggml-silero-v6.2.0.bin',
    );

    expect(options, isA<TranscribeOptions>());
    expect(options.enableVad, isFalse);
    expect(options.vadModelPath, isNull);
  });
}
