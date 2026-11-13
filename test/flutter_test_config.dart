import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// Widget tests exercise cover layout without native disk/network plugins.
class _TestImageCache implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CachedNetworkImageProvider.defaultCacheManager = _TestImageCache();
  await testMain();
}
