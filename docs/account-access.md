# Sign-in and account changes

Open **Account Settings → Sign-in & security**. All changes operate on the
existing Firebase user; no library documents, Hive ownership, document IDs,
reading positions, or outbox entries are transferred to another user.

## Google accounts

1. A Google-only user first sets a Reading Tracker recovery password after
   reauthenticating with their currently linked Google account. This enables
   password login at their existing verified account email.
2. **Change Google account** reauthenticates Firebase using that recovery password,
   asks for the current Google identity to capture a rollback credential, verifies
   its provider ID matches, and asks for the replacement. It does not redundantly
   reauthenticate Firebase through an old Google email after the password email
   changed. Native Google
   selection signs out of the Google picker only, never the Firebase session.
3. A confirmation identifies the selected address and explains that the account
   email may change to it while the recovery password stays the same.
4. The old Google provider is unlinked and the new credential linked to the
   same UID. Firebase permits one Google provider per user, so these operations
   are not atomic. Password recovery remains attached throughout.
5. Failed replacement reads the provider state back first to detect a lost
   success response. Otherwise it attempts to restore the old credential. If
   restoration also fails or the process exits between steps, the user can sign
   in using their account email and recovery password, then **Connect Google**.

An identity already linked to another Firebase account is rejected. The app
does not merge or delete the other account. Wrong-password, wrong-current-Google,
cancelled picker, and cancelled confirmation paths do not unlink anything.
Web uses Firebase popup linking; cancellation after unlink follows the same
restoration/recovery policy. Desktop platforms without Google sign-in support
show this limitation and retain email/password controls.

## Email/password accounts

- **Change password** requires the existing Reading Tracker password. It does
  not change the password of a Google account.
- **Change password-login email** reauthenticates and calls
  `verifyBeforeUpdateEmail`. The old address remains until the new inbox is
  verified through Firebase's hosted action link. Refresh settings afterward;
  if Firebase requires a new session, sign in using the verified new address.
- A linked Google account is managed separately from the password sign-in
  email. The profile labels both addresses. Changing a password email does not
  replace the Google identity: use **Change Google account** for that.

Email verification can invalidate the active Firebase session. The root session
gate removes pushed account/credential routes when the UID is lost or changes,
then shows sign-in with guidance to use the verified email and existing password.
An account-settings route opened or refreshed after expiry shows a recovery page
instead of throwing from initialization. Normal offline refresh failures retain
the settings screen. Local library/outbox storage is not cleared by this transition.
- Password-only users can **Connect Google** to their existing UID after
  verifying their password and confirming the selected identity.

Passwords exist only in transient form inputs and SDK calls. They are not logged
or saved in Hive/preferences. Credential pages clear on reopening/returning.
The screen prevents duplicate mutations and leaving during an active change;
every asynchronous service step checks the current Firebase UID before mutating.
Completed account deletion and sign-out remain separate existing workflows.

## Verification

Unit/widget tests cover recovery gating, wrong credentials, cancellation,
collisions, rollback failure, ambiguous network success, session changes,
concurrent requests, password/email forms, and header navigation/sync.

`integration_test/account_access_test.dart` plus
`tool/firestore/run-native-account-access.mjs` run only against local Auth and
Firestore emulators under `demo-reading-tracker`. The harness asserts emulator
addresses before creating fictional accounts. It exercises real Android Firebase
password setup, Google replacement and collision restoration, interrupted-switch
password recovery/reconnection, password changes, verified email action codes,
and subsequent sign-in. Both SDK and administrator read-back verify the same UID
and exact migrated library content. It does not authenticate a real Google user.
The native runner uses `--no-uninstall` to preserve the installed staging app's
data; restore the regular staging APK after running its integration entry point.
Regression coverage also keeps account settings open during session loss and
tests Google replacement after the password-login email has already changed.

The actual Google account picker and real verification-email delivery still need
an attended staging test with accounts controlled by the tester. Do not test
first on an irreplaceable production account or remove its recovery password.

## Header

The **Reading Tracker** header button opens **Your shelf**, with owner-scoped
counts by type, pending sync status, manual sync, and Home/Library shortcuts.
Help stays on the left of Home and Profile stays on the right. This overview
does not add reading goals or change library storage.
