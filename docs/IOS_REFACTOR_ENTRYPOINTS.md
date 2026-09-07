# iOS Refactor Entrypoints

This note turns the first-phase Android safety work into explicit seams for the
future iOS rebuild. The goal is to keep portable data stable, isolate platform
secrets and sessions, and avoid binding iOS UI decisions to the current
Android `Activity` structure.

## What is now frozen

The portable contract is the shared boundary for both platforms:

- local collections use `{"schemaVersion":1,"items":[...]}`
- schedule backup uses
  `format: "aoxiang-assistant.schedule-backup"` + `schemaVersion: 1`
- credentials, cookies, SMS codes, auth state, GPA, electricity, and update
  scheduler state remain platform-private

Source of truth:

- [LOCAL_DATA_CONTRACT.md](./LOCAL_DATA_CONTRACT.md)
- Android contract adapters:
  [LocalDataContract.java](../app/src/main/java/cn/nwpu/campus/LocalDataContract.java),
  [BackupContract.java](../app/src/main/java/cn/nwpu/campus/BackupContract.java),
  [LocalDataStore.java](../app/src/main/java/cn/nwpu/campus/LocalDataStore.java),
  [ScheduleStorage.java](../app/src/main/java/cn/nwpu/campus/ScheduleStorage.java)

## Safe iOS architecture split

Keep the iOS rebuild split into four layers.

| Layer | Responsibility | Android reference | iOS target |
| --- | --- | --- | --- |
| Portable contract | JSON schema, migration, backup validation | `LocalDataContract`, `BackupContract` | `PortableDataContract.swift`, `ScheduleBackupContract.swift` |
| Local persistence | Reading/writing app-private files or defaults | `LocalDataStore`, `ScheduleStorage` | `LocalDataStore.swift`, `ScheduleStore.swift` |
| Domain services | Import, normalization, diffing, widget-safe snapshots | `ScheduleImport`, `ScheduleUtils`, `UpdateDiff` | `ScheduleImportService`, `ScheduleNormalizer`, `ScheduleSnapshotService` |
| UI / orchestration | Screens, edit flows, sync triggers, error presentation | `MainActivity`, widgets, background service | SwiftUI/UIKit views + coordinators/view models |

The key rule is: iOS views should never own JSON migration logic, backup
validation, or secure-session policy.

## Seams to preserve during the rebuild

### 1. Portable schedule seam

Input/output:

- semester list
- course list
- selected semester id
- theme + dark mode
- import/export backup JSON

Required guarantees:

- unknown or future schema must fail closed
- invalid reads must not overwrite stored bytes
- `course.semesterId` must reference a real semester
- failed save must not look like success in UI state

### 2. Secure identity seam

Input/output:

- credentials
- WebView/session cookies
- SMS verification state

Required guarantees:

- stays out of backup and portable fixtures
- stored in Keychain / `WKWebsiteDataStore`
- imported schedule data never mutates auth/session state

### 3. Device-independent domain seam

This is where schedule parsing, week calculations, diffing, and imported-data
normalization should live. It is the best place to maximize reuse between
Android and iOS because it is mostly deterministic logic with low platform
coupling.

### 4. UI edit seam

Manual add/edit/delete flows should call one save boundary and react only to a
`success/failure` result. The Android first-phase fix already codifies the
behavior we want on iOS:

- keep pre-edit snapshot
- attempt save
- on failure restore previous in-memory state
- keep the editor open or show a clear failure state

## Recommended rebuild order

1. Port the portable contract tests and shared fixtures to Swift tests first.
2. Implement iOS local persistence against the frozen contract.
3. Port schedule domain helpers next, keeping them UI-agnostic.
4. Build the schedule list/detail/edit UI only after save/load failures can be
   surfaced from the persistence seam.
5. Add widgets/app-group snapshots after the main app store is stable.
6. Leave login/session automation and device integration out of the first iOS
   pass unless the portable seam is already green.

## Practical “least risky” strategy

- Keep Android and iOS writing the same portable JSON as long as possible.
- Prefer additive adapters over one large cross-platform rewrite.
- Move logic out of screens only when the extracted seam has a test.
- Treat import/export, manual edit, and first-launch migration as release gates.
- Do not let iOS refactor pressure widen the backup scope to include secrets or
  transient sync state.

## First checks before starting iOS UI work

- Re-run fixture-backed contract tests on both platforms.
- Verify one legacy local array migrates to schema `1`.
- Verify one legacy `version: "2.0"` backup imports and re-exports as schema `1`.
- Verify a failed write leaves the previous local file untouched.
- Verify an invalid backup with a dangling `semesterId` is rejected.

## Third-to-fifth-stage implementation map

The current branch includes two Swift packages:

- `ios/AoxiangCore`: Foundation-only portable models, strict Android backup and
  local-grade importers, atomic stores, edit rollback, widget-safe snapshots,
  authentication state machine, collection policy, and best-effort sync coordinator.
- `ios/AoxiangApp`: SwiftUI offline screens (Home/Grades/Schedule/Management),
  Android backup file importer/exporter, visible `WKWebView` + shared
  `WKHTTPCookieStore` authentication, stable-HTTP `URLSession` adapter, and
  conditional `BGAppRefreshTask`/`BGProcessingTask` plus notification adapter.

The main app writes a versioned snapshot to the App Group container; the widget
only uses `WidgetSnapshotReader`. It has no reference to credentials, cookie
values, authentication state, collectors, or BackgroundTasks. Background jobs
never instantiate a WebView. If the session is expired or a SMS challenge is
required, the coordinator records `needsUserAttention`, keeps the last good
snapshot, and asks the user to open the main app.

The normal verification commands on macOS are:

```sh
swift test --package-path ios/AoxiangCore
swift test --package-path ios/AoxiangApp
```
