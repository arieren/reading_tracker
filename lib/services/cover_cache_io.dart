import 'dart:io' show Platform;

import 'package:file/file.dart' as storage;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

Future<CacheManager> createCoverCache() async {
  final support = await getApplicationSupportDirectory();
  return createPersistentCoverCache('${support.path}/book_covers');
}

CacheManager createPersistentCoverCache(
  String directory, {
  CacheInfoRepository? repository,
  FileService? fileService,
}) => CacheManager(
  Config(
    'book_covers',
    // Retain frequently used covers across restarts, with a bounded cover count.
    stalePeriod: const Duration(days: 365),
    maxNrOfCacheObjects: 2000,
    fileSystem: _CoverFileSystem(directory),
    repo:
        repository ??
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS
            ? CacheObjectProvider(databaseName: 'book_covers')
            : JsonCacheInfoRepository(databaseName: 'book_covers')),
    fileService: fileService ?? HttpFileService(),
  ),
);

class _CoverFileSystem implements FileSystem {
  _CoverFileSystem(String path)
    : directory = const LocalFileSystem().directory(path);
  final storage.Directory directory;

  @override
  Future<storage.File> createFile(String name) async {
    await directory.create(recursive: true);
    return directory.childFile(name);
  }
}
