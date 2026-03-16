# TorrentStation (SynoTorrent)

A native SwiftUI iOS app for managing Synology NAS downloads via Download Station, with integrated Plex Media Server playback and on-device media streaming.

## Features

### NAS Connection & Authentication
- Login with Synology NAS address, port, username, and password
- HTTPS/HTTP toggle with automatic port switching (5000/5001)
- Persistent sessions via Keychain — auto-login on launch
- Network scanning to auto-discover Synology NAS devices on the local /24 subnet

### Download Management
- **Task list** with real-time polling (3-second interval) showing all Download Station tasks
- **Filter bar** — All, Downloading, Seeding, Paused, Completed, Error
- **Task cards** showing title, status badge, progress bar, download/upload speeds, and sizes
- **Batch operations** — Select multiple tasks to pause, resume, or delete
- **Swipe actions** — Swipe right to resume/pause, swipe left to delete
- **Context menus** — Long press for pause/resume/delete/play options
- **Global speed display** — Combined download/upload speeds at the top

### Task Detail View
- Tap any task card to see full details:
  - Status and progress
  - Transfer stats: download/upload speed, downloaded/total size, uploaded amount, ratio, ETA, average speed
  - Details: date added, elapsed time, destination folder, total size
  - File list: all files in the torrent with type icons and sizes
  - Playback section: Plex and on-device player options
  - Actions: pause/resume, delete

### Add Downloads
- Paste magnet links or download URLs
- **Destination folder picker** — browse NAS shared folders and subfolders via FileStation API
- **Recent destinations** — tracks the 3 most recently used download locations (persisted to UserDefaults), shown at the top of the folder picker
- Pre-selects the last used destination on launch
- After submitting, automatically switches to the Downloads tab with "Downloading" filter

### Magnet Link Deep Linking
- Registered URL scheme handler for `magnet:` URIs
- Tapping a magnet link in Safari opens the app and pre-fills the Add tab
- Configured via `CFBundleURLTypes` in Info.plist

### Plex Media Server Integration
- **Server configuration** in Settings — address, port, HTTPS toggle
- **Plex PIN-based OAuth sign-in** — "Sign in with Plex" button opens Safari for authorization, polls plex.tv for auth token
- **Network scanning** to discover Plex servers on the local network
- **Auto-discovery** — background checks all finished/seeding/paused tasks against Plex library
- **Plex icon** on task cards when media is found in a Plex library
- **Persistent cache** — Plex media matches stored in UserDefaults, survive app restarts
- **Smart media search** — cleans torrent titles (removes quality tags, brackets, file extensions) and searches Plex by title, then by file path
- **Library scan trigger** — if media isn't found, triggers a Plex library scan with retry logic (3 attempts at 5s/10s/10s intervals)
- **Outside library detection** — warns when downloads are in a folder Plex doesn't watch
- **Remote playback** — play media on any Plex client (Apple TV, etc.) via plex.tv resources API, with correct server machineIdentifier

### On-Device Media Playback
- **Native playback** for MP4/MOV/M4V via AVPlayer
- **VLC integration** via `vlc-x-callback://` URL scheme for MKV, AVI, etc.
- **Share sheet** for opening in other apps (Infuse, etc.)
- **Safari fallback** for direct streaming
- Media file detection based on file extensions and torrent title keywords

### Download Notifications
- Push notifications when downloads transition to seeding or complete
- Requested on first launch via `UNUserNotificationCenter`

## Architecture

### Pattern
MVVM with `@Observable` (Observation framework). No Combine — uses Swift async/await throughout.

### Concurrency Model
- Services are `actor`-based for thread-safe concurrent API access
- Model structs are `nonisolated` and `Sendable` for safe cross-actor data passing
- ViewModels are `@MainActor` `@Observable` classes
- Swift 6 concurrency compliant

### App Entry Point
`TorrentStationApp.swift` — Creates all services and view models, wires them together. Handles magnet link `.onOpenURL` and post-download tab switching.

### Navigation
Three-tab `TabView` with programmatic tab selection:
- **Downloads** (tab 0) — `TaskListView` with `NavigationStack` for detail drill-in
- **Add** (tab 1) — `AddTaskView`
- **Settings** (tab 2) — `SettingsView` with `PlexSettingsSection`

## File Structure

```
TorrentStation/
├── TorrentStationApp.swift          # App entry, DI, URL handling
├── ContentView.swift                # Auth gate + MainTabView
│
├── Models/
│   ├── ConnectionConfig.swift       # NAS connection config (address, port, HTTPS)
│   ├── SynologyAPI.swift            # API response types, DownloadTask, TaskStatus,
│   │                                  FileItem, TaskFilter, error types
│   └── PlexAPI.swift                # Plex response types, PlexConfig, PlexMediaStatus,
│                                      PlexResource, PlexMediaItem, error types
│
├── Services/
│   ├── SynologyClient.swift         # HTTP client for Synology APIs (API discovery,
│   │                                  session management, request building)
│   ├── AuthService.swift            # Login/logout, session persistence via Keychain
│   ├── DownloadStationService.swift # Task CRUD: list, create, pause, resume, delete,
│   │                                  statistics. Supports destination parameter
│   ├── FileStationService.swift     # File browsing, shared folders, streaming URLs,
│   │                                  path resolution (DownloadStation → FileStation paths)
│   ├── PlexService.swift            # Plex API: library sections, media search (by title
│   │                                  + file path), scan triggers, client discovery via
│   │                                  plex.tv, remote playback, PIN auth, title cleaning
│   ├── KeychainService.swift        # Generic Keychain wrapper for secure storage
│   └── NetworkScannerService.swift  # /24 subnet scanner using NWConnection TCP probes,
│                                      identifies Synology (ports 5000/5001) and Plex
│                                      (port 32400) via API verification
│
├── ViewModels/
│   ├── AuthViewModel.swift          # Login state, auto-login, network scan for NAS
│   ├── TaskListViewModel.swift      # Task polling, filtering, batch actions, download
│   │                                  notifications, media playback trigger
│   ├── AddTaskViewModel.swift       # Download submission, destination selection, recent
│   │                                  destinations persistence, magnet link handling
│   └── PlexViewModel.swift          # Plex config management, media status cache
│                                      (with UserDefaults persistence), auto-check,
│                                      scan triggers, playback initiation, PIN sign-in,
│                                      Plex server network discovery
│
├── Views/
│   ├── LoginView.swift              # NAS login form with network scan button,
│   │                                  DevicePickerSheet (reusable)
│   ├── TaskListView.swift           # Download list with NavigationLink to detail,
│   │                                  filter bar, batch action bar, Plex client picker
│   ├── TaskDetailView.swift         # Full task details: stats, file list, Plex + on-device
│   │                                  playback, pause/resume/delete actions
│   ├── AddTaskView.swift            # URL/magnet input, destination picker, submit
│   ├── SettingsView.swift           # Connection info, Plex settings, app info, logout
│   ├── PlexSettingsSection.swift    # Plex server config, sign-in, test, network scan
│   ├── MediaPlayerView.swift        # AVPlayer for native formats, VLC/share/Safari
│   │                                  for non-native formats. MediaLoadingView for
│   │                                  file discovery and streaming URL resolution
│   └── Components/
│       ├── TaskCardView.swift       # Individual task card with progress, speeds, Plex icon,
│       │                              context menu, swipe actions
│       ├── FilterChipBar.swift      # Horizontal scrolling filter chips with counts
│       ├── ProgressBarView.swift    # Gradient progress bar colored by status
│       ├── SpeedBadgeView.swift     # Global download/upload speed display
│       ├── FolderPickerView.swift   # NAS folder browser with recent destinations
│       └── PlexClientPickerView.swift # Plex client selection for remote playback
│
├── Utilities/
│   ├── Theme.swift                  # Colors (accent #00D4AA), fonts, spacing constants
│   └── Formatters.swift             # Bytes, speed, ETA, progress formatting
│
└── Assets.xcassets                  # App icons, accent color
```

## Synology APIs Used

| API | Purpose |
|-----|---------|
| `SYNO.API.Info` | API discovery and path resolution |
| `SYNO.API.Auth` | Session authentication |
| `SYNO.DownloadStation.Task` | List, create, pause, resume, delete tasks |
| `SYNO.DownloadStation.Statistic` | Global download/upload speeds |
| `SYNO.FileStation.List` | Browse files and shared folders |
| `SYNO.FileStation.Download` | Stream files via HTTP |

## Plex APIs Used

| Endpoint | Purpose |
|----------|---------|
| `/library/sections` | List library sections |
| `/library/sections/{key}/all` | Search media by title or list all items |
| `/library/sections/{key}/refresh` | Trigger library scan |
| `/identity` | Server identification during network scan |
| `plex.tv/api/v2/resources` | Discover clients and server machineIdentifier |
| `plex.tv/api/v2/pins` | PIN-based OAuth authentication |
| `app.plex.tv/auth` | Browser-based authorization |
| `/player/playback/playMedia` | Remote playback command to clients |

## Key Design Decisions

- **Dark mode only** — `.preferredColorScheme(.dark)` set at the app level
- **No Combine** — Uses Swift async/await and `@Observable` throughout
- **Actor-based services** — All network services are actors for thread safety
- **`nonisolated` model structs** — All API response types are `nonisolated` and `Sendable` to cross actor boundaries without warnings
- **Insecure TLS delegate** — `InsecureCertDelegate` allows self-signed certificates common on home NAS setups
- **Dual session management** — Separate SIDs for DownloadStation and FileStation APIs, with fallback sharing
- **Plex title cleaning** — Multi-strategy search: clean title → strip year/brackets → file path matching
- **Plex cache persistence** — Found media stored in UserDefaults as `PlexFoundInfo` (mediaKey + sectionKey), restored on launch
- **Recent destinations** — Last 3 used download folders persisted and shown at top of folder picker
