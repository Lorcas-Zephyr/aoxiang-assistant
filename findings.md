# Findings

## Baseline

- 当前分支起点为 `main` 的 `v2.2.2`，Android 单模块 Java 项目。
- CodeGraph 索引：85 files、1,451 nodes、4,577 edges，索引健康。
- `MainActivity.java` 5,218 行，承担 UI、WebView 采集、认证、存储、通知、后台调度、备份和更新检查。
- `BackgroundSyncService.java` 816 行，另有一套 WebView 轮询和 phase dispatch。

## Existing backup (v2.2.2)

`MainActivity.exportBackup` 生成：

- `version: "2.0"`
- `exportDate: YYYY-MM-DD`
- `courses: Course[]`
- `settings.semesters: Semester[]`
- `settings.themeColor: String`
- `settings.darkMode: Boolean`

它不包含成绩、GPA、电费、自动更新状态、同步时间、认证凭据、WebView Cookie 或短信验证码。导入要求 `courses` 和 `settings`，缺少 `settings.semesters` 时按空列表处理。

## Existing local storage

- SharedPreferences 文件名：`campus_private`
- `grades`、`schedule_semesters`、`schedule_courses` 是裸 JSON 数组。
- 选中学期、主题和深色模式是独立 key。
- `login_credentials` 是 Android Keystore AES-GCM 密文；Cookie 在 WebView CookieManager 中，不属于 JSON 数据。
- Widget、Activity 和后台服务都直接消费 SharedPreferences，因此迁移必须覆盖所有消费者。

## Stable wire values to preserve

- `RepeatRule`: `""`、`"仅单周"`、`"仅双周"`
- `AssessmentMethod`: `"考试"`、`"考察"`、`"PnP"` 或 JSON null
- 日期：ISO-8601 calendar date `YYYY-MM-DD`
- 时间：24 小时制 `HH:mm`
- 课程/学期 ID：不透明字符串，导入导出原样保留；新写入必须显式携带

## Security boundary

普通备份可被用户分享，不能包含密码、账号密文、Cookie、认证 token、短信验证码、学生唯一身份信息或同步调度内部状态。凭据留在 Android Keystore / iOS Keychain；会话留在各平台 WebView cookie store；Widget 只读脱敏数据快照。

## First-phase verification status

- `:app:testDebugUnitTest --offline` 已在本机 SDK 环境下通过；当前汇总为 15 个测试套件、
  92 个测试、0 failures、0 errors、0 skipped。
- `:app:assembleDebug --offline` 通过。
- `:app:lintDebug --offline` 通过并生成
  `app/build/reports/lint-results-debug.html`；报告含既有基线问题（如 Widget XML 的
  API 31 属性、硬编码预览文本、后台权限策略提示），但本轮触达的本地契约/备份路径
  未出现新的 lint 失败。
- 课表消费者入口已统一到 `ScheduleStorage` / `LocalDataStore`：
  `MainActivity`、`BackgroundSyncService`、`ScheduleWidgetData`、`HomeWidgetSupport`
  都通过这两个 seam 访问本地数据，而不是直接拼接 JSON。
- 本地集合解析失败会作为显式失败向上传递；备份导入和导出共用 ID、重复项、
  引用完整性及敏感字段校验，不生成跨平台消费者必然拒绝的文件。

## iOS refactor entrypoint

- 已新增 [docs/IOS_REFACTOR_ENTRYPOINTS.md](./docs/IOS_REFACTOR_ENTRYPOINTS.md)，把后续 iOS
  重构拆成 portable contract、local persistence、domain services、UI orchestration
  四层，并列出最小风险的迁移顺序。

## Second-phase fixture audit (2026-09-05)

- 现有可复用的纯 JVM seams：`PortalApiParsers.gradeRows/gpa/schedulePayload/
  electricityBalance`、`GradeRecord.from/keepHighest`、`ScheduleImport.parsePayload/
  parseScheduleText/convertToCourses/createImportedSemester`、`ScheduleUtils` 的周次/
  作息/冲突方法、`AuthenticationPolicy`、`UnifiedAuthTracker` 与 `UpdateDiff`。
- 当前 `contract-fixtures` 只有第一阶段的 backup/local/collection 合同样例；没有覆盖
  用户要求的成绩 HTML、画像回退、课表边界、电费异常、认证结果和通知差异场景。
- 第二阶段 fixture 必须只保存虚构输入与规范化输出，不保存账号、密码、Cookie、token、
  短信验证码、真实学号、姓名、宿舍或可识别地点；HTML fixture 也遵守同一脱敏边界。
- 跨平台 fixture 采用每个场景一个目录：`manifest.json` 列出 `id`、`kind`、`input`、
  `expected`（以及可选 `html`），路径使用 `/`，文件内容 UTF-8；Android 与 iOS 测试
  均以 manifest 驱动而不是各自重新编写样例。
- 认证 fixture 记录状态机可观察结果（例如 `credentials_valid`、`credentials_error`、
  `sms_required`、`interactive_login`/`auth_expired`），不记录认证秘密或会话内容。

## Phase 6 contract hardening (2026-09-05)

- `LocalDataStore.readArrayResult` 当前先迁移再解析领域记录；旧裸数组只要 JSON 语法正确，
  后续 `ScheduleModels.*.from` 失败时原始字节已经被改写。迁移必须延后到领域记录验证成功后。
- `SharedPreferences.Editor.apply()` 立即返回且不能报告磁盘失败；核心契约写入应使用可观察的
  `commit()` 结果。课表数组与选中学期/主题设置应通过同一可报告提交入口，避免 UI 显示一个未完整落盘的状态。
- 文档规定未知枚举在 iOS 读改写时失败，而 Android 当前保留未知 wire value。第一阶段冻结策略为
  拒绝未知 `repeatRule`/`assessmentMethod`，并在备份导入前验证允许值；旧未知值保留在原始本地记录中，
  不能被重写成默认枚举。
- Phase 6 实现后，`ScheduleStorage.load*Result` 先完整解析领域对象，再调用显式
  `LocalDataStore.migrateIfLegacy`；坏旧数组保持原文。`writeArray`/`writeArrays`/`writeScheduleState`
  使用 `commit()` 返回值，且写前验证当前集合和待写集合，防止坏记录被覆盖。
- 备份 `validateForImport` 现在校验课程/学期字段类型、日期 `YYYY-MM-DD`、节次 `HH:mm`、周数/节数、
  星期范围、节次数组和允许枚举；缺失的历史可选字段仍按兼容规则读取。

## Second-phase closeout seam (2026-09-05)

- GPA 的跨平台选择规则由生产入口 `PortalApiParsers.selectGpa(apiGpa, portraitGpa)` 固化：
  合法 API 值优先，API 缺失或非法时使用合法画像值，否则返回 `NaN`。
- `GoldenGradeEdgeFixtureTest` 与 `GoldenGradesFixtureTest` 直接断言该生产 seam；
  `MainActivity` 和 `BackgroundSyncService` 的 API/画像结果分支也经过该入口，避免 Android 测试
  单独重算未来 iOS 需要遵守的选择逻辑。

## Cross-platform synchronization readiness (2026-09-05)

- 最低风险方案不是自动翻译 Android 源码，而是 Ports & Adapters + 双端 contract tests：
  Android 和 iOS 保留各自平台实现，共享可观察行为、数据格式和错误边界。
- 独立 Python validator 防止 fixture 安全门禁依赖任一平台实现；它也能在 Android/iOS
  工具链启动前快速失败。
- Swift readiness 和 Swift behavior compatibility 是两个不同状态。当前 Package 已覆盖
  manifest/schema/path/reference/secret 基础设施，但 15 个业务 kind 均为 `pending`；因此不能
  宣称 iOS 已经实现成绩、课表、电费或认证规则。
- 单靠可编辑 JSON 容易产生虚假覆盖。Swift registry 要求 capability 中的 adapter 名必须与
  代码注册表匹配；未来每落地一个 adapter，需要同时增加其 fixture 输出断言、代码注册和
  capability 状态更新。
- 日常 CI 保持 readiness 可通过，避免永久红灯被团队习惯性忽略；iOS 发布 tag `ios-v*`
  自动切换严格模式，任何 `pending` 都会阻断发布。
- 只把 CLI 默认路径写死为 `golden/v1` 会让未来新建的 `v2` 完全绕过现有 CI。默认入口
  现已提升到 `golden/` corpus，并在 Python/Swift 两侧核对连续版本与 capability 声明。
- `v1` 继续使用已审阅场景的严格清单；`v2+` 允许新增稳定 kebab-case 场景 kind，但每个
  `schemaVersion/id` 都必须由 Android 测试、Swift capability report 和对应 adapter 显式登记，避免扩展时静默漏测。

## 2026-09-09 build-gate finding

- Windows Swift Package tests intentionally exclude `WebKit`/`SwiftUI` conditional source;
  they cannot catch an iOS SDK call-signature error. The visible collector had passed the
  portable suites while using duplicate `in` labels for `callAsyncJavaScript`. Xcode's API
  spelling is `in: nil, contentWorld: .page` (deployment target 15.0).
- The readiness workflow previously reused one DerivedData directory for Simulator and
  device fallback and selected whichever product directory happened to remain. That could
  report a stale Simulator app after a failed build. Readiness now fails on Simulator error,
  writes a successful product-root marker only after completion, and uploads the build log.
- Xcode 26.6 run `34252603142` confirmed the first attempted `contentWorld: .page` repair was
  still wrong at the call-site shape: the current SDK exposes only the async method
  `callAsyncJavaScript(_:arguments:in:contentWorld:) async throws -> Any?`. The completion
  closure must be removed; portable Windows tests cannot see this because the WebKit branch is
  conditionally excluded there.
- Xcode 26.6 run `34254206081` then reached the product build and found a stale template setting:
  Debug `DEVELOPMENT_ASSET_PATHS` referenced a directory absent from the repository. Removing
  that setting is lower-risk than adding a fake preview resource and keeps the shipping target's
  asset surface explicit.
- GitHub branch protection 仍需仓库管理员把三个平台 job 和 trusted PR declaration 设为 required check；仓库内 workflow
  和文档已经准备好，但本地文件不能替代远端规则配置。

## Final sync-readiness audit (2026-09-06)

- Future fixture versions are structurally extensible: `v1` retains its exact reviewed scenario
  registry, while `v2+` accepts only stable kebab-case identifiers and leaves platform coverage
  to explicit Android test registration and the Swift capability report.
- Android `GoldenCorpusCoverageTest` now makes a new corpus scenario (`schemaVersion/id`) fail until
  a named fixture test method is present. This closes the gap where the independent validator could
  pass a fixture that had no Android behavior assertion.
- Swift capability declarations are exact across discovered versions; duplicate or extra version
  declarations fail. Swift path and JSON root checks now match the independent validator's safety
  boundary more closely.
- Current evidence is complete for Windows-executable checks. Swift source was statically reviewed,
  but compile/XCTest evidence is intentionally delegated to the macOS workflow because Windows has
  no Swift/Xcode toolchain. Remote branch protection configuration remains an administrator action.
- The original Gradle setup action reference was not a resolvable commit. It is now pinned to the
  verified v4.4.4 commit; release workflow actions are pinned as well.
- An offline regression test now requires every third-party GitHub Action reference in the repository
  workflows to use a 40-character commit SHA, so future tag drift fails before merge.
- PR declaration validation must not execute validator code from the untrusted PR itself. The trusted
  `pull_request_target` gate checks out only the base SHA and consumes changed paths via the GitHub API;
  platform jobs remain ordinary `pull_request` jobs for actual code validation.

## Third-to-fifth-phase architecture notes (2026-09-06)

- The new goal includes all three iOS delivery stages, but the implementation order remains offline
  first, foreground authentication second, background scheduling last. This preserves a usable app
  when login or network services are unavailable.
- Existing `ios/AoxiangCore` is Foundation-only and intentionally has no business adapter marked
  `covered`; new offline adapters must register against exact `vN/scenario-id` keys before any
  capability is promoted.
- The portable layer must model persistence and authentication as explicit ports. SwiftUI,
  WidgetKit, WebKit and BackgroundTasks adapters should be thin shells so the same fixture-driven
  behavior can be exercised on macOS without UI, WebView or scheduler availability.
- Widget data must be a versioned, sanitized snapshot written by the main app. A widget reader may
  read that snapshot and render it, but must not receive credentials, cookies, network clients,
  authentication state or采集 commands.
- Background execution is best-effort only. A task that cannot prove a valid authenticated session or
  stable HTTP collector must record `needsUserAttention`/retry metadata and exit without motion or
  fake success; visible foreground login remains the recovery path.

## Real-device repair audit (2026-09-08)

- The supplied iPad screenshot contains `grade response unavailable`, which is
  the stable-HTTP collector's explicit failure when every grade endpoint has
  been rejected or redirected. It confirms the older IPA did not have a
  working browser-session collection path.
- The current visible WebView implementation had a separate blocking defect:
  its course-table JavaScript assigned to `const index`, `const semester`, and
  `const print`, so a successful grade response still ended as a retryable
  collection failure before a candidate could be saved.
- The reliable boundary is the visible, same-origin WebView: it owns SSO
  cookies and returns only sanitized grade/schedule/electricity values. The
  collector must still map 401/403 and login HTML to authentication recovery,
  and must request portrait HTML when the GPA endpoint does not provide a
  usable value.
- A Widget-capable IPA must retain the nested `AoxiangAssistantWidget.appex`.
  The current `sideload` and `full-widget` outputs retain that extension;
  `sideload-host-only` deliberately removes it and can never show a Widget.
  The earlier installed `sideload` artifact used the former host-only layout,
  so it is not comparable to the current delivery artifact. A signer still
  has to sign both bundles and authorize their common App Group. This is the
  same technical category as an app such as Notability, not a Settings switch
  that the app can create itself.

## CAS and electricity collection hardening (2026-09-08)

- The electricity bootstrap URL intentionally contains `/cas/login/`, so the
  previous broad redirect matcher classified its first successful navigation
  as an expired session before the YKT page could open. The new
  `VisibleCollectionNavigationPolicy` permits only that exact HTTPS bootstrap
  URL and only once per electricity collection. A later login redirect still
  returns the explicit authentication-required state.
- The visible electricity collector now retries a short same-page evaluation
  while the YKT Vue data is loading, recognizes both Vue 2 and Vue 3 root
  handles, dynamic balance labels, and the Android-compatible rendered text
  formats. It remains bounded by the existing 20-second foreground timeout;
  missing/invalid values never overwrite local data or the Widget snapshot.

## 2026-09-08 foreground collector audit

- The production management view calls `beginCollection()` after the user
  explicitly prepares the authenticated WebView session. Stable education
  endpoints use `URLSessionHTTPCollectionAdapter` with the same
  `WKHTTPCookieStore`; electricity and portrait HTML stay on the visible WebView
  path.
- `PortalForegroundCollector` returns only sanitized domain values. It does not
  pass passwords, Cookie headers, SMS codes, raw WebView state, or raw response
  bytes into `OfflineAppViewModel` or Widget snapshots.
- A collection commit first validates/persists the candidate and then writes the
  shared snapshot. Snapshot failure restores the prior snapshot and local state;
  a missing App Group is an explicit unavailable state rather than a private
  fallback.
- The collector follows Android's semester policy and uses
  `OfflineDatePolicy.businessCalendar` (`Asia/Shanghai`) for its implicit date.
  This closes the date-boundary drift risk between collection and offline
  schedule rendering.
- Remaining evidence gap is operational, not a claimed pass: no Windows test
  can prove `xcodebuild -sdk iphoneos`, nested Widget signing, App Group
  provisioning, or installation on the user's iPad. The prior GitHub Actions
  run `34139741539` succeeded for commit `721f447`, but a new run is needed after
  the current collector changes.

## Foreground collection gap audit (2026-09-08)

- Android v2.2.2 starts a three-target sequence after unified authentication succeeds: `grades`,
  `schedule`, then `electricity`. Each target uses a visible WebView JavaScript path when the portal
  page is JavaScript-dependent; stable same-origin API responses are parsed before local commit.
- Grade collection accepts published rows, removes unpublished rows, keeps the highest record for
  same-name retakes, and selects GPA from the API before the portrait-page fallback. A missing GPA
  must not discard otherwise valid grade rows.
- Schedule collection preserves an empty semester, normalizes teacher/location/week/repeat data, and
  filters online courses according to the existing Android parser contract.
- Electricity collection accepts only finite non-negative values from the expected response shape;
  missing, malformed, negative, or settlement-time responses remain an explicit non-success outcome.
- `VisibleAuthenticationViewModel.prepareToCollect()` remains an explicit state transition, while
  `ManagementScreen.beginCollection()` now owns the foreground driver after that gate. It injects the
  same WebView cookie store into `URLSessionHTTPCollectionAdapter` and keeps portrait/electricity page
  JavaScript on the visible WebView path.
- The driver seam is now implemented: `PortalForegroundCollector` parses responses into a sanitized
  `PortalCollectedData`, and `OfflineAppViewModel.applyPortalCollection` validates/persists the complete
  candidate before publishing state or refreshing Widget timelines. Credentials, cookie values, SMS
  codes, and WebView session state remain outside the candidate and snapshot types.
- The remaining gap is device evidence and portal compatibility, not an absent app connection: Xcode
  device archive, nested extension signing/App Group authorization, and a real post-login collection
  run on iPad still need to be observed.

## iPad-only re-signable IPA constraints (2026-09-07)

- iPhone/iPad builds still require Xcode's iPhoneOS SDK, but the Mac can be a GitHub-hosted
  `macos-latest` runner; the user does not need a personal Mac or a macOS app target.
- The output must remain an unsigned, re-signable `Payload/AoxiangAssistant.app` IPA. It is not an
  installable artifact until the user's own signing tool signs both the host app and the embedded
  `AoxiangAssistantWidget.appex`.
- Apple signing secrets stay outside GitHub source, CI logs, fixtures, backups and planning files.
  Missing App Group authorization does not get a private-container fallback: offline App features keep
  working, while Widget publication and background collection are disabled fail-closed.
- Windows now executes the portable Swift package suites through Swift 6.3.3 plus the Visual Studio
  C++ linker. This validates Core/App seams but cannot validate `xcodebuild`, iPhoneOS archive,
  provisioning or installation; those remain explicit remote/device evidence gaps.

## Third-to-fifth-phase implementation findings (2026-09-06)

- The Android schedule backup contract does not contain grades. iOS therefore exposes a separate
  `AndroidGradesImporter` for the private local array and keeps `OfflineAppState.grades` out of
  `AndroidBackupExporter`; this prevents a convenience import from widening the shareable backup.
- `OfflineDataController` uses a candidate-copy then store-save sequence. The published state is
  updated only after the store accepts the complete validated candidate, so failed edits and imports
  preserve both memory and disk state.
- The WidgetKit-facing source lives in the app adapter package and can only construct a reader for
  the App Group snapshot. The core snapshot schema has no fields for auth, cookies, credentials, or
  collectors, making that boundary structural as well as procedural.
- WebKit authentication is visible and user-driven. Cookie values stay inside `WKHTTPCookieStore`;
  the view model can report cookie names for diagnostics but never serializes values. URLSession is
  selected only for a stable-HTTP capability, while JavaScript pages remain on the WebView path.
- Background scheduling uses `earliestBeginDate` only as a hint and sets task completion false for
  cancellation, retryable failure, SMS, or expired sessions. It does not claim Android-like timing or
  run a hidden WebView.

## iPhone/iPad target and App Group hardening (2026-09-07)

- `macOS` is a toolchain/CI host only. The shipping Xcode App and Widget targets are constrained to
  `iphoneos iphonesimulator`, device family `1,2`, and `SUPPORTS_MACCATALYST = NO`; Swift Package
  `.macOS(.v12)` exists only so Foundation/XCTest can run on a host.
- A Widget snapshot must have one physical shared path. `AoxiangSharedContainer.sharedSnapshotURL`
  returns an App Group URL only on iOS when the entitlement container resolves; it returns `nil` on
  missing capability and on the host. There is no private-directory fallback because that would make
  the App and Widget appear healthy while reading different snapshots.
- `WidgetSnapshotStore` is the shared reader/writer seam. `UnavailableWidgetSnapshotStore` throws
  `OfflineDataError.sharedContainerUnavailable`; the main app surfaces a clear warning while keeping
  local editing, the Widget has no snapshot to render, and the background scheduler does not register
  or schedule collection without a publishable shared snapshot.
- Real-device distribution requires the App and Widget provisioning profiles to enable the same
  `group.cn.nwpu.aoxiang-assistant` App Group. This is an Apple signing/release prerequisite, not a
  macOS product target.

## 2026-09-06 continuation audit

- The first pass of the SwiftUI surface had a literal count string on Home and a no-op semester Picker
  binding. These are user-visible correctness issues and were not covered by the existing Foundation tests.
- `OfflineGrade` values were not validated by `OfflineAppState.validated()`, so a malformed local grade
  could be persisted and then used in widget summaries. Grade IDs and finite score/point/credit bounds
  need the same fail-closed treatment as courses and semesters.
- The background coordinator currently maps an initial `.needsLogin` state to `.invalidCredentials`,
  which conflates "no session yet" with a rejected password. The attention reason must distinguish a
  login-required recovery path without storing any credential material.
- Friendship-campus schedule fixtures distinguish summer and winter section times; the existing
  service only returned the winter table. Week ranges/repeat rules also need to be considered when
  constructing today's widget/home data.
- Windows has no Swift/Xcode compiler. The edits below are driven by XCTest seams and remain subject
  to the macOS workflow as the authoritative compile gate.

## Final hardening audit (2026-09-06)

- Android fixture coverage is now registered by `schemaVersion/id` (`vN/scenario-id`), with exact
  bidirectional comparison against every discovered manifest scenario. This prevents a new scenario
  sharing an existing kind from silently reusing an old test registration.
- Swift capability entries now carry the same `vN/scenario-id` keys and are compared bidirectionally
  with the manifest before readiness succeeds, so Android and iOS declarations cannot drift at the
  scenario identity boundary.
- The trusted PR validator now checks actual changed paths for shared/breaking classifications:
  at least one `contract-fixtures/` file and one independent `expected.json` must be changed. Shared
  Android seams `GradeRecord`, `AuthenticationPolicy`, and `UnifiedAuthTracker` are contract-sensitive
  and cannot be declared platform-only.
- Swift capability remains deliberately fail-closed: all 15 business kinds are `pending`, and a
  release/tag gate fails until a real Swift adapter is registered and covered. Swift's Foundation
  validator is not presented as a byte-for-byte replacement for the Python structural validator;
  Python is the authoritative exact-key/duplicate-key/secret scan in CI, while Swift validates its
  package-side loading and capability boundary.
- Final Windows evidence after hardening: 34 Python/PR/workflow tests, 123 Android JVM tests,
  0 failures/errors/skips, successful Debug APK and lint with 0 errors/189 existing warnings,
  fixture corpus 1 version/15 scenarios/32 referenced files, YAML parse success, and clean diff check.

## Third-to-fifth-phase architecture notes (2026-09-06)

- The new goal includes all three iOS delivery stages, but the implementation order remains offline
  first, foreground authentication second, background scheduling last. This preserves a usable app
  when login or network services are unavailable.
- Existing `ios/AoxiangCore` is Foundation-only and intentionally has no business adapter marked
  `covered`; new offline adapters must register against exact `vN/scenario-id` keys before any
  capability is promoted.
- The portable layer must model persistence and authentication as explicit ports. SwiftUI,
  WidgetKit, WebKit and BackgroundTasks adapters should be thin shells so the same fixture-driven
  behavior can be exercised on macOS without UI, WebView or scheduler availability.
- Widget data must be a versioned, sanitized snapshot written by the main app. A widget reader may
  read that snapshot and render it, but must not receive credentials, cookies, network clients,
  authentication state or采集 commands.
- Background execution is best-effort only. A task that cannot prove a valid authenticated session or
  stable HTTP collector must record `needsUserAttention`/retry metadata and exit without motion or
  fake success; visible foreground login remains the recovery path.
