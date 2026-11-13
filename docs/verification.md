# Stabilization acceptance checklist

Use disposable accounts for deletion tests. Keep your installed production app and its data until the refactor has passed verification. Android is the primary supported target. Desktop/web reader links fall back to an external browser; Google sign-in on web uses Firebase's popup flow. Apple builds and deployed backend permissions need their own verification.

## Automated checks

Run `flutter pub get`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`, and `flutter build apk --debug`.

Tests cover startup/update failures, version parsing, authentication submission, manual covers, durable outbox recovery, duplicate prevention, server-confirmed deletion, failed reads, concurrent edits, account switching, import parsing and account deletion failure/success.

## Device acceptance

1. Start normally and without network. Previously saved books must remain visible without waiting for Remote Config.
2. Log in with Google; cancel Google login; then retry successfully.
3. Register with email, verify it, sign in, reset the password, then sign in again. Password spaces must be preserved.
4. Add manual books with and without a custom cover URL, plus a reading link. An empty cover must save successfully and show the shared book-icon placeholder. Check the cover, type and chapter after restarting.
5. Search for Naruto and Sword Art Online, type rapidly, select a result and add it once. Check its cover/type and negative/invalid chapter and invalid URL validation. Try an unmatched title and turn networking off: empty results and connection errors must have distinct messages; Retry must work after reconnecting.
6. Edit from Home and Library. Both must show the same fields and validation.
7. Disable networking; add, edit and delete different books. Check the pending status, restart, restore networking and retry sync. The changes should converge without duplicates or restored deletions.
8. Edit different fields of one book from two devices. Edits upload only changed fields. Competing edits to the same field must show a conflict; test both Use cloud and Keep this device. A delete on one device must win over an offline edit on another.
9. Switch between two accounts. Each account must see only its own books. Pending changes stay associated with their original account.
10. Open a reading link, navigate pages, use page-history back, save the URL, leave and return. Test a broken URL and external-browser fallback.
11. Import a small list directly: each title must use the top catalog match and retain chapter progress. Repeat via Review, change one selected match, then import and check type/cover and duplicate skipping. Titles with no match and remaining titles after a catalog failure retain their entered details. Cancel during lookup: no books should be imported.
12. Toggle dark mode, switch tabs, rotate the device and use large text. Search and tab state should survive tab changes.
13. Pull to refresh; check success/offline messages. Pending changes also retry every 30 seconds while the main screen is active and on resume.
14. On a disposable account, try deletion with wrong credentials: no book may be removed. Then delete successfully and confirm that the account and cloud records are gone. Interrupt cleanup and restart: the app must offer Resume account deletion, block new edits, and retain local books until Auth confirms deletion. Other accounts must remain untouched. Keep the app online during cleanup; Spark has no autonomous background worker.

## Backend and release checks

- Follow the coordinated release procedure in [storage.md](storage.md); old published builds cannot write under the strict new rules. Deploy and build the composite indexes before testing production sync.
- Inspect the deployed Firestore rules: authenticated users must only read/write their own documents; ownership must not be changeable; input fields/types must be validated. Frontend UID checks are not a substitute for rules. No backend rules were deployed by this refactor.
- Confirm that Firebase Google provider and the debug/Play signing SHA fingerprints are registered.
- Release signing requires the existing upload keystore and ignored `android/key.properties`. Never commit either. `edu.cpp.reading_tracker` remains the published application ID.
- The current version is sourced from `pubspec.yaml` (`1.1.4+15`). Increase it beyond the latest Play release before publishing; this refactor does not publish anything.
- Run a signed release build and a Play internal-test installation before merging/releasing. Check Remote Config against the release available to that user/platform.
- Firebase plugins still require the KGP/legacy-DSL compatibility flags in `android/gradle.properties`. Keep these until all plugins support built-in Kotlin; do not modify downloaded plugin caches to silence warnings.
