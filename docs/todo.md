# Follow-up work

## Account and sign-in error handling

- [ ] Distinguish an email-change request being accepted from email delivery and a verified change. Do not claim that a message was sent when Firebase does not confirm delivery.
- [ ] Explain missing verification emails, including checking Spam, delivery delays, request limits, and the possibility that the destination address is already associated with another account. Respect Firebase email enumeration protection; do not expose other users' account existence or disable the protection to obtain more specific errors.
- [ ] Clearly separate the password-login email from the connected Google identity, and show the current provider state after refresh.
- [ ] Give useful recovery instructions for expired sessions, wrong credentials, provider conflicts, interrupted Google-account changes, network failures, and other supported edge cases. Preserve the original account UID and library.
- [ ] Add regression coverage for suppressed email-change responses, pending versus completed changes, and actionable error messages. Record useful diagnostic error codes without passwords, tokens, or verification links.

Deferred intentionally; this entry does not change the released app or production authentication settings.
