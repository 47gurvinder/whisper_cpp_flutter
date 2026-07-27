import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
  /// Creates a manager, optionally using an injected HTTP [client].
  WhisperModelManager({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  /// Application-support directory used for managed model files.
  ///
  /// The directory is created on first access.
  Future<Directory> get directory async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/whisper_models')
      ..createSync(recursive: true);
  }

  /// Lists managed files whose names end in `.bin`.
  Future<List<File>> list() async => (await directory)
      .list()
      .where((e) => e is File && e.path.endsWith('.bin'))
      .cast<File>()
      .toList();

  /// Finds a managed model by [name], or returns `null` when it does not exist.
  Future<File?> find(String name) async {
    final f = File('${(await directory).path}/$name');
    return await f.exists() ? f : null;
  }

  /// Deletes the managed model named [name].
  ///
  /// The returned future fails with a [FileSystemException] if it is absent or
  /// cannot be removed.
  Future<void> delete(String name) async =>
      File('${(await directory).path}/$name').delete();

  /// Downloads a model from any HTTP(S) [url] into managed model storage.
  ///
  /// This is a convenience utility. Applications that download models
  /// themselves can pass the resulting local path directly to
  /// `WhisperEngine.load` instead. Existing `.part` files are resumed when the
  /// server supports byte ranges. If [sha256Hex] is supplied, a mismatch throws
  /// a [FormatException] and the final model file is not installed.
  Stream<ModelDownloadProgress> download(Uri url, String name,
      {String? sha256Hex}) async* {
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
      final actual = (await sha256.bind(partial.openRead()).first).toString();
      if (actual.toLowerCase() != sha256Hex.toLowerCase()) {
        throw const FormatException('Model SHA-256 mismatch');
      }
    }
    await partial.rename(target.path);
  }
}
