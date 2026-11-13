import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'cover_cache_stub.dart'
    if (dart.library.io) 'cover_cache_io.dart'
    as platform;

BaseCacheManager? _manager;

Future<void> initializeCoverCache() async {
  try {
    _manager ??= await platform.createCoverCache();
    if (_manager != null) {
      CachedNetworkImageProvider.defaultCacheManager = _manager!;
    }
  } on Object {
    // Cover storage must not prevent access to the locally saved library.
    debugPrint('Cover storage unavailable; using the default image cache.');
  }
}
