# Reading Tracker

Tracks novels, manga, manhwa and light novels with saved chapters, covers and reading links. Android is the primary release target.

## Development

Use Flutter 3.50.0 stable / Dart 3.14. Android uses SDK 36, AGP 9.3.1, Gradle 9.5.0, Kotlin 2.4.21 and NDK 28.2.13676358. Run `flutter doctor` before building; install the requested Android components and accept licenses with `flutter doctor --android-licenses`.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Firebase configuration is in `lib/firebase_options.dart` and `android/app/google-services.json`. Google sign-in needs the signing SHA-1 registered on the Firebase Android app. Register local debug certificates and the Play App Signing certificate for their respective builds. Never commit administrator credentials or signing keys.

## Organization

- `data/book_repository.dart`: local changes, pending operations, reconciliation and account data cleanup.
- `models/book.dart` and `book_codec.dart`: existing Hive schema, cloud serialization and validation.
- `services/`: authentication, catalog requests, import parsing, update checks and preferences.
- `widgets/`: shared auth form, book editor and navigation actions.
- `screens/`: presentation and one shared reader.

Provider owns theme state. The repository exposes pending-operation state. The main screen owns foreground retry and lifecycle refresh; tabs retain their state.

## Local storage and synchronization

Hive's existing `books` box remains the local library. Adapter type ID 0, fields 0–7 and existing numeric box keys remain compatible. Unknown historical read times remain unknown.

The separate `book_outbox_v1` box journals upserts/deletions before local changes. Books receive stable Firestore IDs before being queued. Local saves work without Firestore; the queue survives restart. It retries on manual refresh, resume and every 30 seconds while the main screen is active. Cloud timeouts never clear the queue. Only successful server queries establish remote deletion; failed/cached queries cannot erase local books.

Edits upload changed fields plus ownership, preserving unrelated edits from another device. Pending local changes win until acknowledged; concurrent changes to the same field use last cloud-write wins. Account switches preserve separate queues. ID-less legacy books belonging to the signed-in user receive IDs and are queued. Records with no owner are retained without assigning them to an account automatically.

Account deletion requires online sync and fresh authentication. Restoration intents are persisted before cloud deletion. If cleanup or identity deletion fails, local books remain recoverable and normal sync can restore cloud records. Atomic deletion across Firebase Auth and Firestore requires a trusted server workflow; the client does not claim that guarantee. A crash after identity deletion but before local cleanup can leave inaccessible old-user rows on the device.

## Verification and releases

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

GitHub Actions runs these checks. See [the acceptance checklist](docs/verification.md) for device, offline, account and release verification.

`pubspec.yaml` is the version source. Release signing uses the existing upload keystore and ignored `android/key.properties`. Preserve `edu.cpp.reading_tracker`; use `flutter build appbundle --release` with the correct credentials and a version code above the last Play upload. Releases are not published automatically.

The existing Hive generator constrains `build_runner` to 2.4.13. Keep generator/schema migrations separate and preserve Hive field IDs. Firebase plugins still require the legacy Kotlin/DSL flags; their forward-compatibility warning is documented in the checklist.

## Import behavior

Paste one title and optional whole chapter per line. Import automatically selects the top catalog result for its title, type and cover, preserving your chapter. Choose Import to proceed directly, or Review to inspect and change the automatically selected matches. Titles with no match retain their entered details; if catalog access fails, the remaining titles also retain their entered details. Duplicate titles are skipped. “Not started” maps to zero. Ambiguous “finished” entries need an explicit chapter. Search & Add remains available for individual books. Covers are optional; books without an image use the shared colored book-icon placeholder in the form and library.

## Catalog search

Add Book and the import preview share `CatalogService`, using the public Tenrai `/v1/manga` endpoint without an API key. Jikan discontinued its public API on October 1, 2026 ([announcement](https://github.com/jikan-me/jikan-rest/issues/613)). Tenrai provides the compatible title/type/cover schema ([documentation](https://api.tenrai.org/documentation)). It covers the MyAnimeList manga/novel catalog, not every general book or web novel; manual entry remains available for missing titles.

Search debounces input, ignores stale results, shares repeated in-flight requests, caches up to 40 queries for five minutes, and spaces request starts below the documented public limits. HTTP rate limits, timeouts and invalid responses are shown separately from successful empty searches. Import lookups run sequentially; canceling discards the import before any books are saved. Imports keep the entered chapter when selecting a match and remain usable without catalog access. Saved books remain in Hive and Firestore and do not depend on this API.

Normal tests use recorded responses. To verify actual API connectivity, run `flutter test test/catalog_live_test.dart --dart-define=LIVE_CATALOG_TEST=true`. This optional check depends on the provider being online; it is skipped in the normal test suite.
