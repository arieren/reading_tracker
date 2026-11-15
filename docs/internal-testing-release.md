# Release preparation and optional internal testing

## Current gates

The owner reported that the replacement upload key becomes valid on November 13, 2026 at 8:46 PM; that date has passed. Verify the effective upload certificate in Play Console against the local keystore before signing. The local signing properties and both passwords were verified on November 15; the certificate matches the owner-supplied Play upload fingerprint. Signing properties remain ignored by Git. Never commit its passwords or the keystore.

Production accounts in the completed rollout have migrated to nested storage; see [production storage rollout](production-storage-rollout.md). Version 1.2.0/code 17 is published. The current candidate is `1.2.1+18`, adding support for a server-controlled default for future accounts. Matching rules are required before release; the default itself remains inactive until the new client is publicly available and accepted. The owner prefers production rollout; no new signed bundle is built automatically.

Do not upload a debug APK as a release. Production internal testing requires a signed Android App Bundle and a version code above every previous Play upload, including drafts and testing tracks.

## Signing preparation after approval

1. Confirm the upload-key reset approval/effective date in Play Console. Compare its upload certificate with the replacement certificate; do not change the app signing key.
2. Keep `C:\Users\fight\AndroidKeys\reading-tracker-upload.jks` and its password backed up securely outside Git. The PEM file is only its public certificate, not a substitute for the private keystore.
3. Create the ignored `android/key.properties` locally. Use the actual passwords without sending them through chat:

   ```properties
   storeFile=C:/Users/fight/AndroidKeys/reading-tracker-upload.jks
   keyAlias=upload
   storePassword=YOUR_KEYSTORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   ```

   Confirm the alias is `upload`; if you generated a different alias, use that one. The Gradle file already reads this configuration. Verify Git does not track this file or the keystore.

## Before the production bridge

- Finish old/new APK acceptance against staging, including Google sign-in, search/import, cover rendering, actual process restart, competing edits, deletion, and interrupted account deletion. Native integration/SDK checks supplement this acceptance; they do not claim every screen was tested.
- Preserve the current deployed production rules and obtain a secure production data backup. Verify it can be read/restored before any migration. No production backup is created by the staging checks.
- Inspect representative production book formats for compatibility. Do not rewrite user records just to make a test pass.
- Confirm the deployed migration-aware ownership compatibility rules remain in place. Follow `ownership-rollout.md`; do not deploy an older rules profile over them. Account cutover remains a separate coordinated operation.

## Build and distribute

1. Check the highest version code in Play Console across all tracks and drafts. The candidate in `pubspec.yaml` is `1.2.1+18`; increase the build number if 18 is already used. Gradle reads both values from Flutter. See [app updates](app-updates.md) for Remote Config timing.
2. Run analysis, app/rule tests and the release build with the approved signing configuration:

   ```powershell
   flutter analyze
   flutter test
   flutter build appbundle --release --flavor production --dart-define=USER_BOOK_STORAGE=true --dart-define=LEGACY_DATABASE_COMPATIBILITY=true
   ```

3. Verify the AAB is signed with the approved upload certificate and retains application ID `edu.cpp.reading_tracker`. Confirm the embedded Firebase project is `reading-tracker-67f66`, not staging.
4. The owner selected a **Production** release: upload the revised signed AAB to a new production draft, verify version 1.2.1/code 18 and review all warnings before submitting. Internal testing remains an optional alternative for future releases. Installing through Play tests the Play app-signing certificate; local debug sign-in is a separate certificate configuration.
5. After the selected track becomes available, update the existing Play installation without uninstalling it. Confirm Google sign-in, existing library preservation, offline edits, reconnect and deletion on disposable test data. Keep a backup/export and verify these flows on the owner-controlled account. Database cutover remains separate.

Suggested release notes: “Improved library storage and synchronization reliability, with support for automatic account storage setup.” Error-handling improvements recorded in `todo.md` are deferred and are not part of this release.

The production build follows existing account checkpoints and can read the future-account default. Unregistered accounts continue using root collections while that default is absent. After release acceptance and the Remote Config update, the guarded activation runner must perform its final census and verify any late accounts before enabling the nested default. Do not raise production Remote Config until the Play update is available to its intended audience.
