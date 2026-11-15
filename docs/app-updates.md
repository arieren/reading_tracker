# Required app updates and release versions

Firebase **Remote Config**, not Firestore, supplies the string parameter
`latest_app_version`. The production project is `reading-tracker-67f66`; staging
uses its own Remote Config in `reading-tracker-test-a734e`.
Store a version name such as `1.2.0`, not the Android version code `16`.
The parameter description in the console should say "Required app version name
available on Google Play" rather than "version code".

The Android app compares three numeric version components. `1.2.0` is newer than
`1.1.4`; equal versions, older remote versions, empty values, and malformed values
do not show a prompt. A build suffix such as `+16` does not affect this comparison.
For another release that needs an update prompt, increase the version name too.
This is a Play Store prompt; desktop/web/iOS do not use this destination.

The check runs once at startup without blocking local use, with a six-second
overall deadline and a five-second fetch timeout. Remote Config fetches are cached
for 24 hours, so publishing a value does not immediately reach every installed
app. A failed fetch falls back to the last activated value. No valid cached value
means the app continues normally. The prompt preserves the underlying screen's
state, but blocks interaction with every underlying route. It has no dismiss
button. **Update now** opens the existing Play listing externally and reports
launch failures with a retryable button. It remains blocked until an updated
binary runs or a subsequently fetched requirement no longer exceeds its version.
A known newer cached requirement also blocks offline access. With no valid
requirement available, network/configuration failures alone do not block local use.

## Release order

1. Set the release version in `pubspec.yaml`. Current candidate: `1.2.0+17`.
   `1.2.0` becomes Android `versionName`; `17` becomes `versionCode`.
   `android/app/build.gradle` already reads `flutter.versionName` and
   `flutter.versionCode`. Do not duplicate those numbers in Gradle.
2. Verify the highest version code across every Play track and uploaded draft.
   Code 16 was uploaded for the abandoned draft; use the next unused code 17.
   Confirm code 17 remains unused before upload.
3. Finish code review, signing-certificate verification, and device checks.
   Production builds must use the production Firebase configuration and existing
   application ID. See [internal testing](internal-testing-release.md).
4. Leave production `latest_app_version` at `1.1.4` while the new version is only
   an internal test or unavailable to public users. Test the prompt using the
   staging project's Remote Config instead. Testing new code does not change the
   behavior of already installed older binaries. The old 1.1.4 binary's optional
   prompt remains optional; required updates only take effect in this new code.
5. Once the new release is available to the intended public audience, publish
   `latest_app_version = 1.2.0` as a string in production Remote Config. For a
   staged Play rollout, wait until everyone targeted by the prompt is eligible;
   otherwise some people will see a prompt without an available update.

This gate uses `latest_app_version` as the required version, so every published
increase requires updating once fetched. It does not prove adoption or guarantee
that an old offline app has received a new requirement.
Do not migrate production users or block legacy clients solely because the value
was published. The separate [storage migration](user-storage-migration.md) still
requires backups, verification, and an explicit production rollout.

Authentication is separate between staging and production too. Changing an email
or connected Google account in Reading Tracker Test does not change the production
account. After installing the Play update, sign into the existing production
account first, then change its sign-in details through account settings if wanted.
Signing into a different Google identity does not transfer the existing library.
