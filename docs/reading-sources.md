# Reading websites and page metadata

Reading websites start empty. Users add their own website addresses in Browse, then optionally choose a saved website under Account Settings > Link preferences. Automatic link lookup is off until that choice is made, and can be switched off again without removing bookmarks. Removing the selected site disables lookup, including after that URL is later readded. Old provider-only preferences do not recreate sites or enable lookup. User-saved websites and existing book links are retained; Hive and Firestore schemas are unchanged.

There are no reading-site presets, domain-specific adapters, guessed provider endpoints, or site catalog API fallbacks. The separate book-metadata catalog search/import remains available; it does not supply reading copies or reading-site links.

## Generic behavior

- Opening a user-entered URL, browsing, saving its current page, manually editing details, restoring reading positions, and synchronizing the library remain available.
- The currently rendered page supplies standard Open Graph/Twitter metadata, Schema.org JSON-LD for a main book/series, headings, explicitly labelled type/cover fields, and unambiguous current chapter labels. Site-name suffixes are removed only when the page declares its site name. Recommendations and arbitrary page images are not treated as the main work.
- When standard titles are absent or generic, a unique visible title control near the top of a chapter page can supply a suggestion. Hidden text, navigation labels such as Chapters, and ambiguous controls are excluded. Explicit type labels and a unique story-specific portrait cover provide additional hints; obvious logos and banners are rejected. These heuristics can still be wrong, so suggestions remain editable. Fractional chapter numbers are not rounded. Web novels remain grouped under Light Novel.
- An optional bounded HTTP fetch of that same user-supplied page can fill missing metadata. It does not call a secondary catalog API. Existing book titles must match before metadata from that response is applied; chosen covers are preserved. Missing covers retry once per reader opening and the existing offline cover cache remains in use.
- After explicit source selection, Add can attempt a same-origin GET search form declared by that website. It does not guess search endpoints, replay hidden tokens, submit login forms, or bypass access challenges. A unique exact-title link must also match the destination metadata. Failure keeps the new book and leaves the reading link blank.
- Existing user-supplied reading links are never replaced by automatic lookup. Mass import retains catalog metadata matching and does not invent reading links.

Website/login restrictions, JavaScript-only search, ambiguous titles, and absent metadata can limit automation. Each request has a three-second timeout and automatic link lookup has a six-second overall deadline. Users can always browse manually and save/edit a link.

Bare domains are normalized to HTTPS at form entry. Navigation and stored URLs require HTTP(S) without embedded credentials. Add website reserves validation space and keeps a consistent width while typing, with scrolling when the keyboard limits space.

On Android, website fullscreen content is displayed inside the reader body rather than pushed over the app on a separate route. The app toolbar, bookmark/progress controls and dialogs remain available. Back first exits website fullscreen. Only the app's explicit hide-controls action hides its chrome; a website fullscreen request restores it.

Tests use fictional domains and local WebView pages, including empty setup, opt-in/off, removal/readding, exact/ambiguous matches, access rejection, metadata failures, and current-page saving. No live reading-site catalog test remains.

This general-purpose design is not a guarantee of store-policy or copyright compliance. Content permissions, metadata-service terms, screenshots and store descriptions still need review before submission. Do not advertise access to unauthorized copies or conceal app functionality from review.

Metadata references: [Open Graph](https://ogp.me/) and [Schema.org Book](https://schema.org/Book).
