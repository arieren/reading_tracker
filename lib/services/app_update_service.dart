import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

bool isNewerVersion(String latest, String current) {
  List<int>? parse(String value) {
    final clean = value.split('+').first;
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

Future<bool> checkForAppUpdate() async {
  final current = await PackageInfo.fromPlatform();
  final config = FirebaseRemoteConfig.instance;
  await config.setDefaults({'latest_app_version': current.version});
  await config.setConfigSettings(
    RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 5),
      minimumFetchInterval: const Duration(hours: 24),
    ),
  );
  await config.fetchAndActivate();
  return isNewerVersion(
    config.getString('latest_app_version'),
    current.version,
  );
}
