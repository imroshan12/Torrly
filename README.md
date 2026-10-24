# Torrly

An iOS torrent search-and-download app that behaves like the Android app TorrDroid (`intelligems.torrdroid` 2.0.3).
It was written from scratch from a behavioural teardown of that app, so it contains none of TorrDroid's code,
branding or ad SDKs.

- [Install on your iPhone](#install-on-your-iphone)
- [What it does](#what-it-does)
- [Building from source (developers)](#building-from-source-developers)
- [Provider format](#provider-format)
- [License](#license)

## Install on your iPhone

Torrent apps are not allowed on the App Store, so Torrly is installed by _sideloading_.

### What you need

- An iPhone or iPad on **iOS 17 or later**.
- An **Apple ID**: the free one you already use for the App Store is enough. You do **not** need the paid Apple
  Developer Program. iOS only runs apps signed for your device, and signing needs an Apple ID, so a phone can't run
  Torrly without one. To just try the app without an Apple ID, use the simulator ([Option C](#option-c-try-it-in-the-simulator-no-apple-id-needed)).
- Limits of a free Apple ID (set by Apple): the app must be **refreshed every 7 days**, and at most **3 sideloaded
  apps** can be installed at a time. Refreshing keeps your downloads and settings.

### Which method?

|                 | Option A: AltStore or SideStore             | Option B: Xcode          |
| --------------- | ------------------------------------------- | ------------------------ |
| Computer needed | Mac **or Windows PC**                       | Mac with Xcode           |
| You install     | the prebuilt `Torrly.ipa`                   | from the source code     |
| 7-day refresh   | automatic, or one tap in AltStore/SideStore | press Run in Xcode again |

### Option A: AltStore or SideStore (Mac or Windows)

1. **Get the app file.** Download `Torrly.ipa` from this repository's
   [Releases](../../releases) page onto your iPhone (Safari saves it to Files › Downloads).
   If there is no release yet, someone with a Mac can build it with `./scripts/build-ipa.sh` (see
   [Building from source](#building-from-source-developers)) and share `build/Torrly.ipa`.
2. **Install AltStore** on your iPhone by following the official guide at <https://faq.altstore.io>.
   In short: install AltServer on your computer, connect your iPhone with a USB cable, choose
   _Install AltStore_ from AltServer, and sign in with your Apple ID when asked.
   Alternatively use **SideStore** (<https://sidestore.io>), which needs the computer only once and then refreshes
   apps on the phone itself.
3. **Turn on Developer Mode** (iOS 16 and later): Settings › Privacy & Security › Developer Mode › On. The phone
   restarts; confirm _Turn On_ afterwards. (The switch appears once AltStore is installed.)
4. **Install Torrly.** Open AltStore (or SideStore) › **My Apps** › **+**, then pick `Torrly.ipa` from Files.
   It signs the app with your Apple ID and installs it.
5. **If iOS says "Untrusted Developer"**: Settings › General › VPN & Device Management › tap your Apple ID ›
   **Trust**.
6. **Every 7 days**: AltStore refreshes Torrly in the background while your computer runs AltServer on the same
   Wi-Fi. Otherwise open AltStore › My Apps › **Refresh All** before the 7 days run out. If you miss it, the app
   stops opening until you refresh; nothing is lost.

### Option B: build and install with Xcode (Mac)

1. **Install Xcode** (version 26 or later) from the Mac App Store and open it once so it can install its components.
2. **Install the build tools** with Homebrew (install Homebrew first from <https://brew.sh> if you don't have it):
    ```bash
    brew install cmake boost xcodegen
    ```
3. **Download the source:**
    ```bash
    git clone https://github.com/imroshan12/torrly-ios.git
    cd torrly-ios
    ```
4. **Build the torrent engine** (once; about 10 minutes):
    ```bash
    ./scripts/build-engine.sh
    ```
5. **Pick your own bundle identifier.** Each Apple ID needs a unique app identifier. Open `project.yml` and change
   both `com.sarvesh` (under `bundleIdPrefix`) and `com.sarvesh.torrly` (under `PRODUCT_BUNDLE_IDENTIFIER`) to
   something of your own, for example `com.yourname` and `com.yourname.torrly`.
6. **Create the Xcode project and open it:**
    ```bash
    xcodegen generate
    open Torrly.xcodeproj
    ```
7. **Add your Apple ID to Xcode:** Xcode › Settings › Accounts › **+** › Apple ID, and sign in.
8. **Set up signing:** in Xcode click the blue **Torrly** project at the top of the file list › target **Torrly** ›
   **Signing & Capabilities**. Tick _Automatically manage signing_ and choose **Team: Your Name (Personal Team)**.
9. **Connect your iPhone** with a cable, unlock it and tap **Trust** on the "Trust This Computer?" prompt.
   Select your iPhone in the device menu at the top of the Xcode window.
10. **Turn on Developer Mode** on the iPhone if asked (Settings › Privacy & Security › Developer Mode › On, then
    restart and confirm).
11. **Press Run** (▶︎ or ⌘R). The first time, iOS may block the app as an "Untrusted Developer": open
    Settings › General › VPN & Device Management › your Apple ID › **Trust**, then press Run again.
12. **Every 7 days**: connect the iPhone and press Run again. Your downloads and settings are kept.

### Option C: try it in the simulator (no Apple ID needed)

On a Mac, follow Option B steps 1–4 and 6, choose an iPhone simulator (for example _iPhone 17_) in the device menu,
and press Run. Signing isn't needed for the simulator.

### Troubleshooting

| Problem                                                                       | Fix                                                                                                                |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Xcode: _"Failed to register bundle identifier"_ or _"…is not available"_      | The identifier is taken by another Apple ID. Change it (Option B step 5), run `xcodegen generate` again, then Run. |
| _"The maximum number of apps for free development profiles has been reached"_ | Free Apple IDs allow 3 sideloaded apps. Delete one you don't use, then try again.                                  |
| Torrly stopped opening                                                        | The 7-day signature expired. Refresh in AltStore/SideStore, or press Run in Xcode again. Your data is kept.        |
| _"Untrusted Developer"_                                                       | Settings › General › VPN & Device Management › your Apple ID › Trust.                                              |
| `build-engine.sh` fails at the start                                          | Check `brew install cmake boost` finished, and that Xcode (not only the command-line tools) is installed.          |

### Using it

- Downloaded files are in the **Files** app › On My iPhone › Torrly › Downloads. Tap ▶︎ on a finished download to
  play it; formats iOS can't play (such as `.mkv`) open in a preview whose share button sends them to an app like VLC.
- iOS doesn't let apps run in the background for long, so **keep Torrly open while downloading** (it gets a few
  seconds after you leave to save progress). Saved searches still run in the background through Background App
  Refresh, at times iOS chooses.
- Only download content you have the right to download.

## What it does

| TorrDroid behaviour                                                                                                                                                | Torrly                                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| Search tab: keyword, retry interval (5 min … 1 day), torrent type, "Download if available"                                                                         | `SearchFormView`                                                                          |
| Keyword suggestions while typing (3+ letters, Google suggest)                                                                                                      | `SearchSuggestions`; can be turned off in Settings                                        |
| Saved searches retried on their interval until found, up to _Max search retries_ (default 2)                                                                       | `SearchItem.record`, `AppModel` scheduler + background refresh                            |
| History cards with up to 8 suggestions, attempts count, edit, delete, search again                                                                                 | `HistoryView`                                                                             |
| Sites tried in order with three strategies (sequential / parallel / first-then-rest, default)                                                                      | `SearchEngine` (`SearchAlgorithm`)                                                        |
| Data-driven HTML scraper configured by JSON (`siteSettings`: rows, name, size, seeds, magnet, `more` detail pages, `typeValidation`)                               | `HTMLProvider`, same JSON schema, importable as is                                        |
| JSON search APIs                                                                                                                                                   | `JSONAPIProvider`                                                                         |
| Query clean-up (s02e05 episodes, noise words), category / size / trailer / cam-rip / adult filters, ranking by quality words, title match, seeders, leechers, size | `TextNormalizer`, `ResultFilter`                                                          |
| libtorrent engine: DHT, encryption prefer/require/off, random port 37000–57000, speed limits, proxy, port filter, seeding toggle, Wi-Fi only                       | `Engine/` (Objective-C++ over libtorrent 2.0.15 + OpenSSL 3.5) and `DownloadManager`      |
| Downloads list, torrent detail (files with priorities, trackers, pieces), tap ▶︎ to play a finished download                                                        | `DownloadsView`, `TorrentDetailView`, `MediaOpener`                                       |
| "+" button: add link, open .torrent, choose files                                                                                                                  | `AddLinkSheet`, `FileChooserView`; `magnet:` links and `.torrent` files also open the app |
| Notifications: suggestions available, search complete, download started/complete, waiting for Wi-Fi                                                                | `Notifier`                                                                                |

What it does differently: TorrDroid fetches its site list and scraper rules from the developer's Firebase Remote
Config, logs search terms to Google Analytics, and shows ads. Torrly keeps its providers on the device
(Settings › Search providers), has no analytics and no ads, and ships with one legal default provider (the Internet
Archive). Add your own providers there.

## Building from source (developers)

Requirements: Xcode 26+, Homebrew `cmake`, `boost` and `xcodegen`.

```bash
./scripts/build-engine.sh      # once: OpenSSL + libtorrent + bridge → Vendor/TorrlyEngine.xcframework (~10 min)
xcodegen generate              # creates Torrly.xcodeproj from project.yml (re-run after adding or removing files)
open Torrly.xcodeproj
```

Making a release `.ipa` for Option A (unsigned; AltStore and SideStore sign it with the installer's Apple ID):

```bash
./scripts/build-ipa.sh         # → build/Torrly.ipa; attach it to a GitHub release
```

Tests:

```bash
swift test --package-path Packages/TorrlyCore                                          # search, providers, ranking
xcodebuild -scheme Torrly -destination 'platform=iOS Simulator,name=iPhone 17' test    # engine tests
```

Layout:

```
Engine/              Objective-C++ bridge over libtorrent (TLSession, models), built by scripts/build-engine.sh
Packages/TorrlyCore  Swift package: models, providers (HTML/JSON), search engine, ranking, magnet helpers
Torrly/              SwiftUI app: AppModel (searches, scheduler, providers), DownloadManager, views
TorrlyTests/         Engine integration tests (run on the simulator)
scripts/             build-engine.sh, build-ipa.sh, make-icon.swift
```

## Provider format

HTML providers use TorrDroid's `siteSettings` schema. Selectors are jsoup-style CSS (`td:eq(1) > a`), handled by
SwiftSoup. A field is either a selector (its text is used) or `{ "qs": selector, "access": "href" }`.

```json
{
	"https://example.org": {
		"request": {
			"type": "GET",
			"url": { "default": "https://example.org/search/%s", "audio": "…" }
		},
		"rows": "table > tbody > tr",
		"name": "td:eq(1) > a",
		"size": "td:eq(2)",
		"seeds": "td:eq(4)",
		"leechers": "td:eq(5)",
		"magnet": { "qs": "td:eq(1) > a", "access": "href" },
		"more": {
			"qs": "td:eq(1) > a",
			"page": { "magnet": { "qs": "a.magnet", "access": "href" } }
		},
		"typeValidation": { "video": ".*(movie|tv).*" }
	}
}
```

JSON API providers name the fields to read from each result (`name`, `size`, `seeds`, `leechers`, `infoHash`,
`magnet`, or a `torrentURL` template such as `https://host/download/{id}.torrent`). See
`Packages/TorrlyCore/Sources/TorrlyCore/Resources/default-providers.json`.

## Search Providers

Torrly includes a variety of search providers. Some are enabled by default, while others are available as fallbacks:

- **Active Providers**: apibay, knaben, limetorrent
- **Fallback Pool**: katracker, 247prox, tpb.vip, tpb.world, pirateproxy.dev, 1337x.unblockit.link, zooqle, idope, torlock, limetorrents.lol, torrentz2/torrentz2k, bitsearch, torrentdownload.info, the punycode limetorrents, thepibay

## License

Torrly is released under the [MIT License](LICENSE). It includes libtorrent (BSD), OpenSSL (Apache 2.0),
SwiftSoup (MIT), Boost headers (Boost Software License) and the Mozilla CA certificate list (MPL 2.0); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
