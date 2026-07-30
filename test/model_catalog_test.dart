import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

void main() {
  test('catalog descriptors are unique, pinned, and internally valid', () {
    final ids = <String>{};
    final names = <String>{};
    for (final model in WhisperModelCatalog.values) {
      expect(ids.add(model.id), isTrue);
      expect(names.add(model.fileName), isTrue);
      expect(model.uri.scheme, 'https');
      expect(model.uri.path, isNot(contains('/resolve/main/')));
      expect(model.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(model.approximateBytes, greaterThan(0));
    }
    expect(WhisperModelCatalog.values, hasLength(6));
    expect(
      WhisperModelCatalog.byId('tiny.en'),
      same(WhisperModelCatalog.tinyEnglish),
    );
    expect(WhisperModelCatalog.byId('missing'), isNull);
  });

  test('findCatalogModel verifies cached files', () async {
    final directory = await Directory.systemTemp.createTemp('whisper-model-');
    addTearDown(() => directory.delete(recursive: true));
    final bytes = [1, 2, 3, 4];
    final descriptor = _descriptor(
      fileName: 'verified.bin',
      sha256Hex: sha256.convert(bytes).toString(),
    );
    await File('${directory.path}/${descriptor.fileName}').writeAsBytes(bytes);
    final manager = WhisperModelManager(storageDirectory: directory);

    expect(await manager.findCatalogModel(descriptor), isA<File>());

    final invalid = _descriptor(
      fileName: descriptor.fileName,
      sha256Hex: _zeroHash,
    );
    await expectLater(
      manager.findCatalogModel(invalid),
      throwsA(isA<FormatException>()),
    );
  });

  test('downloads, verifies, and installs a catalog model', () async {
    final directory = await Directory.systemTemp.createTemp('whisper-model-');
    addTearDown(() => directory.delete(recursive: true));
    final bytes = [5, 6, 7];
    final client = _TrackingClient((request) async {
      expect(request.url, Uri.parse('https://example.com/model.bin'));
      return http.StreamedResponse(
        Stream.value(bytes),
        200,
        contentLength: bytes.length,
      );
    });
    final descriptor = _descriptor(
      sha256Hex: sha256.convert(bytes).toString(),
    );
    final manager = WhisperModelManager(
      client: client,
      storageDirectory: directory,
    );

    final progress = await manager.downloadCatalogModel(descriptor).toList();
    expect(progress.last.received, bytes.length);
    expect(
      await File('${directory.path}/model.bin').readAsBytes(),
      bytes,
    );
    expect(await manager.findCatalogModel(descriptor), isNotNull);
  });

  test('resumes partial downloads with a byte range', () async {
    final directory = await Directory.systemTemp.createTemp('whisper-model-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/model.bin.part').writeAsBytes([1, 2]);
    final allBytes = [1, 2, 3, 4];
    final client = _TrackingClient((request) async {
      expect(request.headers['Range'], 'bytes=2-');
      return http.StreamedResponse(
        Stream.value([3, 4]),
        206,
        contentLength: 2,
      );
    });
    final manager = WhisperModelManager(
      client: client,
      storageDirectory: directory,
    );

    final progress = await manager
        .download(
          Uri.parse('https://example.com/model.bin'),
          'model.bin',
          sha256Hex: sha256.convert(allBytes).toString(),
        )
        .toList();

    expect(progress.last.total, 4);
    expect(await File('${directory.path}/model.bin').readAsBytes(), allBytes);
  });

  test('checksum failure installs nothing and removes the bad partial',
      () async {
    final directory = await Directory.systemTemp.createTemp('whisper-model-');
    addTearDown(() => directory.delete(recursive: true));
    final client = _TrackingClient(
      (_) async => http.StreamedResponse(
        Stream.value([1, 2, 3]),
        200,
        contentLength: 3,
      ),
    );
    final manager = WhisperModelManager(
      client: client,
      storageDirectory: directory,
    );

    await expectLater(
      manager
          .download(
            Uri.parse('https://example.com/model.bin'),
            'model.bin',
            sha256Hex: _zeroHash,
          )
          .drain<void>(),
      throwsA(isA<FormatException>()),
    );
    expect(await File('${directory.path}/model.bin').exists(), isFalse);
    expect(await File('${directory.path}/model.bin.part').exists(), isFalse);
  });

  test('rejects traversal, invalid hashes, and insecure URLs by default',
      () async {
    final directory = await Directory.systemTemp.createTemp('whisper-model-');
    addTearDown(() => directory.delete(recursive: true));
    final client = _TrackingClient(
      (_) async => http.StreamedResponse(Stream.value([1]), 200),
    );
    final manager = WhisperModelManager(
      client: client,
      storageDirectory: directory,
    );

    await expectLater(manager.find('../model.bin'), throwsArgumentError);
    await expectLater(
      manager
          .download(
            Uri.parse('https://example.com/model.bin'),
            r'folder\model.bin',
          )
          .drain<void>(),
      throwsArgumentError,
    );
    await expectLater(
      manager
          .download(
            Uri.parse('https://example.com/model.bin'),
            'model.bin',
            sha256Hex: 'invalid',
          )
          .drain<void>(),
      throwsArgumentError,
    );
    await expectLater(
      manager
          .download(
            Uri.parse('http://example.com/model.bin'),
            'model.bin',
          )
          .drain<void>(),
      throwsArgumentError,
    );
  });

  test('allows explicit HTTP opt-in and preserves injected client ownership',
      () async {
    final directory = await Directory.systemTemp.createTemp('whisper-model-');
    addTearDown(() => directory.delete(recursive: true));
    final client = _TrackingClient(
      (_) async => http.StreamedResponse(
        Stream.value([1]),
        200,
        contentLength: 1,
      ),
    );
    final manager = WhisperModelManager(
      client: client,
      storageDirectory: directory,
    );

    await manager
        .download(
          Uri.parse('http://example.com/model.bin'),
          'model.bin',
          allowInsecureHttp: true,
        )
        .drain<void>();
    manager.close();
    manager.close();

    expect(client.wasClosed, isFalse);
    await expectLater(manager.find('model.bin'), throwsStateError);
    client.close();
    expect(client.wasClosed, isTrue);
  });
}

const _zeroHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

WhisperModelDescriptor _descriptor({
  String fileName = 'model.bin',
  required String sha256Hex,
}) =>
    WhisperModelDescriptor(
      id: 'test',
      fileName: fileName,
      url: 'https://example.com/model.bin',
      sha256: sha256Hex,
      approximateBytes: 3,
      languageScope: WhisperModelLanguageScope.english,
      purpose: WhisperModelPurpose.transcription,
    );

final class _TrackingClient extends http.BaseClient {
  _TrackingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;
  bool wasClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);

  @override
  void close() {
    wasClosed = true;
  }
}
