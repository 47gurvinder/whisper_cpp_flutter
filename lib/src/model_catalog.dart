/// Language coverage of a catalog model.
enum WhisperModelLanguageScope {
  /// English-only speech recognition.
  english,

  /// Multilingual speech recognition and translation.
  multilingual,

  /// Not a speech-recognition language model.
  notApplicable,
}

/// Intended use of a catalog model.
enum WhisperModelPurpose {
  /// General speech recognition and translation.
  transcription,

  /// Voice activity detection.
  voiceActivityDetection,

  /// Experimental TinyDiarize speaker-turn detection.
  speakerTurnDetection,
}

/// Immutable metadata for a checksum-pinned downloadable model.
final class WhisperModelDescriptor {
  /// Creates a verified catalog descriptor.
  const WhisperModelDescriptor({
    required this.id,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.approximateBytes,
    required this.languageScope,
    required this.purpose,
  });

  /// Stable package-level identifier.
  final String id;

  /// Filename used in managed model storage.
  final String fileName;

  /// Immutable upstream download URL pinned to a repository revision.
  final String url;

  /// Lowercase SHA-256 digest of the complete model file.
  final String sha256;

  /// Upstream file size in bytes.
  final int approximateBytes;

  /// Languages covered by this model.
  final WhisperModelLanguageScope languageScope;

  /// Intended inference purpose.
  final WhisperModelPurpose purpose;

  /// Parsed form of [url].
  Uri get uri => Uri.parse(url);
}

/// Curated models suitable for common mobile speech workflows.
///
/// Metadata was resolved from Hugging Face Git LFS on 2026-07-30. URLs are
/// pinned to immutable repository revisions and every descriptor includes the
/// corresponding LFS SHA-256 object identifier.
abstract final class WhisperModelCatalog {
  static const _whisperRevision = '5359861c739e955e79d9a303bcbc70fb988958b1';
  static const _vadRevision = '9ffd54a1e1ee413ddf265af9913beaf518d1639b';
  static const _tinyDiarizeRevision =
      'd44ba793fc67e509623a88a409723311fa677744';

  /// Tiny English-only Whisper model.
  static const tinyEnglish = WhisperModelDescriptor(
    id: 'tiny.en',
    fileName: 'ggml-tiny.en.bin',
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
        '$_whisperRevision/ggml-tiny.en.bin',
    sha256: '921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f',
    approximateBytes: 77704715,
    languageScope: WhisperModelLanguageScope.english,
    purpose: WhisperModelPurpose.transcription,
  );

  /// Tiny multilingual Whisper model.
  static const tiny = WhisperModelDescriptor(
    id: 'tiny',
    fileName: 'ggml-tiny.bin',
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
        '$_whisperRevision/ggml-tiny.bin',
    sha256: 'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
    approximateBytes: 77691713,
    languageScope: WhisperModelLanguageScope.multilingual,
    purpose: WhisperModelPurpose.transcription,
  );

  /// Base English-only Whisper model.
  static const baseEnglish = WhisperModelDescriptor(
    id: 'base.en',
    fileName: 'ggml-base.en.bin',
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
        '$_whisperRevision/ggml-base.en.bin',
    sha256: 'a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002',
    approximateBytes: 147964211,
    languageScope: WhisperModelLanguageScope.english,
    purpose: WhisperModelPurpose.transcription,
  );

  /// Base multilingual Whisper model.
  static const base = WhisperModelDescriptor(
    id: 'base',
    fileName: 'ggml-base.bin',
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
        '$_whisperRevision/ggml-base.bin',
    sha256: '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
    approximateBytes: 147951465,
    languageScope: WhisperModelLanguageScope.multilingual,
    purpose: WhisperModelPurpose.transcription,
  );

  /// Silero v6.2.0 voice activity detection model.
  static const sileroVad = WhisperModelDescriptor(
    id: 'silero-v6.2.0',
    fileName: 'ggml-silero-v6.2.0.bin',
    url: 'https://huggingface.co/ggml-org/whisper-vad/resolve/'
        '$_vadRevision/ggml-silero-v6.2.0.bin',
    sha256: '2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987',
    approximateBytes: 885098,
    languageScope: WhisperModelLanguageScope.notApplicable,
    purpose: WhisperModelPurpose.voiceActivityDetection,
  );

  /// English TinyDiarize model for experimental speaker-turn detection.
  static const tinyDiarize = WhisperModelDescriptor(
    id: 'small.en-tdrz',
    fileName: 'ggml-small.en-tdrz.bin',
    url: 'https://huggingface.co/akashmjn/tinydiarize-whisper.cpp/resolve/'
        '$_tinyDiarizeRevision/ggml-small.en-tdrz.bin',
    sha256: 'ceac3ec06d1d98ef71aec665283564631055fd6129b79d8e1be4f9cc33cc54b4',
    approximateBytes: 487614184,
    languageScope: WhisperModelLanguageScope.english,
    purpose: WhisperModelPurpose.speakerTurnDetection,
  );

  /// All curated descriptors in stable display order.
  static const values = <WhisperModelDescriptor>[
    tinyEnglish,
    tiny,
    baseEnglish,
    base,
    sileroVad,
    tinyDiarize,
  ];

  /// Looks up a descriptor by stable [id].
  static WhisperModelDescriptor? byId(String id) {
    for (final descriptor in values) {
      if (descriptor.id == id) return descriptor;
    }
    return null;
  }
}
