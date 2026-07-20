import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_example/main.dart';

void main() {
  testWidgets('shows the transcription workflow', (tester) async {
    await tester.pumpWidget(const WhisperExampleApp());

    expect(find.text('Offline speech to text'), findsOneWidget);
    expect(find.text('Transcript'), findsOneWidget);
  });
}
