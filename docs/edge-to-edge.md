# Android edge-to-edge review

Android startup explicitly selects SystemUiMode.edgeToEdge. The app does not opt out of Android 15/16 edge-to-edge enforcement. Theme-aware overlay styles set status/navigation icon brightness without deprecated explicit bar-color setters. App bars, bottom navigation, input pages, bottom sheets, and reader controls continue using Flutter insets/SafeArea. Reader focus mode keeps its return-control button inside system-bar insets.

Widget tests exercise light/dark layouts with top cutouts, gesture-sized and three-button-sized bottom insets, and keyboard appearance/restoration. The local WebView integration checks reader toolbar placement, fullscreen exit placement, page capture, chapter changes and reading-position restoration under explicit edge-to-edge mode.

The Play recommendation supplied by the owner referred to the old 15 (1.1.4) release. Only Play's analysis of the revised bundle can establish whether that recommendation clears; do not claim that a source change alone removes a console warning. Older framework/plugin internals may also influence static recommendations.

The native WebView rehearsal passed on Android 16 with gesture navigation and Android 15 with three-button navigation, including light/dark screens, generic page capture, reader controls, and reading-position restoration. Widget tests cover the inset and keyboard combinations above. The temporary Android 15 device's navigation preference was restored after testing. Inspect the production build on a physical phone before rollout as well; emulator checks do not cover every device configuration.

References: [Flutter edge-to-edge](https://docs.flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge), [Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16).
