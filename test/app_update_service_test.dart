import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reading_tracker/services/app_update_service.dart';

class _RemoteConfig extends Fake implements FirebaseRemoteConfig {
  String value = '';
  String? fetched;
  bool offline = false;
  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<void> setDefaults(Map<String, dynamic> defaults) async {}
  @override
  Future<void> setConfigSettings(RemoteConfigSettings settings) async {}
  @override
  Future<bool> fetchAndActivate() async {
    if (offline) throw StateError('offline');
    if (fetched != null) value = fetched!;
    return fetched != null;
  }

  @override
  String getString(String key) {
    expect(key, 'latest_app_version');
    return value;
  }
}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    PackageInfo.setMockInitialValues(
      appName: 'Reading Tracker',
      packageName: 'edu.cpp.reading_tracker',
      version: '1.2.0',
      buildNumber: '16',
      buildSignature: '',
    );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'uses newly fetched version and never prompts for same or older',
    () async {
      final config = _RemoteConfig()..fetched = '1.3.0';
      expect(await checkForAppUpdate(remoteConfig: config), isTrue);
      for (final version in ['1.2.0', '1.1.4', 'invalid', '']) {
        config.fetched = version;
        expect(await checkForAppUpdate(remoteConfig: config), isFalse);
      }
    },
  );
  test(
    'offline uses previously activated value and missing cache fails open',
    () async {
      final config = _RemoteConfig()
        ..offline = true
        ..value = '1.3.0';
      expect(await checkForAppUpdate(remoteConfig: config), isTrue);
      config.value = '';
      expect(await checkForAppUpdate(remoteConfig: config), isFalse);
    },
  );
  test('Play Store update check is not used on desktop', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(await checkForAppUpdate(), isFalse);
  });
}
