import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reading_tracker/services/cover_cache_io.dart';

void main() {
  test(
    'expired cover survives manager restart and failed offline refresh',
    () async {
      final directory = await Directory.systemTemp.createTemp('cover-cache-');
      CacheManager? manager;
      var online = true;
      var downloads = 0;
      final client = MockClient((request) async {
        downloads++;
        if (!online) throw http.ClientException('Offline');
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png', 'cache-control': 'no-cache'},
        );
      });
      CacheManager open() => createPersistentCoverCache(
        '${directory.path}/covers',
        repository: JsonCacheInfoRepository.withFile(
          File('${directory.path}/metadata.json'),
        ),
        fileService: HttpFileService(httpClient: client),
      );
      try {
        const url = 'https://example.com/cover.png';
        manager = open();
        final initial = await manager.downloadFile(url);
        expect(
          initial.file.parent.uri,
          Directory('${directory.path}/covers').uri,
        );
        expect(await initial.file.readAsBytes(), [1, 2, 3]);
        await manager.dispose();
        manager = null;
        online = false;
        manager = open();
        final cached = (await manager.getFileStream(url).toList())
            .whereType<FileInfo>()
            .single;
        expect(cached.source, FileSource.Cache);
        expect(await cached.file.readAsBytes(), [1, 2, 3]);
        expect(
          downloads,
          2,
          reason: 'The failed refresh must retain the stale cover.',
        );
        await expectLater(
          manager.getFileStream('https://example.com/unseen.png').toList(),
          throwsA(isA<http.ClientException>()),
        );
        await manager.removeFile(url);
        expect(await manager.getFileFromCache(url), isNull);
      } finally {
        await manager?.dispose();
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
