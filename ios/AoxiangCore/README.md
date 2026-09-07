# AoxiangCore contract readiness

This Swift package is a non-UI entry point for the shared Android/iOS behavior
contract. Its tests discover every `contract-fixtures/golden/vN` directory under
the `contract-fixtures/golden` corpus directly from the repository; the fixture
corpus is not copied into this package.

The bundled `contract-capabilities.json` is the machine-readable coverage
record. Foundation-level manifest, schema, path, reference, and secret checks
are `covered`. Each business entry also lists exact `vN/scenario-id` keys, so a
new scenario cannot be hidden by reusing an existing kind. All 15 business
fixture kinds remain explicitly `pending` until their Swift domain adapters
compare real output with the shared expected JSON.
Changing JSON alone cannot claim coverage: a covered kind must also match an
adapter registered in Swift. `requireCompleteBusinessCoverage` therefore fails
by design at this stage.

Readiness CI does not claim business compatibility. Before an iOS release, run
the suite with `AOXIANG_REQUIRE_IOS_BUSINESS_COVERAGE=1`; `ios-v*` tags do this
automatically. The gate remains red until every manifest kind has a real Swift
adapter and is marked covered.

Run on macOS with Xcode's Swift toolchain:

```sh
swift test --package-path ios/AoxiangCore
```

Set `AOXIANG_GOLDEN_FIXTURES` to the `contract-fixtures/golden` corpus root only
when the repository fixture directory is in a nonstandard location. Windows in this repository currently has neither
Swift nor Xcode, so Swift compilation and XCTest execution must be performed by
macOS CI before this package is treated as verified.

## iOS app adapter

`../AoxiangApp` is a separate Swift package containing the SwiftUI main-app
entry point, visible WebKit authentication surface, URLSession adapter for
stable HTTP endpoints, and conditional BackgroundTasks/WidgetKit adapters.
It depends on this Foundation-only package; the dependency direction never
reverses. Add the app-group entitlement
`group.cn.nwpu.aoxiang-assistant` to the Xcode app and widget targets before
using the shared snapshot URL on a device.

The standard Android backup imports only courses, semesters and display
settings, matching the v2.2.2 contract. Grades remain a separate local-only
array (`AndroidGradesImporter`) and are never included in portable backups.
