# Cross-device app state (optional)

## Default: local-only (no paid Apple Developer Program)

**iCloud and CloudKit require** an Apple Developer Program membership to use container entitlements in a shippable way. This project therefore **does not call CloudKit** at runtime: `AppStateCloudSync` and `AppLifecycleCloudSync` are **no-ops** so you can build and run on a free Apple ID.

- Durable settings still live as JSON under Application Support on each device.
- **There is no automatic sync between Mac and iOS** until you add either:
  - **Paid program + iCloud**: reintroduce CloudKit in `AppStateCloudSync.swift`, add iCloud capabilities, and use the same container on both targets; or
  - **Your own backend** (or another sync service) and wire it through the same call sites.

## If you join the Developer Program later

1. Add **iCloud → CloudKit** in Xcode for both targets and create container `iCloud.aysersHobbies.emptyMyInbox` (or change `AppCloudKitConfiguration.containerIdentifier`).
2. Replace the no-op implementation in `AppStateCloudSync.swift` with CloudKit push/pull of the JSON payloads (see git history or Apple’s CloudKit docs).
3. Restore **entitlements** on iOS/macOS targets for that container.

## Secrets

OpenAI API keys and similar stay in the **keychain per device**; do not put secrets in CloudKit records.
