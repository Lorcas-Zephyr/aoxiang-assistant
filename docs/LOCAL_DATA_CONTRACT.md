# Local Data and Backup Contract

This document freezes the portable data boundary introduced for the iOS
refactor. It is based on Android `v2.2.2` behavior and is the source of truth
for new Android and iOS writers. It covers data that may be migrated between
app versions or exported by the user; it does not turn platform credentials or
web sessions into portable data.

The canonical, fully fictional test inputs are under
[`contract-fixtures/`](../contract-fixtures/). They are shared test assets, not
sample user records.

## Compatibility Rules

All JSON is UTF-8. Object member order is insignificant. Readers must preserve
an original value when its schema is unknown or invalid; they must never
replace it with an empty collection as a side effect of a failed read.

| Data | Legacy input | Current write shape | Migration rule |
| --- | --- | --- | --- |
| Local JSON collections | Bare array (schema `0`) | `{"schemaVersion": 1, "items": [...]}` | Decode the array, then write schema `1` only after successful decoding. |
| Schedule backup | `version: "2.0"`, with `courses` and `settings` and no `format`/`schemaVersion` | `format: "aoxiang-assistant.schedule-backup"`, `schemaVersion: 1`, plus the compatible `version: "2.0"` marker | Validate the legacy document, materialize the canonical in-memory form, then write schema `1` on the next export. |

`schemaVersion` is an integer. Version `0` is reserved for the legacy local
bare-array shape, and version `1` is the current shape. A reader that sees a
version greater than its supported version must fail closed and leave the
stored bytes untouched. It must not silently downgrade, erase, or rewrite the
value. Missing or malformed schema markers are invalid except for the
explicitly defined legacy forms above.

## Local Collections

The Android preferences namespace is `campus_private`. Its versioned JSON
collection keys are `grades`, `schedule_semesters`, and `schedule_courses`.
The key name is an Android implementation detail; the envelope and item JSON
are the cross-platform contract.

```json
{
  "schemaVersion": 1,
  "items": []
}
```

An absent or empty local value means an empty legacy collection. New writers
always emit the envelope. The iOS implementation may use an Application
Support file or `UserDefaults`, but it must retain this JSON representation and
the unsupported-schema protection above.

### Grade Item

`grades.items[]` uses the existing `GradeRecord` wire shape:

| Field | Type | Notes |
| --- | --- | --- |
| `course` | string | Display course name. |
| `credits` | number | May be `0`. |
| `point` | number or `null` | Grade point. |
| `score` | number or `null` | Numeric score. |
| `category` | string | Defaults to `"课程"` in the Android reader. |
| `detail` | string | Sanitized display detail; not an authentication field. |

Grades are local, non-secret user data, but are deliberately outside the
portable schedule backup in version `1`.

### Schedule Item Types

`schedule_semesters.items[]` uses:

| Field | Type |
| --- | --- |
| `id`, `name`, `startDate`, `endDate` | string |
| `weekCount`, `sectionCount` | integer |
| `sectionTimes` | array of `{ "start": "HH:mm", "end": "HH:mm" }` |

`schedule_courses.items[]` uses:

| Field | Type |
| --- | --- |
| `id`, `name`, `semesterId` | string |
| `timeSlots` | array of time-slot objects |
| `code`, `location`, `teacher`, `notes`, `color` | string or `null` |
| `credits` | number or `null` |
| `assessmentMethod` | enum string or `null` |

A time-slot object has `weekRange` (string), `repeatRule` (enum string),
`dayOfWeek` (integer `1` through `7`), `classSections` (integer array), and
`teacher` and `location` (string or `null`).

## Backup Document

The current portable backup is a JSON object with this top-level shape:

```json
{
  "format": "aoxiang-assistant.schedule-backup",
  "schemaVersion": 1,
  "version": "2.0",
  "exportDate": "YYYY-MM-DD",
  "courses": [],
  "settings": {
    "semesters": [],
    "themeColor": "#2F80ED",
    "darkMode": false,
    "selectedSemesterId": ""
  }
}
```

`courses` contains the course item type above. `settings.semesters` contains
the semester item type above. `selectedSemesterId` is an empty string when no
semester is selected; otherwise it is the exact opaque `id` of an entry in
`settings.semesters`. `themeColor` is a color string, and `darkMode` is a
boolean. Importers must require `courses` and `settings`; an absent
`settings.semesters` in a legacy `2.0` document is treated as an empty array.

The `version: "2.0"` member remains present so existing v2.2.x tooling can
identify the document. New code must use `format` and `schemaVersion` to make
compatibility decisions, not infer a version from optional payload fields.

The backup has a deliberately narrow scope. It includes only schedule courses,
semesters, theme color, dark-mode preference, selected semester, and the
export calendar date. It excludes grades, GPA, electricity readings,
auto-update settings and scheduling state, data revision counters, user
identity, and every authentication or session value.

## Wire Values, Dates, and IDs

Use these exact values on every writer:

| Value | Allowed wire values |
| --- | --- |
| `repeatRule` | `""` (all weeks), `"仅单周"`, `"仅双周"` |
| `assessmentMethod` | `"考试"`, `"考察"`, `"PnP"`, or JSON `null` |
| Calendar date | `YYYY-MM-DD` |
| Section time | `HH:mm`, 24-hour, zero-padded |
| Runtime timestamp | Unix epoch milliseconds as a JSON number when a runtime-only record needs one |

Business calendar calculations use `Asia/Shanghai`. A date-only value is a
calendar date in that business timezone, not an instant, and must not be
shifted when imported on a device with another timezone. New platform code
must generate dates using this timezone explicitly.

Course IDs and semester IDs are opaque stable strings. They have no prescribed
format, must be exported/imported byte-for-byte, and must not be parsed for
meaning or regenerated during a migration. New records must receive an ID
before they are persisted.

Android v2.2.2 maps an unrecognized `repeatRule` to `""` and an unrecognized
`assessmentMethod` to `null`; that legacy parser behavior is not a safe
round-trip guarantee. The portable backup contract now rejects an unknown enum
before import or export. Local readers may retain an unknown wire value for
recovery, but a read-modify-write path must not serialize an inferred fallback;
it must either preserve the raw record or reject the write without replacing
stored data. Unknown object members must also survive a cross-version
round-trip, either by retaining the raw JSON or by rejecting the write without
replacing stored data.

The Android contract implementation retains unknown members inside course,
semester, section-time, and time-slot records. It cannot retain unknown
members added to the backup envelope or `settings`, so those members are
rejected before import or migration rather than silently dropped. A migration
also runs the complete identifier validation before writing schema `1`.
Export runs the same identifier and reference-integrity validation before a
document is returned, so Android cannot emit a backup that iOS must reject.
`exportDate`, when present, must be a valid `YYYY-MM-DD` calendar date; invalid
dates are rejected rather than replaced with the current date.

## Security and Platform Boundaries

Portable backups are user-shareable files. They must never contain passwords,
account names, encrypted credential blobs, bearer tokens, WebView cookies,
SMS verification codes, or authentication/synchronization state. A fixture
must never contain those values either.

| Boundary | Android | iOS | Backup rule |
| --- | --- | --- |
| Credentials | Android Keystore-protected `login_credentials` blob | Keychain item | Never export or import. |
| Web session | `CookieManager` cookie store | `WKWebsiteDataStore` cookie/data store | Never export or import. |
| SMS verification code | Runtime-only input | Runtime-only input | Never persist in the contract or export. |
| Scheduled sync/auth state | Private preference/runtime state | Private app/runtime state | Never export; rebuilding it requires a new platform session. |
| Widget data | Non-sensitive display snapshot only | App Group non-sensitive display snapshot only | A widget must not receive credentials or session state. |

Importing a backup must not clear, restore, or validate credentials and must
not mutate the WebView cookie store. It updates only the backup fields after
the entire document has been validated.

Readers recursively reject field names that identify credentials or session
state, including `password`, `credential`, `token`, `cookie`, `auth`, `account`,
`studentId`, `sms`, `captcha`, and `login` variants. This check applies to
unknown record members as well as the fixed envelope, so a future field cannot
accidentally turn a portable backup into a secret-bearing export.

## Fixture and Test Contract

The fixtures are intentionally small and are loaded as test resources from the
repository-root `contract-fixtures` directory:

| Fixture | Purpose |
| --- | --- |
| `backup/v1/minimal_schedule_backup.json` | Current minimal portable backup with one fictional course and semester. |
| `local/v1/grades.json` | Current versioned grade collection with two fictional records. |
| `collection/v1/phases.json` | Runtime-only collection phase names; it is not backup payload data. |

The second-phase behavioral corpus is under
[`contract-fixtures/golden/`](../contract-fixtures/golden/). Its versioned manifests and
scenario files are shared by Android JVM tests and the future iOS XCTest target;
see [`docs/GOLDEN_FIXTURES.md`](GOLDEN_FIXTURES.md) for the path and security rules.

Android's `ContractFixtureTest` checks that these resources are on the unit
test classpath and that the backup fixture contains none of the prohibited
sensitive-key strings. A Swift test target should load the same files directly
from the repository and validate the same schema and safety properties.
