import 'package:flutter_test/flutter_test.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

void main() {
  group('WhisperConfig', () {
    test('defaults to automatic native acceleration', () {
      const config = WhisperConfig();

      expect(config.backend, WhisperBackend.automatic);
      expect(config.coreMlMode, WhisperCoreMlMode.automatic);
      expect(config.useFlashAttention, isTrue);
    });

    test('supports explicit backend and Core ML policies', () {
      const config = WhisperConfig(
        backend: WhisperBackend.metal,
        coreMlMode: WhisperCoreMlMode.required,
      );

      expect(config.backend, WhisperBackend.metal);
      expect(config.coreMlMode, WhisperCoreMlMode.required);
    });

    test('maps the legacy disabled GPU option to CPU', () {
      // ignore: deprecated_member_use_from_same_package
      const config = WhisperConfig(useGpu: false);

      expect(config.backend, WhisperBackend.cpu);
    });
  });
}
