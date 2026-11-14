# Reading experience

The visual-overhaul branch uses warm neutral surfaces, green accents, solid colors and a compact library. The account/help bar stays separate from each screen’s controls. Short fades respect reduced-motion settings. There are no quests, goals, daily counters or activity tracking.

## Home, Browse and editing

Home puts Continue reading and recently read titles first. A saved title with a valid reading link opens the reader directly; its menu opens the editor. The editor is a full page with spaced fields, keyboard-safe scrolling and Save in the toolbar. Unsaved text in Add, Browse, Library search and authentication forms resets when switching tabs or returning from another page. Dialogs and dropdowns keep the underlying form intact; saved book details and website shortcuts are retained. Unchanged historical non-URL reading notes are preserved exactly.

Browse is a list of reading websites, rather than a separate catalog feed. Atsu is the only default shortcut. Users can open a full web address and save/remove custom website shortcuts. Shortcuts are device preferences, not library records, and are not synced between devices. Addresses must use HTTP(S) and cannot contain embedded credentials.

On supported native platforms, Save to library captures the current page URL and available title/cover, with editable title/type/chapter confirmation. Atsu reader controls supply the active series title, media type and current chapter when generic browser metadata is missing. The compact layout uses its floating title control; when title/type remain incomplete, Save to library makes one optional three-second lookup of the exact public series ID. Lookup failures preserve manual saving, and automatic reading updates make no extra lookup requests. Other sites use structured page metadata and active chapter labels when available. Missing type/chapter detection is marked for review; fractional chapters are not rounded. Existing normalized titles attach the chosen page to their existing book and retain the confirmed chapter/type. Other platforms open websites in the external browser; Add retains manual link entry. Add and mass import continue to use the shared catalog search service for title details.

The familiar source-list pattern is informed by [Mihon](https://mihon.app/); reading shelves emphasize covers and resuming a book. Websites remain external services, with their own availability, accounts and reading permissions. These are website entry points, not bundled content or guaranteed provider integrations.

## Reading

- Library tiles with valid links open reading directly. Their edit menus, long-press selection and grid/list controls remain. Books without reading links open the editor.
- The reader watches URL changes and full page loads, including single-page navigation. Updates are debounced and serialized through the existing local-first repository/outbox.
- Automatic bookmark changes require the same host and an identifiable matching story/chapter title. Home/search/login pages and other stories are excluded. Whole, bounded chapter labels can update the stored chapter. Missing/ambiguous titles and fractional chapters are not guessed; bookmark and chapter controls provide explicit corrections.
- Controls can be hidden and shown again. Close exits directly; back/forward, reload, external browser and explicit page saving remain available.
- Scroll checkpoints use CSS coordinates and are scoped by user/book/exact URL in local preferences. Idle scroll, backgrounding and normal close flush them; matching page loads restore them. Dynamic/lazy-loading sites may override restoration. This is not cross-device scroll sync or a guarantee against abrupt OS process termination.
- Local reader checkpoints are cleared after successful account deletion. Hive fields, production collection layout and deployed rules are unchanged by this branch.

## Verification

```powershell
flutter analyze
flutter test
flutter test integration_test/visual_overhaul_test.dart --flavor staging --no-uninstall -d emulator-5554
```

The native rehearsal uses fictional books, a memory cloud adapter and local HTML. It exercises chapter detection, single-page URL/title changes, rejection of another story, hidden controls, exit, persisted scroll restoration, browser-to-library capture and editor saving, then captures light/dark navigation screenshots. It does not use production accounts/data. The debug-only loopback network exception supports its fixture; release networking is unchanged. Restore the normal migration-enabled staging APK after testing.

Unit/widget checks cover custom website persistence, URL validation/deduplication, corrupt preferences, opening/removing shortcuts, editor scrolling with a keyboard, unchanged legacy notes, encoded title lookup, conservative chapter matching, scroll checkpoint cleanup and small-screen light/dark layouts with enlarged text. Real reading websites, sign-in and provider-specific behavior still need attended acceptance testing.
