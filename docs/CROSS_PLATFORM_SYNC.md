# Android/iOS 跨平台同步契约

这份文档定义 Android 更新后如何低风险地同步到 iOS。同步对象是可观察的行为和数据契约，不是 Java 到 Swift 的代码翻译。当前行为基线是 `v2.2.2`；共享行为 fixture corpus 位于 [`contract-fixtures/golden`](../contract-fixtures/golden/)，当前版本为 `v1`。第一阶段的本地数据/备份边界仍以 [`LOCAL_DATA_CONTRACT.md`](LOCAL_DATA_CONTRACT.md) 为准。

## 主机与发布平台边界

- 产品发布目标只有 iPhone 和 iPad。Xcode 的 App 与 Widget target 固定为
  `iphoneos iphonesimulator`、设备族 `1,2`，并关闭 `SUPPORTS_MACCATALYST`；不会产出
  macOS 或 Mac Catalyst 版本。
- macOS 只是一台 CI/开发验证主机。macOS 上运行 Swift Package 测试，是为了验证
  Foundation 层和共享契约；Xcode 门禁使用 `iphonesimulator` SDK 编译真正的 iOS App
  和 Widget，不等于支持 macOS 发布。
- CI 的 Xcode 构建关闭签名，仅证明工程、依赖和 iOS 目标可以编译。真机安装、归档和
  发布仍必须在 macOS 的 Apple 工具链中使用团队签名配置完成。

## 不变的边界

两端可以分别实现 UI、WebView、后台任务和本地存储，但以下结果必须由同一份契约约束：

- 成绩、GPA 回退、同名重修和成绩构成的归一化结果；
- 课表周次、单双周、校区作息、教师/地点和线上课程过滤；
- 电费结算时段与异常响应；
- 认证阶段的可观察结果、课程差异和通知文本；
- 导入/导出 JSON 的字段、枚举、日期时间和迁移行为。

密码、Cookie、token、`Authorization` header、短信验证码、WebView 会话、真实学号/姓名/宿舍信息不属于共享契约。它们只能留在各平台的安全存储或会话容器中，也不能进入 fixture、备份、截图、日志或 CI 输出。

## 版本规则

### 行为基线

`v2.2.2` 是重构前的行为基线。发现 Android 与 iOS 结果不一致时，先判断是实现缺陷还是有意变更；没有经过 fixture、迁移和发布说明的变更，不得用“Android 已更新”作为理由直接改写 iOS 结果。

### Golden fixture 版本

- 只调整现有场景的兼容输入/元数据，且旧 `expected.json` 仍然正确时，留在当前 `golden/vN`；
  为避免已审阅基线漂移，新增场景或 kind 应建立下一个 `golden/vN`，而不是悄悄追加到旧版本。
- 旧输入的 expected 需要改变，先把它视为行为变更：更新 fixture、补测试和 changelog，并在 PR 中说明旧版本是否仍受支持。
- 解析规则或输出结构无法兼容旧行为时，建立 `golden/v2`，保留 `v1` 作为回归集；不要覆盖旧目录来隐藏差异。
- `expected.json` 必须由人工或独立参考实现确认，不能由被测 Android/iOS 实现自动生成。

### JSON schema 与迁移

- 可读的旧数据必须继续导入；新增字段优先采用可选/默认值。
- 破坏性字段、枚举、ID、日期时间或时区变化必须同时提升 `schemaVersion`、建立新的 `golden/vN`、保留上一版 fixture，提供 `旧版本 -> 新版本` 的迁移测试，并保留失败可观察性。
- 迁移采用一次性、可重复验证的纯函数；迁移失败时保留原始字节，不把部分结果当成成功写回。
- `schemaVersion` 不是应用版本号。应用升级可以不改 schema；schema 升级也必须单独记录兼容矩阵。

### 稳定表示

共享 JSON 使用以下约定：日期 `YYYY-MM-DD`，时间 `HH:mm`，带时刻的值使用带 offset 的 ISO-8601；业务计算时区为 `Asia/Shanghai`；枚举使用文档化的稳定字符串；ID 是不透明字符串，不能依赖数据库自增或数组顺序。JSON 对象成员顺序不构成行为差异。

## CI 门禁

工作流 [`cross-platform-contract.yml`](../.github/workflows/cross-platform-contract.yml) 在 PR、`main`/`iOS` 分支 push 和手动触发时运行三个跨平台检查；PR 另外由受信任的 [`pr-contract-gate.yml`](../.github/workflows/pr-contract-gate.yml) 运行声明门禁：

0. **Validate PR contract declaration (trusted)**：`pull_request_target` 只 checkout PR 的
   base SHA，读取 PR 正文和 GitHub API 返回的全部 changed files，再运行 base 版本的校验脚本；
   不执行 PR 分支可修改的 validator，避免自修改门禁。

   该检查
   强制且只能选择一种变更分类。共享行为必须勾选脱敏 fixture 和独立 expected，并且
   changed files 中实际包含 `contract-fixtures/` 与 `expected.json`；破坏性
   变更还必须填写新 schema/golden 版本并确认迁移测试；契约敏感文件不能伪装成
   platform-only，安全声明和验证/回滚记录不能为空。

1. **Validate shared fixtures**（Ubuntu）：运行唯一的静态入口
   `python scripts/validate_golden_fixtures.py`，并运行 `scripts/tests` 中的 validator 回归测试。它检查 manifest 引用、路径安全、脱敏边界和 expected/input 隔离，不执行任何平台实现。
2. **Android test, build, and lint**（Ubuntu）：使用 JDK 17 运行
   `./gradlew :app:testDebugUnitTest :app:assembleDebug :app:lintDebug --no-daemon --console=plain`，同时验证 JVM 行为、Debug 构建和 lint error 门禁；其中
   `GoldenCorpusCoverageTest` 会在新增 fixture scenario/id 但尚未补 Android 行为测试时 fail-closed。
3. **iOS contract readiness**：在 macOS 再运行同一 fixture 校验，捕获大小写、路径和换行等跨平台问题；Python
   校验器是 manifest/重复键/敏感内容的结构权威，Swift Package 负责 Foundation 读取、路径 containment
   和 capability/readiness 入口；随后要求
   `ios/AoxiangCore/Package.swift` 存在并运行
   `swift test --package-path ios/AoxiangCore`、`swift test --package-path ios/AoxiangApp`，并用共享
   `AoxiangAssistant` scheme 通过无签名 `xcodebuild` 的 `iphonesimulator` 构建验证 App 和
   Widget 产物。缺包、测试失败或任一 iOS 产物缺失都会使 job 失败，不能只用 fixture 静态校验
   代替 iOS 工程验证。

建议在 GitHub branch protection 中把三个平台 job（`Validate shared fixtures`、
`Android test, build, and lint`、`iOS contract readiness`）以及 PR 另加的
`Validate PR contract declaration (trusted)` 都设为目标分支的 required status checks。
工作流采用 fail-closed 策略：iOS Package、fixture 校验器或任一平台测试缺失时均不能通过。

当前 macOS job 是 **readiness 门禁**：它验证共享文件可被 Swift 安全读取、App/Widget iOS 工程可由
`iphonesimulator` SDK 无签名编译，并校验能力报告与 manifest 完全对应，但不会把仍为 `pending` 的业务
adapter 冒充为已完成。macOS 只是验证主机，不改变产品仅面向 iPhone/iPad 的边界。`ios-v*` 发布 tag
会自动启用严格覆盖；也可以在手动运行工作流时勾选 `require_ios_business_coverage`，或在仓库
Variables 中设置 `AOXIANG_IOS_RELEASE_GATE=1`。严格模式以 `AOXIANG_REQUIRE_IOS_BUSINESS_COVERAGE=1`
再跑 Swift 测试，只要还有一个业务 kind 为 `pending` 就会失败。

Python 和 Swift 两侧都从 `contract-fixtures/golden/` 自动发现全部 `vN`，并要求从
版本目录从 `v1` 连续编号、目录号等于 manifest `schemaVersion`。因此增加 `golden/v2` 后，旧
CI 命令也会自动纳入它；同时必须把 Swift `GoldenFixtureContract.supportedSchemaVersions`、
capability report 的 `fixtureSchemaVersions` 更新为 `[1, 2]`，为新增 scenario 写入
`vN/scenario-id` capability key，并增加对应迁移/行为测试；
遗漏任一项时 macOS job 会 fail-closed。

## 快速日常流程

一次共享行为更新按以下顺序进行：

1. 从当前基线分支创建短生命周期分支，先写失败的 fixture 测试或新增场景。
2. 脱敏并固定 `input.json`、必要的 HTML 和人工确认的 `expected.json`；不要复制真实响应中的账号、Cookie、验证码或身份信息。
3. 在 Android 实现中修复/实现，运行 fixture 测试和本地完整 JVM 测试。
4. 将同一 fixture 交给 iOS domain adapter/XCTest；允许平台内部代码不同，但输入、输出和错误边界必须一致。
5. 按 PR 模板选择唯一主分类：平台专属、共享行为或 wire/contract breaking；填写 fixture、迁移、changelog 和回滚说明。
6. 等待三个平台 job 和 trusted PR declaration 全部完成，再合并。若只是平台专属改动，也要确认没有意外改变共享 JSON 或通知文本。

本地最小检查（仓库根目录）：

```bash
python scripts/validate_golden_fixtures.py
python -m unittest discover -s scripts/tests -p "test_*.py" -v
./gradlew :app:testDebugUnitTest --no-daemon --console=plain
```

本地还必须运行 Swift 契约测试：

```bash
swift test --package-path ios/AoxiangCore
swift test --package-path ios/AoxiangApp
xcodebuild -project ios/AoxiangAssistant.xcodeproj \
  -scheme AoxiangAssistant \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$RUNNER_TEMP/aoxiang-assistant-derived-data" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

最后一条命令必须在 macOS/Xcode 上执行；Windows 或 Linux 没有 iOS SDK，不能用本地命令
替代这项验证。

## 发布门禁

发布前必须满足：

- 目标分支上的三个 CI job 通过，且使用了将要发布的提交；
- 所有共享行为变更有 fixture 和独立 expected；
- schema/wire breaking 变更有版本提升、迁移测试、兼容说明和 changelog；
- Android 契约测试通过，Swift readiness 测试通过，且 capability report 没有 `pending`；缺少 Swift Package 或待实现的 adapter 视为 iOS 发布阻塞，而不是兼容性证明；
- 构建产物、日志和 release notes 不含秘密或真实个人数据。

现有 tag 发布工作流负责上传发布资产；它不应被视为自动替代上述契约门禁。仓库管理员应在分支保护/发布检查中要求契约工作流通过，并在打 tag 前确认检查对应同一 commit。

## 回滚与故障处理

### 实现回归

先停止继续扩大 fixture 变更，保留失败输入和 CI 运行链接。若是最近一次实现导致的回归，优先 `git revert` 对应提交并重新运行三个 job；不要通过修改 expected 来让失败变绿。之后再用一个新 PR 修复实现并补回归场景。

### 契约或 schema 回归

1. 暂停发布，确定受影响的 schema/fixture 版本和已落地的迁移。
2. 若旧数据仍可安全读取，回滚实现但保留旧 schema；若已经写出新格式，先发布向后兼容的读取/迁移，再回滚 UI 或平台实现。
3. 保留旧 `golden/vN` 目录和迁移测试，避免回滚后丢失证据。
4. 对用户不可逆的导出/导入变化，在 release notes 中写明恢复路径；绝不要求用户提供密码、Cookie 或短信验证码作为“修复备份”。

### CI 或单个平台暂时不可用

不要跳过检查并声称同步完成。平台专属改动也需要三个平台 required checks；共享行为、schema 和 wire 变更必须等待对应 runner/测试恢复。紧急发布若由仓库管理员绕过保护，必须记录例外、影响范围和后续补测任务，且不得把未测试的 iOS adapter 描述为兼容。

## iOS 接入完成后的收口

`ios/AoxiangCore/Package.swift` 直接从仓库读取 `contract-fixtures/golden`，自动发现所有连续版本，
先按 `schemaVersion/id` 校验 capability，再按 fixture `kind` 分派到纯 Foundation/domain adapter，
不提交第二份 fixture 副本。先完成 portable contract、迁移和 domain 测试，再接入 SwiftUI/UIKit；UI
不应持有 JSON 迁移或安全会话逻辑。这样 Android 后续每次共享行为更新都会自动暴露 iOS 缺失适配或
输出漂移，而不要求两端代码结构相同。只有已由 Swift 测试实际覆盖、具备真实 adapter 注册并在
`contract-capabilities.json` 标记为 `covered` 的 adapter 才能被列入兼容矩阵；当前全部业务 kind
为 `pending`，所以 readiness CI 通过只代表接入骨架可靠，不代表 iOS 行为已经实现。
