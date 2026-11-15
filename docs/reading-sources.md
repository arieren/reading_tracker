# Reading websites and page metadata

Website choices are user data. Atsu is the only built-in default. Add a website in Browse > Add website using a full address or a bare domain (for example, atsu.moe), then select it in Account Settings > Reading links. Manage websites opens the same list from settings. Older preferred-source values migrate to the saved-site format. Removing a preferred custom site resets the preference to Atsu.

Saving an opened page does not require a supported search provider. The reader inspects public metadata in the currently rendered page: Open Graph/Twitter fields, Schema.org JSON-LD book/series data, a title or main heading, explicit cover attributes and labelled media-type fields. Relative covers are resolved against the page URL. Site names are stripped from titles when declared. JSON-LD recommendations and publisher logos are not treated as the main book. Missing or ambiguous details remain editable instead of being invented. Web novels use Light Novel.

Atsu reader layouts and public data have an optional specialized adapter for better accuracy. MangaFire also has a public-API search adapter, but ordinary automated requests were rejected with HTTP 403 during verification on 2026-11-14. These adapters do not restrict which websites can be saved or selected, and a failed site does not redirect matching to a different provider.

Automatic link lookup is separate from metadata capture. It applies only to Manga, Manhwa and Light Novel entries added with a blank link. Known adapters require an exact title or a unique exact listed alternate title. An unknown website is attempted through its own same-origin GET search form, if present; a unique exact link must be verified against the destination's title. Search routes and results are never fabricated. If this fails, the book still saves locally with a blank link. Manually supplied links are retained.

Third-party access restrictions, scripts and missing metadata can limit extraction. No challenge bypass is used. Individual requests have three-second timeouts; automatic link lookup is bounded to six seconds. Existing chosen covers remain unchanged. The reader retries missing covers once per opening, and the existing cache retains downloaded images offline. Hive and Firestore schemas are unchanged.

Verification uses fake/recorded responses and an Android WebView with local fictional pages, including a generic website without a site adapter. Optional live Atsu lookup: `flutter test test/reading_source_live_test.dart --dart-define=LIVE_READING_SOURCE_TEST=true`.

Metadata references: [Open Graph](https://ogp.me/) and [Schema.org Book](https://schema.org/Book).

Website and reading-link forms add HTTPS to bare domains at the input boundary. Stored/navigation URLs retain HTTP(S) validation. The Add website dialog keeps a consistent width and reserves validation space so typing and errors do not resize it; the content still scrolls when the keyboard limits space.
