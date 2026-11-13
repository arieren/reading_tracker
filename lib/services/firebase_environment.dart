import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';

String firebaseProjectForFlavor(String? flavor) => switch (flavor) {
  null || 'production' => 'reading-tracker-67f66',
  'staging' => 'reading-tracker-test-a734e',
  _ => throw StateError('Unknown application environment: $flavor'),
};

Future<void> initializeFirebaseEnvironment() async {
  final expected = firebaseProjectForFlavor(appFlavor);
  final nativeAndroid =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  if (appFlavor == 'staging' && !nativeAndroid) {
    throw UnsupportedError(
      'The staging Firebase configuration currently supports Android only.',
    );
  }
  // Android reads the google-services resources for its native build flavor.
  // This avoids combining a staging package with Dart's production options.
  final app = Firebase.apps.isEmpty
      ? await Firebase.initializeApp(
          options: nativeAndroid
              ? null
              : DefaultFirebaseOptions.currentPlatform,
        )
      : Firebase.app();
  if (app.options.projectId != expected) {
    throw StateError(
      'Firebase configuration does not match this application environment.',
    );
  }
}
