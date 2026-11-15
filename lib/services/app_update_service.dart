import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

bool isNewerVersion(String latest, String current) {
  List<int>? parse(String value) {
    final clean = value.trim().split('+').first;
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(clean)) return null;
    return clean.split('.').map(int.parse).toList();
  }

  final a = parse(latest);
  final b = parse(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

Future<bool> checkForAppUpdate({FirebaseRemoteConfig? remoteConfig}) async {
  // This app currently has a Play Store update destination only.
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  final current = await PackageInfo.fromPlatform();
  final config = remoteConfig ?? FirebaseRemoteConfig.instance;
  await config.ensureInitialized();
  await config.setDefaults({'latest_app_version': current.version});
  await config.setConfigSettings(
    RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 5),
      minimumFetchInterval: const Duration(hours: 24),
    ),
  );
  try {
    await config.fetchAndActivate();
  } on Object catch (_) {
    // A previously activated value remains useful offline. Missing or malformed
    // values below fail open so a network/configuration failure alone cannot
    // lock out the library. A known newer cached version still requires update.
  }
  return isNewerVersion(
    config.getString('latest_app_version'),
    current.version,
  );
}
