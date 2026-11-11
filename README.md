# OpenGuard

**Self-discipline app blocking for iOS** — powered by Apple's Screen Time API.

OpenGuard is a native iOS app that lets you permanently shield distracting apps and grant yourself a limited number of daily "opens" — each lasting a configurable time window before the shield automatically returns.

> **Not a parental control tool.** OpenGuard is designed for adults who want to manage their own screen time with intentional friction.

---

## How It Works

1. **Authorize** — Grant Screen Time permission via Face ID (individual authorization, no child account needed).
2. **Add apps** — Pick apps from the system app picker. They are immediately shielded.
3. **Open when needed** — Tap the shield to spend one of your daily opens. The shield drops for the configured time (e.g., 10 minutes), then automatically returns.
4. **Daily reset** — Each midnight, all open counters reset.

### Key Concepts

| Concept         | Description                                                                |
| --------------- | -------------------------------------------------------------------------- |
| **Shield**      | A system overlay that blocks access to an app (via `ManagedSettingsStore`) |
| **Open**        | A temporary unblock window — each app has a configurable number per day    |
| **Time Limit**  | How long each open window lasts before the shield re-engages               |
| **Daily Reset** | All open counters reset at midnight via `DeviceActivityMonitor`            |

---

## Architecture

```
OpenGuard/                     # Main app target
├── App/                       # App entry point, ContentView
├── Stores/                    # BlockListStore, CloudSyncManager
└── Views/                     # SwiftUI views (Onboarding, BlockList, Settings)

Shared/                        # Code shared across all 4 targets
├── Constants.swift            # App group IDs, defaults
├── BlockedAppData.swift       # Data models (Codable)
├── SharedDataStore.swift      # Process-safe JSON persistence (NSFileCoordinator)
├── ShieldManager.swift        # ManagedSettingsStore shield operations
└── NotificationManager.swift  # Local notification scheduling

ShieldConfigurationExtension/  # Custom shield UI (ManagedSettingsUI)
ShieldActionExtension/         # Handles "Open" / "Dismiss" button taps
DeviceActivityMonitorExtension/ # Midnight reset & ticker for expired windows
```

All four targets share the `Shared/` directory and communicate through a JSON file in the App Group container, protected by `NSFileCoordinator`.

---

## Requirements

- **iOS 17.0+**
- **iPhone only** (Screen Time APIs are not available on iPad in the same way)
- **Physical device required** — Screen Time / FamilyControls APIs do not work in the iOS Simulator
- **Family Controls entitlement** — Must be requested from Apple via [developer.apple.com](https://developer.apple.com) for distribution

## Building

### Prerequisites

- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Steps

```bash
# Generate the Xcode project from project.yml
xcodegen generate

# Open in Xcode
open OpenGuard.xcodeproj

# Set your Development Team in Xcode → Signing & Capabilities
# Build and run on a physical device
```

> **Note:** You must set `DEVELOPMENT_TEAM` in `project.yml` or in Xcode's Signing settings before building for a device.

---

## Configuration

Each blocked app can be individually configured:

- **Opens per day**: 1–20 (default: 3)
- **Time per open**: 5min, 10min, 15min, or custom 1–120 minutes (default: 10 minutes)

Settings are backed up via `NSUbiquitousKeyValueStore` (iCloud Key-Value Store) for recovery after reinstalls.

---

## Privacy

- **No server, no analytics, no tracking.** All data stays on-device (and optionally in your personal iCloud KV store).
- Screen Time authorization uses `.individual` mode — no MDM, no child accounts.
- The app never sees which apps you use or for how long — it only manages shields.

---

## License

MIT

---

## Acknowledgments

Built with Apple's [Screen Time API](https://developer.apple.com/documentation/familycontrols) frameworks:

- FamilyControls
- ManagedSettings / ManagedSettingsUI
- DeviceActivity
