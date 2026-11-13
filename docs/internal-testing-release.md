# Internal testing release

## Current gates

The upload-key reset is still pending (confirmed by the project owner). The replacement keystore exists locally, but `android/key.properties` is not configured. No production rules, production data, Play release, application ID or version number is changed by the staging rehearsal.

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
- Review and deploy the temporary compatibility rules to the explicit production project before publishing the production compatibility build. Follow `compatibility-rollout.md`; strict rules are a later coordinated cutover.

## Build and distribute

1. Check the highest version code in Play Console and choose a larger one. Update the version in `pubspec.yaml` deliberately; the current source is `1.1.4+15`. Do not assume 16 is unused.
2. Run analysis, app/rule tests and the release build with the approved signing configuration:

   ```powershell
   flutter analyze
   flutter test
   flutter build appbundle --release --flavor production --dart-define=LEGACY_DATABASE_COMPATIBILITY=true
   ```

3. Verify the AAB is signed with the approved upload certificate and retains application ID `edu.cpp.reading_tracker`. Confirm the embedded Firebase project is `reading-tracker-67f66`, not staging.
4. In Play Console, create an **Internal testing** release, upload the signed AAB, add release notes/testers, and review the release before distributing it. Installing through Play tests the Play app-signing certificate; local debug sign-in is a separate certificate configuration.
5. Install through the internal-testing link. Confirm Google sign-in, existing library preservation, offline edits, reconnect and deletion on disposable test data. Do not promote to production until these checks pass.

Suggested release notes: “Improved book search and imports, optional book covers, offline synchronization, conflict handling, and account cleanup.” Adjust these to match the final accepted release.

Keep production rollout and the later database reorganization separate. No Firebase collection migration is included here.
