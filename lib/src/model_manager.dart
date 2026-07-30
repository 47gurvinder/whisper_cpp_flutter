import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'model_catalog.dart';

/// Byte-level progress for a model download.
final class ModelDownloadProgress {
  /// Creates a progress snapshot with downloaded and expected byte counts.
  const ModelDownloadProgress(this.received, this.total);

  /// Bytes received and total expected bytes.
  ///
  /// [total] is zero when the server did not provide a content length.
  final int received, total;

  /// Completion ratio from 0 to 1, or `null` when [total] is unknown.
  double? get fraction => total > 0 ? received / total : null;
}

/// Stores, discovers, downloads, and removes whisper model files.
final class WhisperModelManager {
  /// Creates a manager with optional HTTP and storage dependencies.
  ///
  /// An injected [client] remains owned by the caller and is not closed by
  /// [close]. An injected [storageDirectory] is useful for custom storage and
  /// deterministic tests.
  WhisperModelManager({
    http.Client? client,
    Directory? storageDirectory,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _storageDirectory = storageDirectory;

  final http.Client _client;
  final bool _ownsClient;
  final Directory? _storageDirectory;
  bool _closed = false;

  /// Application-support directory used for managed model files.
  ///
  /// The directory is created on first access.
  Future<Directory> get directory async {
    _ensureOpen();
    final configured = _storageDirectory;
    if (configured != null) {
      await configured.create(recursive: true);
      return configured;
    }
    final base = await getApplicationSupportDirectory();
    final managed = Directory('${base.path}/whisper_models');
    await managed.create(recursive: true);
    return managed;
  }

  /// Lists managed files whose names end in `.bin`.
  Future<List<File>> list() async => (await directory)
      .list()
      .where((e) => e is File && e.path.endsWith('.bin'))
      .cast<File>()
      .toList();

  /// Finds a managed model by [name], or returns `null` when it does not exist.
  Future<File?> find(String name) async {
    _validateName(name);
    final f = File('${(await directory).path}/$name');
    return await f.exists() ? f : null;
  }

  /// Finds [model] only when its cached file matches the catalog SHA-256.
  ///
  /// Returns `null` when the model is not cached. A mismatched cached file
  /// throws [FormatException] and is left in place for caller-directed cleanup.
  Future<File?> findCatalogModel(WhisperModelDescriptor model) async {
    final file = await find(model.fileName);
    if (file == null) return null;
    final actual = await _sha256(file);
    if (actual != model.sha256) {
      throw FormatException(
        'Model SHA-256 mismatch for ${model.fileName}: '
        'expected ${model.sha256}, found $actual',
      );
    }
    return file;
  }

  /// Deletes the managed model named [name].
  ///
  /// The returned future fails with a [FileSystemException] if it is absent or
  /// cannot be removed.
  Future<void> delete(String name) async =>
      File('${(await directory).path}/${_validatedName(name)}').delete();

  /// Downloads a checksum-pinned catalog [model].
  Stream<ModelDownloadProgress> downloadCatalogModel(
    WhisperModelDescriptor model,
  ) =>
      download(
        model.uri,
        model.fileName,
        sha256Hex: model.sha256,
      );

  /// Downloads a model from an HTTP(S) [url] into managed model storage.
  ///
  /// This is a convenience utility. Applications that download models
  /// themselves can pass the resulting local path directly to
  /// `WhisperEngine.load` instead. Existing `.part` files are resumed when the
  /// server supports byte ranges. If [sha256Hex] is supplied, a mismatch throws
  /// a [FormatException] and the final model file is not installed. HTTPS is
  /// required unless [allowInsecureHttp] is explicitly enabled.
  Stream<ModelDownloadProgress> download(
    Uri url,
    String name, {
    String? sha256Hex,
    bool allowInsecureHttp = false,
  }) async* {
    _ensureOpen();
    _validateDownloadUri(url, allowInsecureHttp: allowInsecureHttp);
    _validateName(name);
    if (sha256Hex != null &&
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256Hex)) {
      throw ArgumentError.value(
        sha256Hex,
        'sha256Hex',
        'Must contain exactly 64 hexadecimal characters',
      );
    }
    final dir = await directory;
    final target = File('${dir.path}/$name'),
        partial = File('${dir.path}/$name.part');
    var received = await partial.exists() ? await partial.length() : 0;
    final request = http.Request('GET', url);
    if (received > 0) request.headers['Range'] = 'bytes=$received-';
    final response = await _client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException('Download failed: HTTP ${response.statusCode}');
    }
    if (response.statusCode == 200 && received > 0) {
      await partial.writeAsBytes([]);
      received = 0;
    }
    final total = received + (response.contentLength ?? 0);
    final sink = partial.openWrite(mode: FileMode.append);
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield ModelDownloadProgress(received, total);
      }
    } finally {
      await sink.close();
    }
    if (sha256Hex != null) {
      final actual = await _sha256(partial);
      if (actual.toLowerCase() != sha256Hex.toLowerCase()) {
        await partial.delete();
        throw const FormatException('Model SHA-256 mismatch');
      }
    }
    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
  }

  /// Releases an internally created HTTP client.
  ///
  /// This method is idempotent. Injected clients remain owned by their caller.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }

  Future<String> _sha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString().toLowerCase();

  void _ensureOpen() {
    if (_closed) throw StateError('WhisperModelManager is closed');
  }

  String _validatedName(String name) {
    _validateName(name);
    return name;
  }

  void _validateName(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\u0000')) {
      throw ArgumentError.value(
        name,
        'name',
        'Must be a simple filename without path separators',
      );
    }
  }

  void _validateDownloadUri(
    Uri url, {
    required bool allowInsecureHttp,
  }) {
    if (!url.hasScheme || url.host.isEmpty) {
      throw ArgumentError.value(url, 'url', 'Must be an absolute HTTP(S) URL');
    }
    if (url.scheme == 'https') return;
    if (url.scheme == 'http' && allowInsecureHttp) return;
    throw ArgumentError.value(
      url,
      'url',
      url.scheme == 'http'
          ? 'HTTP requires allowInsecureHttp: true'
          : 'Only HTTP(S) model URLs are supported',
    );
  }
}
