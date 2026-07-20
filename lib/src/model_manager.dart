import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

final class ModelDownloadProgress {
  const ModelDownloadProgress(this.received, this.total);
  final int received, total;
  double? get fraction => total > 0 ? received / total : null;
}

final class WhisperModelManager {
  WhisperModelManager({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  Future<Directory> get directory async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/whisper_models')..createSync(recursive: true);
  }
  Future<List<File>> list() async => (await directory).list()
      .where((e) => e is File && e.path.endsWith('.bin')).cast<File>().toList();
  Future<File?> find(String name) async { final f=File('${(await directory).path}/$name'); return await f.exists()?f:null; }
  Future<void> delete(String name) async => File('${(await directory).path}/$name').delete();

  Stream<ModelDownloadProgress> download(Uri url, String name,
      {String? sha256Hex}) async* {
    final dir = await directory;
    final target = File('${dir.path}/$name'), partial = File('${dir.path}/$name.part');
    var received = await partial.exists() ? await partial.length() : 0;
    final request = http.Request('GET', url);
    if (received > 0) request.headers['Range'] = 'bytes=$received-';
    final response = await _client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException('Download failed: HTTP ${response.statusCode}');
    }
    if (response.statusCode == 200 && received > 0) { await partial.writeAsBytes([]); received=0; }
    final total = received + (response.contentLength ?? 0);
    final sink = partial.openWrite(mode: FileMode.append);
    try { await for (final chunk in response.stream) { sink.add(chunk); received += chunk.length; yield ModelDownloadProgress(received,total); } }
    finally { await sink.close(); }
    if (sha256Hex != null) {
      final actual = (await sha256.bind(partial.openRead()).first).toString();
      if (actual.toLowerCase() != sha256Hex.toLowerCase()) throw const FormatException('Model SHA-256 mismatch');
    }
    await partial.rename(target.path);
  }
}
