# iOS 第一阶段计划

## Goal

在 `iOS` 分支冻结翱翔助手 v2.2.2 的本地数据与备份契约，提供可迁移的
schemaVersion、兼容旧数据的迁移入口、脱敏跨平台 fixture 和测试入口；
不改变现有 Android 用户可见行为，也不把凭据或 WebView 会话放入备份。
第一阶段的收口还必须保证失败时不覆盖数据、不显示未持久化状态，并为后续
iOS 迁移保留清晰的存储/备份 seam。

## Phases

- [x] Phase 1: 盘点 v2.2.2 的存储、备份字段和安全边界
- [x] Phase 2: 接入版本化本地数组与备份 envelope，保留旧格式读取
- [x] Phase 3: 写契约文档、跨平台 fixture 和 seam 测试
- [x] Phase 4: 修复失败路径、引用完整性和部分覆盖风险
- [x] Phase 5: 编译、测试、静态审计并完成目标逐项验收
- [x] Phase 6: 收口迁移读写原子性与未知枚举策略

## Final acceptance

- [x] 分支、goal、规划文件和未提交改动范围已核对
- [x] 单元测试、Debug 构建、lint 和 `git diff --check` 已完成并记录
- [x] Android 课表/成绩消费者 seam 覆盖已审计
- [x] 备份敏感数据边界与脱敏 fixture 已审计
- [x] 后续 iOS 重构入口与非阻塞真机验证缺口已记录
- [x] 旧裸数组坏记录读取失败时保持原始字节不变
- [x] 持久化失败可由调用方观察，且关联课表设置不做无提示的部分成功
- [x] 未知枚举策略在实现、文档和测试中一致

## Decisions

- 新本地数组 envelope 使用 `schemaVersion: 1` 和 `items`；旧裸数组视为 schema 0，只读时迁移。
- 备份使用 `format: aoxiang-assistant.schedule-backup`、`schemaVersion: 1`；旧 `version: 2.0` 文档继续可读。
- 备份只覆盖课程、学期和主题/深色/选中学期设置；成绩、GPA、电费、同步状态、自动更新设置、凭据、Cookie 和短信验证码不在备份范围内。
- 日期使用 `YYYY-MM-DD`，节次时间使用 `HH:mm`，持久化时间戳使用 Unix epoch milliseconds；身份认证和会话由平台安全存储管理。
- 先测试纯 JSON contract seam，再接入 Android 存储适配器；不在本阶段重写 Activity 或 WebView。
- 保存失败时以持久化成功为准：调用方必须保留旧内存快照、检查返回值，
  不得关闭编辑 UI 或显示成功状态。
- 坏记录导致的集合读取必须显式失败，不能把部分列表当成完整列表回写。
- 课程 `semesterId` 必须引用备份中存在的学期；未知 envelope 字段拒绝写入，
  以避免未来字段被静默丢失。
- 读取迁移必须在领域记录验证成功后才允许；提交失败不得报告成功。
- 当前版本的未知 `repeatRule`/`assessmentMethod` 拒绝导入，避免默认值造成静默语义变化。

## Errors Encountered

| Error | Attempt | Resolution |
|---|---:|---|
| Gradle wrapper download timeout | 1 | 使用用户提供的 `gradle-8.14.3-all.zip` 填充 wrapper 缓存，`gradlew --version` 已确认 8.14.3。 |
| `Unsupported class file major version 69` | 1 | 默认 Java 25 与构建脚本编译不兼容；验证命令改用本机 JDK 17。 |
| Android SDK location not found | 1 | 在用户标准目录安装 command-line tools、API 35、build-tools 35.0.0 和 platform-tools；机器路径只写入已忽略的 `local.properties`。 |
| Invalid pinned Gradle Action SHA | 1 | GitHub API 确认原 SHA 不存在，改为已验证的 `gradle/actions/setup-gradle` v4.4.4 commit，并固定 release workflow 的 action SHA。 |

## Verification Results

- `:app:testDebugUnitTest`: 92 tests, 0 failures, 0 errors, 0 skipped。
- `:app:assembleDebug`: 成功，生成 `app/build/outputs/apk/debug/app-debug.apk`。
- `:app:lintDebug`: 成功，0 errors、189 warnings；本阶段修改文件中 0 条 lint issue。
- `git diff --check`: 通过。

## Residual verification gap

| Gap | Impact | Next action |
|---|---|---|
| 尚未在真机执行旧数据升级与手动编辑失败回滚 | JVM 契约和 APK 构建已验证，但 Android runtime/UI 行为仍缺少人工证据 | 后续 Android 回归时增加 instrumentation 或真机清单；不阻塞第一阶段契约冻结 |

## Verification Gates

- [x] 旧 v2.2.2 裸数组可被读取并写成 schema 1 envelope
- [x] 旧 `version: 2.0` 备份可导入，新备份含 `format` 与 `schemaVersion`
- [x] 未来 schema 会拒绝且不覆盖原始数据
- [x] fixture 不含账号、密码、Cookie、验证码或真实个人信息
- [x] Android 所有成绩/课表消费者使用同一契约读写
- [x] JUnit、编译和 lint 结果已记录

## Phase 6 Verification

- `:app:testDebugUnitTest --offline`: 118 tests, 0 failures, 0 errors, 0 skipped。
- `:app:assembleDebug --offline`: 成功，生成 `app/build/outputs/apk/debug/app-debug.apk`。
- `:app:lintDebug --offline`: 0 errors、189 warnings；未引入本阶段相关 error。
- `git diff --check`: 通过。

---

# 第二阶段 Golden Fixture 计划

## Scope

本计划只服务于第二阶段：建立 Android 与 iOS 共用的脱敏 golden fixture 和
输入/输出测试基线。不编写 iOS UI，不迁移数据结构智能体代码，不重新实现第一
阶段的 schema/备份任务。

## Phases

- [x] Phase 1: 固化 fixture manifest、目录/命名、安全扫描和跨平台读取约定
- [x] Phase 2: 成绩接口、成绩构成 HTML、GPA 缺失与画像页回退、同名重修
- [x] Phase 3: 课表空数据、单双周、不连续周次、校区作息、多教师/地点、线上过滤
- [x] Phase 4: 电费结算时段/异常、认证状态和课程差异/通知文本
- [x] Phase 5: Android manifest 驱动测试、iOS 接入说明、全量验证

## Fixture Contract

- 根目录：`contract-fixtures/golden/`；当前版本为 `v1`，每个场景使用稳定的 kebab-case `id`。
  已审阅版本不追加新场景；新增场景或 kind 建立下一个连续 `vN`，并保留旧版本回归。
- `manifest.json` 是唯一索引，场景字段为 `id`、`kind`、`input`、`expected`，HTML
  场景可增加 `html`；路径使用 `/`，文件内容 UTF-8。
- `expected` 是独立的已知答案，不从 Android 实现重新计算；字段顺序不构成语义。
- 所有输入都脱敏；禁止 `password`、`cookie`、`token`、`sms`、`captcha`、`studentId`
  等敏感字段或真实身份值进入 fixture。
- 规则输出使用第一阶段稳定格式：日期 `YYYY-MM-DD`、节次时间 `HH:mm`、业务时区
  `Asia/Shanghai`、重复规则 `""`/`"仅单周"`/`"仅双周"`、不透明稳定 ID。

## TDD Order

每个场景按一个垂直切片推进：先添加一个 manifest 条目和独立 expected，写一个
失败的 Android seam 测试，确认失败原因，再做最小适配并回归；不一次性先写完全部
测试，也不以实现内部字段作为断言目标。

## Residual Risks

- 画像页 DOM/API 的真实字段仍可能随校方页面变化；fixture 只冻结已观察到的脱敏形状，
  不宣称线上页面永久兼容。
- Android 当前认证流程依赖 WebView/JavaScript；第二阶段只冻结可观察 phase 和结果，
  不把 Cookie 或验证码持久化，也不在 JVM 测试中伪造平台会话。

## Verification Results

- `:app:testDebugUnitTest --offline --rerun-tasks`: 121 tests, 0 failures, 0 errors.
- `:app:assembleDebug --offline --rerun-tasks`: successful; APK at
  `app/build/outputs/apk/debug/app-debug.apk`.
- `:app:lintDebug --offline --rerun-tasks`: 0 errors; 189 existing warnings.
- `git diff --check`: passed.

## Final Acceptance

- [x] 第一阶段审查通过：v2.2.2 行为基线、JSON 覆盖范围、schema 迁移、凭据/会话边界和
  稳定 wire 格式已记录；真机旧数据升级与 UI 失败回滚仅保留为非阻塞现场验证项。
- [x] 15 个第二阶段场景、32 个被 manifest 引用的 fixture 文件（连同根目录 README/manifest
  共 34 个文件）通过 manifest 完整性、路径安全、脱敏字段和值、
  expected 隔离门禁。
- [x] Android 端所有第二阶段 fixture 均通过纯 seam 输入/输出测试；GPA API 优先/画像回退
  规则由 `PortalApiParsers.selectGpa` 生产入口统一实现，未在测试中复制选择逻辑。
- [x] 未编写 iOS UI，未引入数据结构智能体代码；`docs/GOLDEN_FIXTURES.md` 已提供 iOS XCTest
  接入约定与同一 manifest 读取方式。
- [x] 完整 JVM 测试、Debug 构建、lint 和 `git diff --check` 均通过。

## Follow-up Risks

- 真实 iOS/XCTest runner has not yet been added; current fixtures and Android seam tests
  are the portable baseline for that next task.
- Android device verification of legacy migration, theme/semester write failures, and the
  Home-only learning workspace/double-sidebar UI remains outside this contract pass.

---

# 第三阶段 Android -> iOS 持续同步准备

## Goal

在不编写 iOS UI、也不复制 Android 平台实现的前提下，把共享契约和 golden fixture
变成后续双端迭代的单一事实源。日常 CI 必须验证 fixture、Android 行为和 Swift 接入
准备度；iOS 发布门禁必须在任一业务 adapter 尚未覆盖时失败。

## Architecture Decisions

- 采用 Ports & Adapters：两端分别实现平台 adapter，共享的是输入、规范化输出和错误边界，
  不是 Java/Swift 源码。
- 采用 Contract Testing：每个 `contract-fixtures/golden/vN/manifest.json` 是对应版本的行为索引，
  `expected.json` 必须独立审阅，不能由被测实现生成。
- fixture 只保留仓库根目录一份；Swift Package 通过仓库路径直接读取，避免副本漂移。
- `contract-capabilities.json` 是 iOS 的机器可读覆盖矩阵；只有真实 Swift adapter 已注册且
  有 fixture 输出断言时才能标 `covered`，其余必须显式 `pending`。
- 日常 readiness 与 iOS release gate 分离：前者验证接入骨架，后者要求业务 kind 零
  `pending`。`ios-v*` tag 自动启用严格发布门禁。
- wire/schema 破坏性变化必须提升 `schemaVersion`、新建 `golden/vN`、保留旧版本并添加迁移测试。

## Phases

- [x] Phase 1: 建立独立于 Android/Swift 的 fixture 校验器和负向回归测试
- [x] Phase 2: 建立跨平台 CI、PR 变更分类、安全检查和版本/回滚规范
- [x] Phase 3: 建立 Foundation-only Swift Package、能力矩阵和防虚报门禁
- [x] Phase 4: 运行 validator、Android test/build/lint、Swift 静态审查和 diff 验收
- [x] Phase 5: 更新最终证据、已自动化范围和剩余平台限制

## Acceptance

- [x] 独立校验器检查 manifest 精确结构、引用完整性、路径穿越/符号链接、重复 JSON key、
  未引用文件、输入/答案隔离和敏感内容。
- [x] Python/Swift 默认发现全部连续 `golden/vN`，目录号、manifest schema 和 iOS
  capability 声明必须一致，新增版本不能被旧 CI 静默漏掉；Swift supported versions、
  capability report 和迁移测试是新增版本的必同步项。
- [x] CI 在 Ubuntu 运行 validator 自测与 Android test/build/lint，并在 macOS 运行同一
  validator 和 `swift test --package-path ios/AoxiangCore`。
- [x] PR 模板强制区分 platform-only、shared behavior 和 wire/contract breaking。
- [x] PR 声明改由 `pull_request_target` 的 base revision 校验，避免 PR 自修改 validator 绕过门禁。
- [x] Swift 能力矩阵覆盖 manifest 的全部 kind 和 `schemaVersion/id` 场景键，且当前 15 类业务
  能力诚实标记为 `pending`。
- [x] Android corpus coverage gate 扫描全部 `golden/vN`，要求每个 `schemaVersion/id` 有显式
  fixture 测试注册；同 kind 新 scenario 也会 fail-closed。
- [x] 修改 JSON 不能单独冒充 Swift 覆盖：`covered` 必须对应代码中注册的 adapter。
- [x] iOS 严格发布模式在存在 `pending` 时失败，并由 `ios-v*` tag 自动触发。
- [x] 当前 Windows 可执行检查全部通过；Swift 编译/XCTest 留给新增 macOS CI 首次运行确认。

## Phase 4/5 Verification (2026-09-06)

- Python/PR/workflow validator regression: 34 tests, 0 failures; corpus validator reports 1 version,
  15 scenarios and 32 referenced fixture files; `python -m compileall -q scripts` passes.
- Android regression: 123 JVM tests, 0 failures/errors/skips; Debug APK assemble passes;
  lint has 0 errors and 189 pre-existing warnings. `GoldenCorpusCoverageTest` now scans
  every `golden/vN` and requires an explicit Android fixture test method for each `schemaVersion/id`.
- Workflow YAML parses successfully on Windows; `git diff --check` passes.
- Swift source and tests received static review and fail-closed tests for null roots, portable
  paths, duplicate version declarations, and extra single-manifest versions. Windows has no
  Swift/Xcode toolchain, so `swift test` remains an authoritative macOS CI check rather than
  a local claim.

## Final hardening verification (2026-09-06)

- Android coverage registry now uses exact `schemaVersion/id` keys and matches every discovered
  manifest scenario bidirectionally; the targeted coverage test and full Android suite pass.
- Trusted PR validation now requires actual `contract-fixtures/` and `expected.json` changes for
  shared/breaking declarations and classifies grade/auth seams as contract-sensitive.
- Python/PR/workflow regression: 34 tests, 0 failures; corpus: 1 version, 15 scenarios, 32
  manifest-referenced files; Android: 123 tests, 0 failures/errors/skips; APK SHA256
  `47299933E3F21A6473E15ECB7768522EC300194A7F2A2B4DFDC7C6A74946EE18`; lint 0 errors/189
  existing warnings; YAML and diff checks pass.
- Swift compilation/XCTest remains an explicit macOS-only gate; no Windows claim is made. Remote
  branch protection remains an administrator configuration step.

## Errors Encountered

| Error | Attempt | Resolution |
|---|---:|---|
| CodeGraph MCP tools were not exposed in this task runtime | 1 | Reused the already recorded healthy CodeGraph architecture audit; did not claim a new graph query. |
| Three delegated review tasks ended with HTTP 503 after writing shared files | 1 | Preserved their visible edits and moved final review/verification to the root task. |
| Specialist reviewer model was unavailable for this account | 1 | Continued with root static review plus executable validator/Android/macOS-CI evidence. |
| Swift/Xcode toolchain is unavailable on Windows | 1 | Added macOS CI as the authoritative compile/XCTest gate and limited local claims to static/JSON checks. |

---

# 第三、四、五阶段 iOS 实施计划

## Goal

在 `iOS` 分支把已冻结的 Android 本地数据/fixture 契约落成可持续演进的 iOS
实现：先完成离线导入、浏览、本地编辑和主 App -> Widget 快照边界；再接入前台
统一认证与可继续采集状态；最后接入尽力而为的后台同步调度。所有阶段都不把
密码、Cookie、短信验证码或 WebView 会话放入普通备份，所有失败路径默认保持旧
数据和旧快照不变，并为未来 Android 契约更新保留 fail-closed 门禁。

## Scope boundaries

- 第三阶段：Android backup import、首页/成绩/课表/管理领域模型与 SwiftUI 页面、
  本地编辑、原子持久化、Widget 只读快照。
- 第四阶段：`WKWebView` + `WKHTTPCookieStore` 的前台认证边界；状态包括需要登录、
  需要短信、认证成功、可继续采集、可重试失败；仅在 HTTP 契约稳定时使用
  `URLSession`，依赖 JavaScript 时保留可见前台路径。
- 第五阶段：`BGAppRefreshTask`/`BGProcessingTask` 尽力而为调度；认证失效/需短信
  只记录待处理状态并通知用户打开 App；Widget 不执行登录或采集。
- 明确排除：iOS 后台隐藏 WebView 常驻、后台凭据自动填充、Android 源码翻译、
  数据结构智能体代码、未验证的精确定时承诺。

## Architecture and safety gates

- Shared contract first：Swift 读取 `contract-fixtures/golden/`，不复制 fixture，
  所有输入/输出以 `schemaVersion/id` 绑定。
- Ports & Adapters：Foundation-only domain/storage/ports 与 WebKit、WidgetKit、
  BackgroundTasks、SwiftUI 平台适配分层；平台框架不可反向渗透 portable contract。
- Atomic commit seam：导入、编辑、认证状态和同步快照均先验证完整候选值，再一次提交；
  提交失败时保留旧磁盘、旧内存和旧 Widget 快照。
- Security boundary：普通备份只含课程、学期、主题/显示设置及允许的可脱敏成绩/课表
  数据；凭据仅入 Keychain，Cookie 仅入 `WKHTTPCookieStore`，短信验证码只在前台
  短生命周期内存中处理。
- Fail closed：缺失/未来 schema、未知枚举、悬空 ID、认证未完成、缺少采集前置条件、
  后台任务不可执行时均返回显式状态，不伪造成功。

## Phases

- [x] Phase 1: Swift 离线 contract/import/storage/editor/snapshot seam 与 XCTest
- [x] Phase 2: SwiftUI 首页、成绩、课表、管理页面及本地编辑接入
- [x] Phase 3: WidgetKit 只读快照适配与离线端到端验收
- [x] Phase 4: 前台 WebView/cookie 认证端口、状态机与采集策略（含生产前台采集接线）
- [ ] Phase 5: BackgroundTasks 尽力而为同步、待处理状态和通知入口
- [ ] Phase 6: macOS XCTest/静态门禁、Android fixture 兼容性、文档和回滚验收
- [ ] Phase 7: GitHub macOS `iphoneos` archive、可重签名 IPA 产物和 iPad 安装验证
- [x] Phase 8: 无 Mac 用户的云端设备 IPA 构建与平板重新签名交付路径设计

## Verification gates

- [ ] 每个新增 Swift adapter 都有 `schemaVersion/id` fixture 输入/expected 断言。
- [ ] 离线导入/编辑失败回滚测试覆盖磁盘失败、未知字段、坏记录和悬空引用。
- [ ] Widget 测试只能通过快照 reader 读数据，无法访问认证或采集端口。
- [ ] 认证状态转换和后台调度均有可观察、可取消、可重试/待处理测试。
- [ ] Windows 只报告可执行的 Python/Android/static 检查；Swift/Xcode 由 macOS CI
  authoritative gate 验证。
- [ ] 设备 IPA 从 macOS `iphoneos` archive 的 `.app` 原子打包；产物明确标为
  `re-signable`，不伪称可直接安装，也不把证书、provisioning profile 或 App Group
  entitlement 秘密提交到仓库。
- [ ] `git diff --check`、fixture validator、Android 回归和 workflow pin 检查通过。

## Errors Encountered

| Error | Attempt | Resolution |
|---|---:|---|
| Windows lacks Swift/Xcode toolchain | 1 | Keep compile/XCTest as macOS CI authoritative gate; use Foundation source/static checks locally. |
| Windows Swift 6.3.3 initially lacked `link.exe` | 1 | Installed Swift toolchain, then installed Visual Studio Build Tools C++ workload so Swift Package tests can link locally; iOS SDK remains macOS-only. |

## 2026-09-07 continuation: iPhone/iPad target and shared snapshot hardening

- 产品目标再次确认：只发布 iPhone/iPad；`macOS` 只表示 Swift/Xcode 的开发与 CI 宿主，
  不表示 Mac App 或 Mac Catalyst 支持。Xcode App/Widget target 仍固定为
  `iphoneos iphonesimulator`、`TARGETED_DEVICE_FAMILY = 1,2`、`SUPPORTS_MACCATALYST = NO`。
- App Group 快照边界已 fail-closed：`sharedSnapshotURL` 只返回
  `group.cn.nwpu.aoxiang-assistant` 的共享路径；缺少 entitlement、签名 capability 或非 iOS
  宿主时返回 unavailable，不再回退到 App/Widget 各自的私有目录。
- 主 App 和 Widget 共用 `WidgetSnapshotStore` seam。共享容器不可用时，主 App 保留本地数据
  编辑能力但明确提示小组件不可用；Widget 返回空状态；后台同步不注册/不调度，避免产生
  无法被 Widget 读取的“成功快照”。
- TDD seam 增加 `UnavailableWidgetSnapshotStore` 的读写失败断言；Python 工程配置测试
  同时锁定 `sharedSnapshotURL` 和无 `snapshotURL()` 私有回退。

## Continuation verification

- Python/PR/workflow tests: 44 passed。
- Golden validator: 1 version, 15 scenarios, 32 referenced fixture files。
- Android: 123 JVM tests, 0 failures/errors/skips；Debug APK assemble successful；lint 0
  errors/189 existing warnings；APK SHA256 remains
  `47299933E3F21A6473E15ECB7768522EC300194A7F2A2B4DFDC7C6A74946EE18`。
- `git diff --check`: passed。
- Windows has no Swift/Xcode toolchain. `swift test` and `xcodebuild -sdk iphonesimulator` remain
  mandatory macOS CI gates; do not close the goal until those results are available.

---

# 历史计划副本（已由上方实施计划取代）

> 本段保留用于追溯早期启动状态；当前阶段、验证结果和未完成门禁以上方的
> “第三、四、五阶段 iOS 实施计划”及其 2026-09-08 continuation 为准。

## Goal

在 `iOS` 分支把已冻结的 Android 本地数据/fixture 契约落成可持续演进的 iOS
实现：先完成离线导入、浏览、本地编辑和主 App -> Widget 快照边界；再接入前台
统一认证与可继续采集状态；最后接入尽力而为的后台同步调度。所有阶段都不把
密码、Cookie、短信验证码或 WebView 会话放入普通备份，所有失败路径默认保持旧
数据和旧快照不变，并为未来 Android 契约更新保留 fail-closed 门禁。

## Scope boundaries

- 第三阶段：Android backup import、首页/成绩/课表/管理领域模型与 SwiftUI 页面、
  本地编辑、原子持久化、Widget 只读快照。
- 第四阶段：`WKWebView` + `WKHTTPCookieStore` 的前台认证边界；状态包括需要登录、
  需要短信、认证成功、可继续采集、可重试失败；仅在 HTTP 契约稳定时使用
  `URLSession`，依赖 JavaScript 时保留可见前台路径。
- 第五阶段：`BGAppRefreshTask`/`BGProcessingTask` 尽力而为调度；认证失效/需短信
  只记录待处理状态并通知用户打开 App；Widget 不执行登录或采集。
- 明确排除：iOS 后台隐藏 WebView 常驻、后台凭据自动填充、Android 源码翻译、
  数据结构智能体代码、未验证的精确定时承诺。

## Architecture and safety gates

- Shared contract first：Swift 读取 `contract-fixtures/golden/`，不复制 fixture，
  所有输入/输出以 `schemaVersion/id` 绑定。
- Ports & Adapters：Foundation-only domain/storage/ports 与 WebKit、WidgetKit、
  BackgroundTasks、SwiftUI 平台适配分层；平台框架不可反向渗透 portable contract。
- Atomic commit seam：导入、编辑、认证状态和同步快照均先验证完整候选值，再一次提交；
  提交失败时保留旧磁盘、旧内存和旧 Widget 快照。
- Security boundary：普通备份只含课程、学期、主题/显示设置及允许的可脱敏成绩/课表
  数据；凭据仅入 Keychain，Cookie 仅入 `WKHTTPCookieStore`，短信验证码只在前台
  短生命周期内存中处理。
- Fail closed：缺失/未来 schema、未知枚举、悬空 ID、认证未完成、缺少采集前置条件、
  后台任务不可执行时均返回显式状态，不伪造成功。

## Phases

- [ ] Phase 1: Swift 离线 contract/import/storage/editor/snapshot seam 与 XCTest
- [ ] Phase 2: SwiftUI 首页、成绩、课表、管理页面及本地编辑接入
- [ ] Phase 3: WidgetKit 只读快照适配与离线端到端验收
- [ ] Phase 4: 前台 WebView/cookie 认证端口、状态机与采集策略
- [ ] Phase 5: BackgroundTasks 尽力而为同步、待处理状态和通知入口
- [ ] Phase 6: macOS XCTest/静态门禁、Android fixture 兼容性、文档和回滚验收

## Verification gates

- [ ] 每个新增 Swift adapter 都有 `schemaVersion/id` fixture 输入/expected 断言。
- [ ] 离线导入/编辑失败回滚测试覆盖磁盘失败、未知字段、坏记录和悬空引用。
- [ ] Widget 测试只能通过快照 reader 读数据，无法访问认证或采集端口。
- [ ] 认证状态转换和后台调度均有可观察、可取消、可重试/待处理测试。
- [x] Windows 已执行可移植的 Swift/XCTest、Python、fixture 与 Android 检查；Xcode 的
  iPhone/iPad archive 仍由 macOS CI authoritative gate 验证。
- [ ] `git diff --check`、fixture validator、Android 回归和 workflow pin 检查通过。
- [ ] macOS workflow 已生成可重签名 IPA，且 iPad 端签名/安装已得到真实证据。

## Errors Encountered

| Error | Attempt | Resolution |
|---|---:|---|
| Windows lacks iOS SDK/Xcode | 1 | 安装 Swift 6.3.3 与 C++ linker 后本机可运行 Foundation/XCTest；`iphoneos` archive 仍由 macOS CI 提供。 |

## 2026-09-08 collection and widget continuation

- [x] Foreground collector is wired through the visible authentication WebView's
  cookie store and applies a complete result atomically to local state and the
  shared Widget snapshot.
- [x] Schedule selection mirrors Android: dated semesters are sorted,
  current/next/latest is selected by the Asia/Shanghai business date, and an
  ended activity-derived schedule advances to the next candidate.
- [x] GPA API/portrait fallback, student ID discovery, allow-listed requests,
  online-course filtering, teacher/location normalization and electricity
  parsing remain covered by portable/App tests.
- [x] macOS `xcodebuild` device archive and re-signable IPA structure verification
  completed in GitHub Actions run `34174391367` for commit `3fda090`.
- [ ] Signed full-widget IPA verification and real iPad installation remain external
  gates; the repository does not receive Apple signing credentials, and Windows Swift
  tests do not replace device evidence.

### 2026-09-08 verification

- `swift test --package-path ios/AoxiangCore`: 77 tests, 0 failures/errors.
- `swift test --package-path ios/AoxiangApp`: 15 tests, 0 failures/errors.
- `python -m unittest discover -s scripts/tests -p 'test_*.py'`: 59 tests passed.
- `python scripts/validate_golden_fixtures.py`: 1 version, 15 scenarios, 32
  referenced files.
- `git diff --check`: passed.
- The collector's default date uses `OfflineDatePolicy.businessCalendar`
  (`Asia/Shanghai`) rather than UTC; tests can inject a deterministic date.

### 2026-09-08 macOS archive evidence

- GitHub Actions run `34174391367` completed successfully from the current `iOS` branch
  commit. The job ran both Swift Package suites, archived with `-sdk iphoneos`, packaged
  `AoxiangAssistant-sideload-re-signable.ipa` and
  `AoxiangAssistant-full-widget-re-signable.ipa`, and passed the no-Widget/embedded-Widget
  ZIP layout checks.
- The artifact is downloadable from the run page after GitHub authentication. It is not
  signed; installation still requires the user's own valid App IDs, App Group and nested
  code signing.

## 2026-09-07 iPad-only delivery readiness

- 用户只有可自签安装的 iPad，因此不要求本地 macOS 硬件；GitHub Actions 的
  `macos-latest` 是唯一的 Xcode/archive 宿主，产物明确标记为 unsigned/re-signable。
- iPad 使用者可在 Safari 的 GitHub Actions 页面手动启动 workflow、下载 artifact 并用自己
  的签名工具处理；仓库和 workflow 不接收 Apple ID、证书、private key、profile、密码或会话。
- 自签工具必须同时重签主 App 和内嵌 Widget extension；若无法授权共同的 App Group，离线主 App
  仍可运行，但 Widget 与后台同步保持 disabled/fail-closed。
- 本机验收：Swift Core 64 tests、Swift App 7 tests、Python 49 tests、Android 123 tests 均为
  0 failures/errors；fixture validator 通过 1 version/15 scenarios/32 referenced files；Android
  lint 为 0 errors/186 warnings；`git diff --check` 在本次文档更新前通过。

## 2026-09-07 iPad install hardening and approved artwork

- 图标唯一来源改为用户提供的无透明 PNG；Android 旧 vector 不参与 iOS 生成。
- AppIcon 资源覆盖 iPhone/iPad 目标尺寸，Xcode 工程已启用 `AppIcon` catalog。
- 同一 macOS `iphoneos` archive 现在生成 `AoxiangAssistant-sideload-re-signable.ipa` 和
  `AoxiangAssistant-full-widget-re-signable.ipa`；前者移除嵌套 Widget，后者保留完整 Widget/App Group。
- Python/fixture 回归 55 tests 通过；远端 Swift/Xcode archive、artifact 下载和真实 iPad 安装仍为
  当前目标的未完成验证门。
