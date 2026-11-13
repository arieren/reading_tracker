import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reading_tracker/services/cover_cache_io.dart';
import 'package:reading_tracker/widgets/book_cover.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native cover renders offline after disk cache reopens', (
    tester,
  ) async {
    expect(appFlavor, 'staging');
    final asset = await rootBundle.load('assets/google_logo.png');
    final png = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = 'http://127.0.0.1:${server.port}/cover.png';
    server.listen((request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.response.add(png);
      await request.response.close();
    });
    final previous = CachedNetworkImageProvider.defaultCacheManager;
    var manager = await createCoverCache();
    Future<void> showCover() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookCover(
              imageUrl: url,
              type: 'Manga',
              width: 100,
              height: 150,
            ),
          ),
        ),
      );
      bool loaded() => tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null);
      for (var attempt = 0; attempt < 100 && !loaded(); attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      expect(loaded(), isTrue);
    }

    try {
      CachedNetworkImageProvider.defaultCacheManager = manager;
      await showCover();
      expect(await manager.getFileFromCache(url), isNotNull);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await server.close(force: true);
      await manager.dispose();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      manager = await createCoverCache();
      CachedNetworkImageProvider.defaultCacheManager = manager;
      await showCover();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await server.close(force: true);
      await manager.removeFile(url);
      await manager.dispose();
      CachedNetworkImageProvider.defaultCacheManager = previous;
    }
  });
}
