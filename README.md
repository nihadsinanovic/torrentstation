# TorrentStation

A SwiftUI iPhone and iPad app for Synology Download Station, with Plex playback and a Safari share extension for
sending links to the NAS. How it is built: [ARCHITECTURE.md](ARCHITECTURE.md).

## GitHub builds

The **Build** workflow compiles the app and its share extension on a GitHub Mac for every pull request and push to
`main` (unsigned, for the simulator), so a change that breaks the build shows up on the pull request. The repository
is public, so the Mac minutes are free.

## iPhone builds (TestFlight)

The **iPhone app to TestFlight** workflow (Actions → iPhone app to TestFlight → Run workflow) builds the app on a
GitHub Mac, signs it and its share extension, and uploads it to TestFlight; no Mac of your own is needed. Each run's
number is its build number.

One-time setup, with the Mac. If Our place (the couples repository) already uploads to TestFlight from the same Apple
developer account, reuse its distribution certificate and API key: skip steps 3 and 5 and give this repository the same
`IOS_DIST_CERT_P12`, `IOS_DIST_CERT_PASSWORD` and `ASC_*` secrets.

1. [Certificates, IDs & Profiles](https://developer.apple.com/account/resources) → Identifiers: check that the App IDs
   `frugi.TorrentStation` and `frugi.TorrentStation.TorrentStationShare` exist (Xcode's automatic signing creates
   them; otherwise + → App IDs → App, with those explicit Bundle IDs). Both need the App Groups capability with
   `group.frugi.torrentstation.shared` and `group.com.torrentstation.shared` ticked.
2. [App Store Connect](https://appstoreconnect.apple.com) → Apps → + → New App, with the Bundle ID
   `frugi.TorrentStation`. The name must be unique on the App Store; the name under the Home Screen icon stays
   "TorrentStation" either way.
3. Signing certificate: Xcode → Settings → Accounts → your team → Manage Certificates → + → Apple Distribution. Then in
   Keychain Access → login → My Certificates, export "Apple Distribution: …" as a .p12 with a password.
4. Provisioning profiles, two of them: Certificates, IDs & Profiles → Profiles → + → App Store Connect, pick the App
   ID `frugi.TorrentStation` and the certificate, and download it. Repeat for
   `frugi.TorrentStation.TorrentStationShare`.
5. API key: App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → +, role
   App Manager. Download the .p8 (possible only once) and note the Key ID and the Issuer ID.
6. GitHub → this repository → Settings → Secrets and variables → Actions → New repository secret, for each of:

   | Secret | Value |
   | --- | --- |
   | `IOS_DIST_CERT_P12` | `base64 -i Certificates.p12 \| pbcopy`, then paste |
   | `IOS_DIST_CERT_PASSWORD` | the .p12 password |
   | `IOS_PROFILE` | `base64 -i <app profile>.mobileprovision \| pbcopy`, then paste |
   | `IOS_SHARE_PROFILE` | `base64 -i <share extension profile>.mobileprovision \| pbcopy`, then paste |
   | `ASC_KEY_ID` | the Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_KEY_P8` | `pbcopy < AuthKey_<Key ID>.p8`, then paste |

7. After the first upload: App Store Connect → the app → TestFlight → add an Internal Testing group with yourself, and
   install the TestFlight app from the App Store on the iPhone.

The certificate and profiles expire after a year: redo steps 3, 4 and 6. The workflow switches only the Release builds
to these profiles (`scripts/ios-signing.mjs`), so Xcode on the Mac keeps its automatic signing.

The app icon (`TorrentStation/Assets.xcassets/AppIcon.appiconset/AppIcon.png`) is a placeholder, a download arrow in
the app's accent colour; replace the file with a 1024×1024 PNG without transparency to change it.
