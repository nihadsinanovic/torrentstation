# Feature Implementation Brief for Claude Code

Implement the following 6 features for TorrentStation. Read `ARCHITECTURE.md` first for full context on the existing codebase, patterns, and conventions. All new code must follow the existing patterns: actor-based services, `@Observable` ViewModels on `@MainActor`, `nonisolated Sendable` model structs, Swift async/await (no Combine), and Swift 6 concurrency compliance.

---

## Feature 1: QuickConnect Support

**Goal:** Let users connect using their Synology QuickConnect ID (e.g. "mynas") instead of a manual IP address.

**How it works:** QuickConnect is a resolution protocol. The app sends the QuickConnect ID to Synology's global server, which returns a prioritized list of connection routes (LAN, WAN, hole-punch, relay). The app tries each route until one works, then uses that URL for all subsequent API calls.

**Implementation:**

1. Create `Services/QuickConnectService.swift` as an `actor`. The resolution flow:
   - POST to `https://global.quickconnect.to/Serv.php` with JSON body: `{"id": "quickconnect_id", "command": "get_server_info", "version": 1}`
   - The response contains `server` info with `interface`, `external`, and `relay` connection details
   - Build candidate URLs from LAN IPs (from `interface`), then external IP/DDNS (from `external`), then relay (from `relay`)
   - Try each candidate by hitting `/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query&query=all` with a short timeout (3-5 seconds)
   - Return the first working URL

2. Update `Models/ConnectionConfig.swift`: Add an optional `quickConnectID: String?` field. The `baseURL` computed property stays the same (it still uses address/port), but the config now tracks how the connection was established.

3. Update `Views/LoginView.swift`: Add a segmented control or toggle at the top of the login form to switch between "Address" (current manual IP entry) and "QuickConnect ID" (single text field). When QuickConnect is selected, show one text field for the ID. On login, resolve the ID first via `QuickConnectService`, populate the `ConnectionConfig` with the resolved address/port/HTTPS, then proceed with the existing `AuthService.login()` flow.

4. Update `ViewModels/AuthViewModel.swift`: Add a `loginWithQuickConnect(id:username:password:)` method that calls the resolver first, then delegates to the existing login logic. Show a "Resolving..." state while the QuickConnect lookup is in progress.

5. Persist the QuickConnect ID in `StoredCredentials` (via `KeychainService`) so auto-login can re-resolve on next launch if the IP has changed.

---

## Feature 2: Home Screen Widgets & Lock Screen Live Activities

**Goal:** Show download progress on the Home Screen and Lock Screen without opening the app.

**Implementation:**

1. Create a new **Widget Extension** target named `TorrentStationWidget`.

2. **App Group:** Create a shared App Group container (e.g. `group.com.torrentstation.shared`). The main app writes current download state to `UserDefaults(suiteName: "group.com.torrentstation.shared")` every polling cycle (in `TaskListViewModel`). The widget reads from this shared container.

3. **Shared data model:** Create a `SharedDownloadState` struct in a shared Swift file (accessible to both targets) containing: total active downloads count, total download speed, total upload speed, and an array of the top 3-5 active tasks (title, progress, speed, status). Encode as JSON to the shared UserDefaults.

4. **Widget types:**
   - **Small widget:** Shows total active downloads count, combined download speed
   - **Medium widget:** Shows list of top 3 active downloads with progress bars and speeds
   - **Lock Screen widgets (WidgetFamily.accessoryCircular / accessoryRectangular):** Circular shows download count, rectangular shows top download name + progress

5. **Timeline:** Use a short timeline (refresh every 5-15 minutes via `TimelineReloadPolicy.after`). Also call `WidgetCenter.shared.reloadAllTimelines()` from the main app whenever task state changes significantly (download completes, new download starts).

6. **Live Activities** (ActivityKit):
   - Define a `DownloadActivityAttributes` struct with `ContentState` containing: task title, progress (Double), download speed (Int64), status (String)
   - Start a Live Activity when a download begins (in `TaskListViewModel` when a new downloading task appears)
   - Update it every polling cycle with current progress/speed
   - End it when the download completes or is removed
   - Show on Lock Screen: task name, progress bar, speed
   - Show in Dynamic Island (compact/expanded): progress percentage and speed

**Important:** The widget extension is a separate target with its own `Info.plist`. It needs the shared App Group entitlement. The main app target also needs the App Group entitlement added.

---

## Feature 3: Safari Share Extension

**Goal:** Send any URL from Safari (or any app with a share sheet) directly to Download Station.

**Implementation:**

1. Create a new **Share Extension** target named `TorrentStationShare`.

2. **App Group:** Use the same App Group as the widget (`group.com.torrentstation.shared`). Store NAS credentials in a Keychain access group shared between the main app and the extension (update `KeychainService` to use a shared access group).

3. **Extension UI (`ShareViewController.swift`):**
   - Subclass `SLComposeServiceViewController` or use a custom SwiftUI view via `UIHostingController`
   - Extract the shared URL from `extensionContext?.inputItems`
   - Show a compact view with: the URL being shared, an optional destination folder picker (load recent destinations from shared UserDefaults), and a "Send to NAS" button
   - On submit: create a lightweight `SynologyClient` instance using credentials from the shared Keychain, call `SYNO.DownloadStation.Task` create with the URL, show success/failure, then dismiss

4. **Info.plist activation rule:** Configure `NSExtensionActivationRule` to accept URLs:
   ```
   NSExtensionActivationSupportsWebURLWithMaxCount = 1
   ```

5. **Shared Keychain:** Update `KeychainService` to use a shared access group (e.g. `$(TeamIdentifierPrefix)com.torrentstation.shared`) so both the main app and the extension can read/write credentials.

6. The extension should handle both regular HTTP URLs and `magnet:` links.

---

## Feature 4: NAS System Monitoring (in Settings)

**Goal:** Show Synology NAS hardware info and real-time system metrics. Accessible from Settings by tapping the connection info.

**Synology APIs to use:**
- `SYNO.DSM.Info` (method: `getinfo`, version: 2) — Returns model name, serial number, DSM version, uptime, RAM, temperature
- `SYNO.Core.System.Utilization` (method: `get`, version: 1) — Returns CPU usage, memory usage, network throughput, disk I/O
- `SYNO.Storage.CGI.Storage` (method: `load_info`, version: 1) — Returns volume info, disk health, total/used space

**Implementation:**

1. Create `Services/DSMInfoService.swift` as an `actor` that uses `SynologyClient` to call the above APIs. Define response model structs in `Models/DSMInfo.swift`.

2. Create `ViewModels/NASInfoViewModel.swift` (`@MainActor @Observable`) that loads and polls (every 10 seconds) the system info.

3. **Update `Views/SettingsView.swift`** — Replace the current "Connection" section:
   - Instead of showing "Server" and "Username" as plain `LabeledContent`, show:
     - **"Connected to: Synology DS920+"** (or whatever model `SYNO.DSM.Info` returns) as a `NavigationLink`
     - Below it in secondary text: the server address
   - The username row can stay or move into the detail page
   - Tapping the "Connected to:" row navigates to a new `NASDetailView`

4. Create `Views/NASDetailView.swift`:
   - **Device section:** Model name, serial number, DSM version, uptime (formatted as "X days, Y hours"), RAM amount
   - **System section:** CPU usage (gauge or progress bar), memory usage (used/total with bar), temperature with color coding (green < 50°C, yellow 50-65°C, red > 65°C)
   - **Storage section:** For each volume — name, total/used/free space with visual bar, health status. For each disk — model, serial, size, health status, temperature
   - **Network section:** Current network throughput (receive/transmit speeds)
   - Poll every 10 seconds while the view is visible (use `.task` with a `while !Task.isCancelled` loop, similar to how `TaskListViewModel` polls)

5. Fetch the NAS model name once on login (in `AuthViewModel` or after login completes) so it's available immediately in Settings without navigating to the detail page. Cache it in the view model or shared state.

---

## Feature 5: RSS Feed Support

**Goal:** Let users manage Download Station's RSS feeds and auto-download rules from within the app.

**Synology APIs:**
- `SYNO.DownloadStation.RSS.Site` — List, add, delete RSS feeds
- `SYNO.DownloadStation.RSS.Feed` — List items from a feed

**Implementation:**

1. Create `Services/RSSService.swift` as an `actor` with methods: `listFeeds()`, `addFeed(url:)`, `deleteFeed(id:)`, `listFeedItems(feedId:)`.

2. Create models in `Models/RSSModels.swift`: `RSSFeed` (id, title, url, last updated), `RSSFeedItem` (title, url, date, size).

3. Create `ViewModels/RSSViewModel.swift` (`@MainActor @Observable`).

4. Create `Views/RSSView.swift`:
   - List of subscribed RSS feeds with swipe-to-delete
   - "Add Feed" button that presents a sheet with a URL text field
   - Tapping a feed shows its items in a list
   - Tapping a feed item offers to download it (calls the existing `DownloadStationService.createTask()`)

5. Add RSS as a 4th tab in `ContentView.swift`'s `TabView`, with `systemImage: "dot.radiowaves.up.forward"` or `"antenna.radiowaves.left.and.right"`.

---

## Feature 6: Search Module Browser

**Goal:** Search for content directly from within the app using Download Station's built-in BT search modules.

**Synology APIs:**
- `SYNO.DownloadStation.BTSearch` (method: `list`, version: 2) — List available search modules
- `SYNO.DownloadStation.BTSearch` (method: `start`, version: 2) — Start a search, returns a taskid
- `SYNO.DownloadStation.BTSearch` (method: `list`, version: 2 with taskid param) — Get search results for an ongoing search
- `SYNO.DownloadStation.BTSearch` (method: `clean`, version: 2) — Clean up a search task

**Implementation:**

1. Create `Services/BTSearchService.swift` as an `actor` with methods: `listModules()`, `startSearch(keyword:module:)`, `getResults(taskId:offset:limit:)`, `cleanSearch(taskId:)`.

2. Create models in `Models/BTSearchModels.swift`: `SearchModule` (name, enabled), `SearchResult` (title, seeds, leeches, size, date, downloadURL, module name).

3. Create `ViewModels/SearchViewModel.swift` (`@MainActor @Observable`). Handle the async search pattern: `startSearch` returns a task ID, then poll `getResults` until results stop growing.

4. Create `Views/SearchView.swift`:
   - Search bar at the top
   - Optional module filter (horizontal chip bar showing available/enabled modules)
   - Results list showing: title, size, seeds/leeches counts, source module
   - Tapping a result offers to download it (calls `DownloadStationService.createTask()` with the result's download URL)
   - Loading indicator while search is in progress

5. This could either be a 5th tab or integrated into the Add tab as a search mode (segmented control: "URL" / "Search"). The Add tab integration is probably cleaner — avoids too many tabs.

---

## Implementation Order (suggested)

1. **Feature 4 (NAS Monitoring)** — Smallest scope, self-contained in Settings, adds immediate value
2. **Feature 1 (QuickConnect)** — Important for usability, touches login flow
3. **Feature 3 (Share Extension)** — New target but reuses existing API logic
4. **Feature 6 (Search)** — New UI but straightforward API
5. **Feature 5 (RSS)** — New tab, new API surface
6. **Feature 2 (Widgets & Live Activities)** — Most complex, needs App Group infrastructure, best done after Share Extension sets up the shared container
