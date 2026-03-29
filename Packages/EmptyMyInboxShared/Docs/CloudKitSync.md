# CloudKit app-state sync

## Scope

- **In scope**: Durable app preferences stored as JSON under Application Support (`emptyMyInbox/`): interest profile, account inclusion flags, stories feed state, LLM **non-secret** settings file, and a **summary** of the email action outbox (counts/metadata only).
- **Out of scope**: Gmail mail bodies, caches (`EmailCache`, `DashboardCache`, …), and the OpenAI API key (keychain per device).

## Container

- Identifier: `iCloud.aysersHobbies.emptyMyInbox` (`AppCloudKitConfiguration.containerIdentifier`).
- Add this container to **both** iOS and macOS targets in Xcode (Signing & Capabilities → iCloud → CloudKit).

## Record model

| Record type | Stable name | Fields |
|-------------|-------------|--------|
| `InterestProfile`, `AccountInclusions`, `StoriesFeed`, `LLMSettings`, `ActionOutboxSummary` | `singleton-<RecordType>` | `payload` (`Data`), `updatedAt` (`Date`) |

## Conflict strategy

- **Last-write-wins** per singleton record: each save overwrites the previous server record; `updatedAt` is informational.
- Local files are replaced on pull before in-memory stores are invalidated (`AppStateCloudSync.pullMergeAndReloadStores()`).

## Lifecycle

- **Startup**: `AppLifecycleCloudSync.performStartupSync()` — pull, reload stores, push.
- **After local changes** (optional): `AppLifecycleCloudSync.pushLocalStateOnly()` — e.g. when settings screens dismiss.

## Developer Console

Create the container and deploy the schema (record types) in CloudKit Dashboard if automatic creation is disabled for your team.
