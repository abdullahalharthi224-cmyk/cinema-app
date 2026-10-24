Project: Personal Media Hub for iOS (working name: "Cinema")
This file is the project brief for Claude Code. Read it fully before writing any code.
The owner is NOT a programmer: explain every step simply (in Arabic when talking to the owner),
make decisions yourself when they are technical, and only ask the owner about taste/preferences.
1. What we are building
A private, single-user iOS app in the same family as Stremio / Nuvio:
The app hosts NO content. Everything comes from addons the owner installs (Stremio addon protocol).
The owner already has addons in his Stremio account; importing them is the #1 feature.
It must look and feel like a first-party Apple app (Apple TV app / App Store quality).
Delivered as an unsigned .ipa built in the cloud (owner has no Mac). The owner signs and installs
it himself through his signing store.
Do NOT write scrapers or built-in providers for any streaming/piracy site. The app is only a client
for addons the owner adds.
2. Tech stack (decided)
Swift 5.10+, SwiftUI, iOS 17 minimum, iPhone only (no iPad version is planned).
Project generated with XcodeGen (`project.yml`) so it builds on CI without opening Xcode.
Persistence: SwiftData (library, continue watching, settings). Secrets in Keychain.
Networking: async/await + URLSession, Codable models.
Video player: MPVKit (Swift Package) so MKV, HEVC, multiple audio tracks and embedded
subtitles work. AVPlayer is NOT enough. Wrap it in a custom SwiftUI player UI.
Images: native AsyncImage with a small memory/disk cache (or Nuke via SPM).
No backend server.
3. Feature list
Phase 1 – Skeleton + addon import (most important)
Tab bar: Home, Search, Library, Settings.
Addon manager (Settings → Addons):
Import from Stremio account: email + password →
`POST https://api.strem.io/api/login` body `{"type":"Login","email":..,"password":..}` → `authKey`.
Then `POST https://api.strem.io/api/addonCollectionGet` body
`{"type":"AddonCollectionGet","authKey":..,"update":true}` → list of addons (`transportUrl`, `manifest`).
Save only the authKey in Keychain, never the password. Show the imported list with toggles.
Add addon manually by pasting a manifest URL (also accept `stremio://` links by converting to https).
Reorder, enable/disable, remove addons. Re-sync button.
Addon client implementing the Stremio protocol:
`{base}/manifest.json`, `{base}/catalog/{type}/{id}[/extra].json`,
`{base}/meta/{type}/{id}.json`, `{base}/stream/{type}/{id}.json`,
`{base}/subtitles/{type}/{id}.json`. Handle `extra` (search, skip, genre) correctly.
GitHub Actions workflow that produces the unsigned IPA (see section 5).
Phase 2 – Browsing
Home: large cinematic hero carousel (auto-advancing, parallax), then horizontal rows built from
the catalogs of enabled addons.
Detail page: backdrop with blur fade, logo/title, year, rating, genres, description, cast,
seasons/episodes picker for series, trailer if available.
Stream picker sheet: groups streams by addon, parses quality (4K/1080p/HDR/DV), size, source;
shows clearly when a stream type is unsupported (e.g. raw torrent `infoHash` streams).
Search across all addons that support search.
Phase 3 – Player
MPVKit player with custom controls: scrubbing with thumbnails if possible, ±10s, speed,
audio track & subtitle menus, external subtitles from subtitle addons, subtitle size/color,
aspect/zoom, Picture-in-Picture, AirPlay where possible, lock screen controls.
Resume position saved automatically; "Continue Watching" row on Home.
Phase 4 – Luxury & customization
Themes: Dark Cinematic (default), OLED Black, Light Glass; custom accent color.
Reorder / hide Home rows, choose hero source, poster size, show/hide ratings.
Multiple local profiles with avatar, each with its own library and history.
Optional Trakt sync (postponed by the owner). App icon variants.
Haptics, matchedGeometryEffect transitions, `.ultraThinMaterial` surfaces,
SF Pro / SF Pro Rounded, SF Symbols, smooth skeleton loading states, Dynamic Type support.
4. Design rules
Follow Apple Human Interface Guidelines. If it would look out of place in an Apple app, don't do it.
Generous spacing, large titles, rounded continuous corners, subtle shadows, no clutter.
Every list must have loading, empty and error states that also look polished.
Arabic + English localization, full RTL support.
5. Build & delivery (owner has no Mac)
`.github/workflows/build-ipa.yml` on `macos-latest`:
install XcodeGen → `xcodegen generate` → `xcodebuild archive` with
`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` → copy the `.app` into `Payload/` →
zip as `Cinema.ipa` → upload as a workflow artifact (and attach to a GitHub Release on tags).
Bundle id placeholder: `com.personal.cinema` (owner's signing store may re-sign it).
After each phase: make sure CI is green, then tell the owner in simple Arabic exactly where to
download the IPA and what to test.
6. Working rules for Claude Code
Work phase by phase; finish and verify one phase before starting the next.
Keep the code organized: `App/`, `Features/<Feature>/`, `Core/Addons/`, `Core/Player/`,
`Core/Storage/`, `DesignSystem/`.
Write unit tests for the addon client and Stremio import parsing.
Never commit secrets. Never hardcode content sources.
7. Roadmap (agreed with the owner — planned, not built yet)
Done:
Profile lock: Face ID with a 4-digit passcode fallback, per profile or for the whole app (passcode never in backups).
Kids profile limited by age rating (TMDB certification; unrated titles hidden; no Settings/addons; leaving needs the passcode, not Face ID).
Customization: hero source, poster size, show/hide ratings, alternate app icons (tools/AppIcons/make_variants.py).
Next:
Home Screen widget (last watched, continue with one tap).
Siri / App Intents ("Continue watching in Cinema").
Viewing statistics page (hours watched, top genres, most-seen actors).
After that:
A web version for the laptop.
Never write anything to the owner's Stremio account: it is used only to import addons.
