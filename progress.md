# Progress

## 2026-09-09 iPad validation continuation: visible collection and snapshot diagnostics

- Added a red/green regression seam for the reported “点击准备采集没有反应” path. The
  authentication sheet now remains mounted while the same visible `WKWebView` performs
  education/electricity collection, disables interactive dismissal and login controls during
  the run, and closes only after local state plus the shared Widget snapshot commit succeeds.
- Added an explicit retry path for collection-scoped transient failures so a network/portal
  timeout does not force a fresh login; credentials and cookie values remain inside WebKit.
- Extended the visible education script to accept `id`/`code`/`dataSemester` semester shapes,
  object-valued semester maps, and student IDs discovered from prior print-data resources. A
  Node WebView harness now runs this path end-to-end with sanitized fixture responses.
- Extended the version-1 Widget snapshot with an optional validated electricity balance. The
  Widget and Home surface display GPA/electricity when present, while old snapshots without the
  field remain readable.
- Management now exposes the resolved App Group availability and identifier. The macOS signed
  IPA verifier also checks both runtime `Info.plist` App Group fields in addition to nested
  signatures, provisioning profiles and entitlements.
- Local script regression: 69 tests passed, golden validator passed (1 version/15 scenarios/32
  referenced files), and `git diff --check` passed. Swift/Xcode compilation and a real iPad run
  still require the next macOS workflow artifact and user-side signed-device evidence.

## 2026-09-09 collection launch race repair

- [x] Management-page collection requests now wait for the authentication sheet's visible
  WebView to mount before starting the collector; callbacks from inside the sheet continue
  through the same guarded request path.
- [x] Retry handling is centralized so the authentication sheet and management page cannot
  consume the same collection transition twice.
- [x] The portable Python suite (69 tests), golden corpus validation (1 version/15 scenarios/32
  files), and `git diff --check` pass. Windows has no Swift/Xcode toolchain, so macOS XCTest and
  the iPhoneOS archive remain authoritative cloud gates.
- [ ] A new macOS IPA run is still required; `cloud-run-34255125394` predates this repair and
  must not be described as the current-round build.

## 2026-09-09 iOS collection build-gate repair

- 复核确认当前 goal `01a06b40-b9a6-7af0-aeb2-c1a56e9c91d8` 仍为 active；没有重复创建
  goal，所有工作仍在 `aoxiang-assistant` 的 `iOS` 分支。
- 定位并修复真正的 Xcode 编译风险：`WKWebView.callAsyncJavaScript` 使用了重复的
  `in` 参数标签，改为 iOS 15 API 的 `contentWorld: .page`；Windows Foundation-only
  测试此前不会编译这段 WebKit 条件代码。
- 教师对象数组现在按 `nameZh`/`name`/`teacherName` 等字段归一化，避免 `[object Object]`
  或字典描述进入课表；新增 Swift 与 Python 回归。
- readiness workflow 改为严格要求 Simulator 成功，使用独立 DerivedData 和成功路径
  marker，并在失败时上传 xcodebuild 日志；device archive 不再静默替代 Simulator gate。
- 本机回归：Swift Core 80、Swift App 23、Python 65（含 13 subtests）、golden
  validator 15 scenarios/32 files、Android 单测/assemble/lint 均通过；lint 仍为 0 errors、
  189 条既有 warnings，`git diff --check` 通过。
- 当时待完成的提交、macOS readiness、device archive 与 Widget-capable IPA 检查现已完成；
  签名、App Group 和 iPad 实测仍明确保留为外部证据。

## 2026-09-09 Xcode 26 diagnosis

- 新提交的 readiness/IPA runs (`34252603142`/`34252603155`) 均执行到真实 Xcode 编译后
  失败；GitHub 页面日志确认唯一编译错误是 `callAsyncJavaScript` 的 completion closure
  不再被 Xcode 26 SDK 接受（`extra trailing closure passed in call`）。
- 已将教育脚本调用改为 `try await webView.callAsyncJavaScript(..., contentWorld: .page)`，
  保留 MainActor、超时和 continuation 保护；下一提交必须重新通过 Simulator 与 device
  archive 两条 macOS 门禁后才可交付 IPA。

## 2026-09-09 Simulator diagnosis

- 新 readiness run `34254206081` 已验证 WebKit API 修复通过，但 Debug Xcode build 因
  `DEVELOPMENT_ASSET_PATHS` 指向不存在的 `AoxiangAssistant/Preview Content` 失败。
- 已移除这个无效模板路径；它不是产品资源，也不影响 Release device archive。加入配置回归
  后，下一 run 必须同时证明 Simulator `.app` 和嵌套 Widget 都能生成。

## 2026-09-04

- 创建 `iOS` 分支和本阶段 goal。
- 读取并启用 `planning-with-files`、`tdd`、`project-architect` 技能。
- 完成 CodeGraph/源码盘点，记录在 `findings.md`。
- 已新增 `LocalDataContract`、`LocalDataStore`、`BackupContract` 初版，并接入部分 Activity/课表存储路径。
- 已发现并待修复：后台服务和 Widget 的成绩读取、旧备份识别、契约文档/fixture/测试、编译验证。
- 上一轮已完成契约文档、fixture、主要消费者接入及基础 seam 测试；当前分支基于
  `d7a7954`，工作区保留本地未提交改动（未做清理或回滚）。
- 本轮收口范围：先为悬空 `semesterId`、坏记录部分覆盖、未知 local envelope 字段
  建立失败测试，再修复对应 seam；Activity 手动编辑回滚作为后续高风险项单独处理，
  避免在没有可运行 Android UI 测试的情况下盲改 5,000 行 Activity。
- 已新增失败测试：未知 local envelope 字段拒绝、备份课程引用缺失学期拒绝、
  坏课表集合读取返回失败而不是部分列表。
- 已修复：`LocalDataContract` 显式拒绝未知 envelope 字段并严格检查整数 schema；
  `BackupContract` 校验 `course.semesterId` 引用完整性；
  `ScheduleStorage`/`LocalDataStore` 返回显式读取结果，`BackgroundSyncService`
  和 `MainActivity` 在读取失败时不再把坏数据覆盖为空数据。
- 已额外收口：`MainActivity` 手动新增/编辑/删除课程或学期时，保存失败会回滚内存状态、
  保持当前界面并提示未保存。
- 用户提供 `gradle-8.14.3-all.zip` 后已填充 wrapper 缓存；Gradle 8.14.3 可正常启动。
  默认 Java 25 导致 class major 69 错误，切换 JDK 17 后解决。
- 本机原先没有 Android SDK；已在用户标准目录安装 command-line tools、API 35、
  build-tools 35.0.0 和 platform-tools，并通过已忽略的 `local.properties` 接入。
- 完成 TDD 红绿循环：先证实导出悬空课程引用的测试失败，再让
  `BackupContract.createDocument` 复用完整导入校验，防止生成 iOS 无法读取的备份。
- 最终验证：92 个单元测试全部通过；Debug APK 构建成功；lint 0 errors、
  189 warnings，且本阶段修改文件中 0 条 lint issue；`git diff --check` 通过。
- 剩余非阻塞项：真机上的旧数据升级与手动编辑失败回滚 UI 流程尚未人工回归。
- 已新增 [docs/IOS_REFACTOR_ENTRYPOINTS.md](./docs/IOS_REFACTOR_ENTRYPOINTS.md)，把
  第一阶段成果整理成后续 iOS 重构的模块入口与迁移顺序。
- 最终 requirement-by-requirement 审计完成：`MainActivity`、`BackgroundSyncService`、
  `ScheduleWidgetData`、`HomeWidgetSupport` 均通过 `LocalDataStore` 或
  `ScheduleStorage` 访问本地数据；备份契约递归拒绝凭据/会话字段，fixture 仅含虚构数据；
  `git diff --check` 再次通过。
- 第一阶段正式验收完成。真机旧数据升级和手动编辑失败回滚仍列为后续 instrumentation/
  真机回归项，属于非阻塞集成验证缺口。

## 2026-09-05

- 按第二阶段启动前的要求复核第一阶段：当前分支为 `iOS`，基线提交为 `d7a7954`，
  工作区包含本地契约/存储/测试/文档改动，未发现数据结构智能体项目文件或标识混入。
- 重新执行 `:app:testDebugUnitTest :app:assembleDebug :app:lintDebug --offline`：
  92 个 JVM 测试通过，Debug APK 构建成功，lint 0 errors（189 warnings 为既有基线），
  `git diff --check` 通过。
- 第一阶段验收结论保持为通过；唯一未完成的是 Android 真机上的旧数据升级和手动编辑
  保存失败回滚人工验证，不阻塞第二阶段的纯 fixture/契约工作。
- 已创建只包含第二阶段 golden fixture 的 goal；第一阶段内容不再作为该 goal 的任务。

## 2026-09-05 continued

- 根据收口审查新增 Phase 6：先覆盖旧裸数组坏记录不改写、提交失败可观察、未知枚举拒绝三条 seam，
  再实现最小变更并重跑完整 JVM/构建/lint 验证。
- Phase 6 已完成：`LocalDataStore` 读取不再隐式迁移，领域校验成功后才提交 schema 1；核心写入改用
  可观察的 `commit()`，课表数组/选中学期/主题由一次批量提交保护；备份拒绝未知枚举和错误域字段，
  保留记录内未知扩展字段。
- 最终回归：118 个 JVM 测试通过，Debug APK 构建成功，lint 0 errors/189 warnings，`git diff --check`
  通过。真机旧数据升级、实际磁盘故障和手动编辑失败 UI 仍需后续 instrumentation/真机清单验证。

## 2026-09-05 final second-phase closeout

- GPA 画像回退测试不再在测试体内复制选择逻辑；新增生产 seam
  `PortalApiParsers.selectGpa(apiGpa, portraitGpa)`，前台和后台成绩采集均通过该入口选择 GPA。
- 先以缺失 seam 的编译失败确认红灯，再实现最小规则并通过 GPA golden 测试。
- 第二阶段范围保持为脱敏 fixture、manifest 安全门禁和 Android 输入/输出基线；未编写 iOS UI，
  未引入数据结构智能体代码。

## 2026-09-05 fixture 收口

- Golden fixture 阶段已完成：15 个场景、32 个被 manifest 引用的输入/答案/HTML 文件，
  加根目录 `README.md` 和 `manifest.json` 共 34 个文件，纳入当前
  `contract-fixtures/golden/v1/` 版本，由 `GoldenManifestTest` 校验覆盖、路径、安全字段和
  输入/答案字段隔离。
- 最终回归（含 fixture）：`:app:testDebugUnitTest :app:assembleDebug :app:lintDebug`
  使用 JDK 17、`--offline --rerun-tasks` 完成；121 个 JVM 测试通过，Debug APK 构建成功，
  lint 0 errors（189 条为既有 warnings），`git diff --check` 通过。
- 当前契约与 fixture goal 已具备关闭条件；学习台仅 Home 渲染、旧侧边栏重复挂载和图二
  重叠布局仍属于独立 UI 阶段，不纳入本次契约冻结。
- 最终命令 `:app:testDebugUnitTest :app:assembleDebug :app:lintDebug --offline --rerun-tasks`
  通过：121 个 JVM 测试、Debug APK、lint 0 errors（189 条既有 warnings）；`git diff --check` 通过。

## 2026-09-05 cross-platform sync readiness

- 新建当前同步准备 goal，范围只包含共享契约、fixture、Swift 非 UI 入口和 CI/协作门禁。
- 新增 `scripts/validate_golden_fixtures.py` 及 23 个 golden validator 负向/CLI 测试、7 个 PR
  validator 测试和 1 个 workflow pin 测试；当前独立校验通过
  15 个场景和 32 个 manifest 引用文件（另有根目录 manifest/README，共 34 个文件）。
- 新增 `.github/workflows/cross-platform-contract.yml` 和 PR 模板：Ubuntu 校验 fixture 与
  Android test/build/lint，macOS 校验路径可移植性并编译/测试 Swift Package。
- 新增 `docs/CROSS_PLATFORM_SYNC.md`，固定日常同步、版本提升、迁移、回滚、分支保护和
  iOS 发布规则。
- 新增 `ios/AoxiangCore` Foundation-only Swift Package；直接读取同一 fixture，不复制数据，
  并用能力矩阵把 15 个尚未移植的业务 kind 明确标为 `pending`。
- 加入防虚报约束：能力 JSON 标 `covered` 时必须与 Swift 注册 adapter 精确对应；
  `ios-v*` tag、手动严格运行或仓库 release gate 变量会要求零 `pending`。
- TDD 补齐未来版本发现：先用 3 个失败测试证明默认入口会漏掉 `v2`，再让 Python
  validator 和 Swift readiness 自动扫描整个 `golden/`，要求版本连续且 schema/目录一致。

## 2026-09-06 final sync-readiness hardening

- 先补红灯再实现：Python validator 现在对 `v1` 保持严格场景清单，对 `v2+` 允许新增
  稳定 kebab-case `id`/`kind`，并拒绝非规范标识；输入/expected 文件分类也改为按 manifest
  引用集合判断。
- Swift capability registry 拒绝重复 schema 版本声明，单 manifest 校验拒绝多余版本；
  Swift fixture validator 拒绝 null 根和跨平台不可移植路径（冒号/控制字符）。
- 新增 Android `GoldenCorpusCoverageTest`，扫描全部连续 `golden/vN` 并检查每个
  `schemaVersion/id` 有显式 fixture 测试方法注册，防止同 kind 新场景仅通过静态检查却没有
  独立 Android 行为断言。
- 文档已统一使用 `contract-fixtures/golden/` corpus 表述，并明确 `v1` 严格清单、`v2+`
  扩展规则和 Android/iOS 双端登记要求。
- 最新本机验收：Python/PR/workflow validator 34 tests 全部通过；golden validator 15 场景/32 引用文件通过；
  Android 123 tests、Debug assemble、lint（0 errors/189 既有 warnings）和 `git diff --check`
  通过；两个 workflow YAML 解析通过。Windows 无 Swift/Xcode，Swift 编译/XCTest 由 macOS CI
  authoritative gate 验证。
- 远端 CI 依赖审计发现原 `gradle/actions/setup-gradle` SHA 不存在；已替换为 GitHub API
  验证过的 v4.4.4 commit，并将既有 release workflow 的 checkout/release action 也固定到
  已验证 commit，避免供应链依赖漂移。
- 门禁安全审计发现 PR job 若 checkout PR 自身脚本可被恶意修改绕过；已拆出受信任的
  `.github/workflows/pr-contract-gate.yml`，用 `pull_request_target` checkout base SHA，
  仅通过 API 读取 PR 文件列表，普通构建 job 仍在 `pull_request` 上验证 PR 代码。
- Windows 没有 Swift/Xcode，本机不能执行权威 Swift 编译或 XCTest；该证据由 macOS CI 提供。

## 2026-09-06 final acceptance hardening

- Android coverage gate 已从 `kind` 粒度提升为 `schemaVersion/id` 粒度：注册表使用 `vN/scenario-id`
  精确键，重复注册和 manifest/注册表集合不一致均 fail-closed；同一 kind 的新增 scenario 必须
  增加独立测试入口。
- PR 门禁已补齐 `GradeRecord`、`AuthenticationPolicy`、`UnifiedAuthTracker` 等共享 seam；
  shared/breaking PR 在 trusted base workflow 中还必须实际修改 `contract-fixtures/` 和独立
  `expected.json`，不能只依靠复选框声明。
- 文档已明确新增 `golden/vN` 时同步更新 Swift `supportedSchemaVersions`、capability report
  和迁移测试；Python 是 manifest 精确字段、重复 JSON key 和敏感内容的结构权威，Swift Package
  负责 Foundation 读取、路径 containment 与 capability/readiness 入口。
- Swift capability report 已增加每个业务 kind 对应的 `vN/scenario-id` 列表，并与发现到的
  manifest 场景做双向精确校验；同一 kind 的新增场景会让 Swift readiness 先失败，直到报告更新。
- 最终可执行验收：Python/PR/workflow 回归 34 tests 全部通过；golden validator 1 version、
  15 scenarios、32 referenced files；Android 123 tests、0 failures/errors/skips，Debug APK
  SHA256 `47299933E3F21A6473E15ECB7768522EC300194A7F2A2B4DFDC7C6A74946EE18`，lint 0 errors/
  189 existing warnings，workflow YAML 解析和 `git diff --check` 通过。
- 未声称 Windows 已通过 Swift 编译/XCTest；`swift test --package-path ios/AoxiangCore` 仍由
  macOS CI 权威执行。远端 GitHub branch protection 将四个 required checks 配置为必需仍需仓库管理员完成。

## 2026-09-06 third-to-fifth-phase kickoff

- 用户确认第三、第四、第五阶段均在当前 `iOS` 分支目标内推进；已创建新的 active goal，
  范围包含离线主 App、前台认证/采集和尽力而为后台同步。
- 已将 `task_plan.md` 切换为三阶段实施计划；当前尚未开始 iOS UI 或认证/后台代码，先盘点
  既有 Foundation-only Package、Android backup seam 和可复用 fixture 入口。

## 2026-09-09 final artifact verification and goal recreation

- CodeGraph 已在当前仓库初始化并验证健康：158 files、3,055 nodes、8,972 edges，索引为最新。
- `origin/iOS` 与本地 `iOS` 分支均指向 `1f58a7466b038a647653e1ffc9ea786a8e6a39db`。
- GitHub Actions `34255125388`（Cross-platform contract）和 `34255125394`
  （Build re-signable iOS IPA）均对该精确提交成功；前者通过严格 Simulator gate，后者通过
  `iphoneos` archive。
- Artifact `AoxiangAssistant-ipa-variants-9`（ID `10067599252`，ZIP SHA-256
  `b61b8fc06fab9e79b65dbae40f473470448a16c42f7e7139860828660c9e1f96`）包含三个 IPA：推荐
  `AoxiangAssistant-sideload-re-signable.ipa`、兼容的 `AoxiangAssistant-full-widget-re-signable.ipa`
  均保留 `AoxiangAssistantWidget.appex` 及其可执行文件；显式
  `AoxiangAssistant-sideload-host-only-re-signable.ipa` 不含 `PlugIns/`。三者均包含新的
  iPhone/iPad AppIcon 资源。
- 当前可复现证据：Swift Core 80、Swift App 23、Python 65（13 subtests）、golden
  corpus 1 version/15 scenarios/32 referenced files、Android test/assemble/lint 全部通过，
  lint 0 errors/189 existing warnings，`git diff --check` 通过。
- 原 active goal 的软件验收记录已完整；用户要求重新建立 goal。后续新 goal 只追踪外部
  签名/App Group、sideload 安装、真实 iPad 采集与 Widget 渲染，不把 unsigned artifact
  误称为可安装或已验证。
- 本次本机复核中 Python validator/tests 仍通过；Android 离线命令因当前 Gradle cache 缺少
  `com.android.tools.build:gradle:8.11.0` 无法配置项目，Windows Swift helper 因宿主权限无法
  枚举用户 Swift toolchain。两者均由同一提交的 GitHub Actions 成功 job 覆盖，未修改源码。
- 已将原软件交付 goal 标记为 complete，并按用户要求建立新的 active goal（同一线程 ID），
  仅追踪 Widget-capable `sideload` 的重签名/App Group 配置、iPad 安装、真实前台采集和
  Widget 渲染证据；不把这些外部门禁伪装成已完成，也不修改 Structify。
- 当前交付文件：`dist/ios/cloud-run-34255125394/AoxiangAssistant-ipa-variants-9.zip`
  及其 `artifact/` 下的三个 IPA。推荐使用 `AoxiangAssistant-sideload-re-signable.ipa`。

## 2026-09-08 foreground collection continuation

- Reviewed the current `iOS` worktree and confirmed all changes remain under
  `aoxiang-assistant`; no Structify or data-structure-agent files were restored
  or introduced.
- Added Android-compatible course-table semester selection to the Swift
  collector: valid dated candidates are ordered, the current/next/latest
  candidate is selected, and an activity-derived end date causes a safe retry of
  the next semester. Empty schedules keep the Android two-week minimum.
- Added Core parser tests for selection, embedded semester discovery and empty
  schedule end dates, plus an App transport test proving the next-semester
  request chain.
- Changed the collector's implicit date source from UTC to the shared
  `Asia/Shanghai` business calendar so iPad locale/time-zone settings cannot
  select a wrong semester around midnight.
- Windows verification after the continuation: Core 77 tests and App 15 tests
  passed; Python test suite 59 passed; golden validator passed; `git diff
  --check` passed. Xcode/device archive and iPad installation remain unverified
  until the GitHub macOS workflow is run.

## 2026-09-08 foreground collection integration

- 复核最新 Swift 变更后，先修复 `PortalCollectedData` 与 `SchedulePayload` 的 Equatable 契约，
  Core 测试恢复为 73/73 通过；App 端修复 collector 对 `(Data, HTTPURLResponse)` 的错误访问及
  状态门禁的可编译性，App 测试恢复为 7/7 通过。
- `PortalForegroundCollector` 已补齐 student ID 的 HTML/API 回退、GPA 缺失时保留有效成绩、
  学期补充请求失败时保留原对象，并已接入 `OfflineAppViewModel` 与管理页。
- 管理页现在在可见认证 WebView 完成显式“准备采集”后，使用同一 `WKHTTPCookieStore` 执行
  成绩/课表稳定 HTTP 请求和画像/GPA、电费页面兜底；完整结果原子写入本地 state 与 Widget
  快照，任一提交失败都保持旧值。
- 课表选择和隐式日期仍需以本轮 2026-09-08 的 77/15 Swift 回归为准；下一阶段重点是
  macOS `xcodebuild`、嵌套 Widget 签名和真实 iPad 安装证据，不再把“准备采集未接线”当作当前状态。

## 2026-09-07 iPad install hardening and approved artwork

- 用户确认目标设备为 iPadOS 26.6.1；截图只有通用 `Unable to Install` 提示，不能据此把问题归因
  于系统版本。工程仍以 iOS 15.0 为最低部署目标，设备族为 iPhone/iPad（1,2），关闭 Mac Catalyst。
- 用户指定新的无透明 PNG 作为唯一品牌图标源：
  `ios/AoxiangAssistant/Branding/AoxiangAssistantIcon.png`，SHA-256 为
  `19940c2923d80ff088b87c8fe54591da640b3649fe2dcc916b4bbe23c1592e87`。
  Android 旧 `ic_launcher.xml` 不再作为 iOS 图标输入；Android 后续可独立同步同一 artwork。
- 生成 `Assets.xcassets/AppIcon.appiconset` 的 18 个 iPhone/iPad/marketing RGB PNG，Xcode
  App target 已设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 并正确引用资源组。
- （历史记录，已由 2026-09-08 修正取代）当时 IPA 打包器把 `sideload` 当作 host-only，
  因此不嵌入 Widget；现在推荐的 `sideload` 保留嵌套扩展，host-only 已改为显式的
  `sideload-host-only` 变体。
- 当时的 macOS workflow 一次上传两个 IPA 并分别验证无/有 Widget 入口；当前 workflow
  上传三个变体并验证推荐 sideload/full-widget 含 Widget、host-only 不含 Widget；不接收
  Apple ID、证书、私钥、provisioning profile、密码或会话。
- 本机 Python/fixture 回归：55 tests 通过；fixture validator 通过 1 version/15 scenarios/32
  files；`git diff --check` 通过。Swift/Xcode device archive 和真实 iPad 自签安装仍需远端/设备证据。

## 2026-09-08 current iOS delivery evidence

- 当前 `iOS` 分支提交 `3fda090db5ff175ce7277299e4138e82160676ce` 已推送；专用 IPA workflow
  同时支持手动触发和 `iOS` 分支 push 触发，避免没有 `gh`/写入令牌时无法启动 macOS 构建。
- GitHub Actions run `34174391367` 是修正前的历史证据：当时的 `sideload` 为 host-only，
  `full-widget` 保留 `AoxiangAssistantWidget.appex`；当前未提交修正需要新的 workflow run。
- artifact 名称为 `AoxiangAssistant-ipa-variants-4`，保留至 2026-09-15；下载需要登录
  GitHub。当前没有 Apple 团队签名凭据，因此产物仍是 re-signable IPA，不是可直接安装的 IPA。
- 未宣称 signed IPA 或真实 iPad 安装成功：full-widget 仍要求签名工具同时重签主 App/Widget，
  并让 provisioning profile 授权相同 App Group；sideload 是当前兼容安装变体。

## 2026-09-08 Widget-capable sideload correction and collection recovery

- Earlier entries used the `sideload` name for a host-only IPA. That layout was
  deliberately install-oriented and could not contain a Widget. Current
  packaging keeps the nested Widget in `AoxiangAssistant-sideload-re-signable.ipa`;
  the explicitly named `sideload-host-only` artifact is the only no-Widget
  fallback. `full-widget` remains a compatibility alias for the same complete
  extension layout.
- Added a Foundation-testable navigation policy for the electricity CAS
  bootstrap. It allows only the expected first YKT CAS hop, while a later CAS
  login redirect still maps to authentication recovery.
- The visible electricity collector now retries page evaluation while Vue data
  loads and supports Vue 2/Vue 3 roots plus Android-compatible balance labels.
  It is foreground-only and bounded; no password, Cookie, token, or SMS value
  crosses into portable storage.
- Management now has a snapshot-refresh action so an installed app reports a
  real App Group write failure instead of leaving Widget state ambiguous.

## 2026-09-08 recovery verification

- 恢复检查确认旧 goal 仍是当前线程的 active goal；未创建重叠目标，所有改动仍在
  `aoxiang-assistant` 的 `iOS` 分支，未触碰 Structify。
- 本机回归已完成：Swift Core 79 tests、Swift App 22 tests、Python 65 tests、golden
  corpus 1 version/15 scenarios/32 referenced files；Android 123 JVM tests、Debug
  APK assemble 成功，lint 0 errors/189 existing warnings；`git diff --check` 通过。
- 本次 Android 命令最初误用了不存在的 JDK 路径，随后改用已安装的
  `C:\Program Files\Java\jdk-17` 重跑并通过；这不是产品代码失败。
- 当前推荐的 `sideload` 保留 `PlugIns/AoxiangAssistantWidget.appex`；无 Widget 的包已
  改名为显式 `sideload-host-only`，避免再次把可安装性降级误认为 Widget 支持。

## 2026-09-08 goal recovery continuation

- 用户界面中误删 goal 后，后端检查确认原目标仍为 active；没有创建重叠 goal，继续沿用
  原目标及其验收历史。
- 最新完整回归：Swift Core 79 tests、Swift App 23 tests、Python 65 tests、Android
  123 JVM tests 均通过；golden validator 通过 1 version/15 scenarios/32 referenced
  files；Android Debug APK 构建成功，lint 0 errors/189 existing warnings，`git diff
  --check` 通过。
- 当前剩余门禁是把未提交修复推送到 `iOS`，由新 macOS run 对该精确提交执行
  `iphoneos` archive，并验证推荐 sideload 中同时存在主 App 和 Widget extension。

## 2026-09-07 regression hardening and iPad delivery path

- 修正 `RecordingSnapshotWriter.restore` 测试替身：恢复操作现在精确还原原快照（或空状态），
  覆盖 `BackgroundSyncCoordinator.run` 在 status store 提交失败后回滚新 Widget 快照的 fail-closed 路径。
- 新增 `OfflineDataController.importAndroidBackup` 回归：Android 便携课表备份导入新学期/课程时，
  iOS 私有成绩数组仍保留在控制器内存与持久化 store；备份省略成绩不再被解释为删除命令。
- 首轮编译因测试中的可选 `InMemoryOfflineStateStore.value` 访问失败；改为可选比较后通过，未改动产品语义。
- 当前本机回归：Swift Core 64 tests、Swift App 7 tests、Python 49 tests、Android 123 tests 均
  0 failures/errors；golden validator 通过 1 version/15 scenarios/32 files；Android lint 0 errors/
  186 warnings；`git diff --check` 通过（文档更新前）。
- `git ls-remote` 已确认 GitHub `iOS` 分支可达。下一步是安全提交 workflow 与 iOS 源码，推送后
  由 iPad Safari 的 GitHub Actions 页面手动启动 macOS archive；尚无云端 IPA 或真实设备安装证据。

## 2026-09-07 iPhone/iPad target clarification and App Group hardening

- 用户确认产品是手机/平板软件。已核对 App/Widget target：仅支持
  `iphoneos iphonesimulator`、设备族 `1,2`，并关闭 Mac Catalyst；macOS 只作为 Swift/Xcode
  测试宿主，不产出 macOS App。
- 按 TDD 补齐 App Group 缺失时的 fail-closed seam：共享快照 URL 不再回退私有沙盒，新增
  `sharedContainerUnavailable` 与 `UnavailableWidgetSnapshotStore`；主 App 提示共享容器不可用
  但仍可编辑本地数据，Widget 不渲染私有副本，后台同步不注册/调度。
- 可执行回归：Python/PR/workflow 44 tests 通过；golden validator 通过（1 version/15
  scenarios/32 referenced files）；Android 123 tests 全通过，Debug APK 构建成功，lint 0
  errors/189 existing warnings；`git diff --check` 通过。
- Windows 无 Swift/Xcode，因此未声称 Swift XCTest 或 iOS Simulator 构建通过；必须等待
  macOS CI 验证后再关闭当前第三至第五阶段 goal。

## 2026-09-07 local Swift and re-signable IPA preparation

- 用户说明没有 macOS 电脑、仅有可自签安装的平板。交付路径调整为：GitHub Actions 的
  `macos-latest` 负责 iPhone/iPad device archive，输出不含签名秘密的 re-signable IPA；
  用户在平板端自行签名。该 IPA 不能被描述为未经签名即可安装。
- 已通过 winget 安装 Swift 6.3.3 Windows toolchain。首次运行发现缺少 `link.exe`，正在
  安装 Visual Studio Build Tools 的 C++ workload；Windows Swift 覆盖 Foundation/XCTest，
  不提供 iOS SDK、Simulator、archive 或 Apple 代码签名。

## 2026-09-06 third-to-fifth-phase implementation

- 新增 `ios/AoxiangCore` 离线模型、Android v2.2.2 备份导入/导出、独立 grades 本地数组导入、
  原子文件存储、编辑控制器和脱敏 Widget 快照；导入失败、悬空引用、磁盘失败回滚和快照
  只读边界均有 XCTest seam。
- 新增 `ios/AoxiangCore` 认证状态机、采集策略和 BackgroundSyncCoordinator：状态显式区分
  needsLogin/needsSMS/authenticated/readyToCollect/retryableFailure/needsUserAttention；
  后台认证失效/短信只记录待处理状态并通知用户，成功前不替换快照。
- 新增独立 `ios/AoxiangApp` Swift package：SwiftUI 首页/成绩/课表/管理页面及本地编辑入口、
  可见 WKWebView/WKHTTPCookieStore 认证、稳定 HTTP URLSession 适配和条件编译的
  BGAppRefreshTask/BGProcessingTask/通知适配。标准备份仍不包含成绩、凭据或会话。
- Windows 无 Swift/Xcode，尚未声称本地 Swift 编译通过；CI 已加入两个 package 的 macOS
  XCTest 入口，待远端 macOS runner 提供权威结果。

## 2026-09-06 third-to-fifth-phase kickoff

- 用户确认第三、第四、第五阶段均在当前 `iOS` 分支目标内推进；已创建新的 active goal，
  范围包含离线主 App、前台认证/采集和尽力而为后台同步。
- 已将 `task_plan.md` 切换为三阶段实施计划；当前尚未开始 iOS UI 或认证/后台代码，先盘点
  既有 Foundation-only Package、Android backup seam 和可复用 fixture 入口。
## 2026-09-09 iPad collection/widget repair

- Reproduced the reported grade failure with the Node WebView harness: rendered table + unavailable
  grade API previously returned `retryable` and surfaced `grade response unavailable`.
- Added a red-capable DOM fallback test and implemented a bounded wait plus normalized table parsing;
  API data remains preferred and no sensitive session material is returned.
- Added coverage for a failed grade-page reload, removed the SwiftUI WidgetBundle principal-class
  override from the Widget plist, and bumped App/Widget to `1.0.1 (2)`.
- Targeted runtime, script-syntax, project-configuration and golden-fixture checks pass. Full Swift/
  Xcode archive and user-side App Group/Widget installation remain pending until the fresh CI artifact.

## 2026-09-09 current release handoff

- Re-ran the visible education Node harness: 7 tests passed, including the exact failure shape
  reported by the user (the grade page is mounted while grade/schedule endpoints are unavailable).
- Re-ran iOS project configuration, IPA packaging, and collection-visibility checks: 30 tests passed;
  `git diff --check` passed.
- The current workspace changes are ready to commit on branch `iOS`. The old local artifact
  `dist/ios/cloud-run-34299633874` remains stale (`1.0 (1)`) and must not be used for validation.
- Next authoritative step is a fresh macOS archive for the new commit; only the resulting
  `AoxiangAssistant-sideload-re-signable.ipa` should be re-signed and installed.

## 2026-09-09 repair verification before fresh archive

- Re-ran `python -m unittest discover -s scripts/tests -p "test_*.py" -v`: 77 tests passed.
- Re-ran the visible WebView Node harness: 7 tests passed. The harness now proves a rendered
 成绩 table is retained when the grade API, grade-page reload, schedule endpoint or student
  bootstrap is unavailable.
- Re-ran `python scripts/validate_golden_fixtures.py`: 1 version, 15 scenarios and 32 referenced
  files validated. `git diff --check` passed.
- The pending source diff adds empty-grade guards in `PortalForegroundCollector` and fixes only
  Swift test compilation seams; no credentials, cookies, SMS codes or raw session values are
  introduced.
- The old `dist/ios/cloud-run-34299633874` artifact remains stale (`1.0 (1)`) and must not be
  installed. A fresh macOS archive for the repair commit is required before another iPad test.

## 2026-09-09 push gate

- Created local commit `87214fd` (`Harden iOS grade collection fallback`) after the verification
  suite passed. It is one commit ahead of `origin/iOS`.
- The first push request was not executed: the approval service returned transient HTTP 503. No
  workaround or indirect upload was attempted; an explicit fresh approval is required before retry.
- The latest device screenshot does not include the shared-container/App Group status rows added in
  the current source. It is therefore evidence of an older installed build, consistent with the
  locally inspected `1.0 (1)` artifact, not of the pending `1.0.1 (2)` repair.
