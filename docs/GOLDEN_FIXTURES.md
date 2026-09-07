# Cross-platform Golden Fixtures

第二阶段的行为标准位于 [`contract-fixtures/golden`](../contract-fixtures/golden/)。
当前提交包含 `v1`，后续不兼容的契约会以连续的 `vN` 目录追加；旧目录必须保留。
它把 Android 当前实现中最容易在 iOS 重写时漂移的输入、规范化输出和异常边界
固定下来；它不是备份，也不承载登录会话。

## Contract

`manifest.json` 是唯一索引。每个场景目录包含独立的 `input.json`、
`expected.json`，HTML 输入场景再包含一个 `.html` 文件。路径相对 manifest，使用
`/`，文件统一 UTF-8；expected 必须是人工确认的字面答案，不能由被测实现生成。

跨平台共享的稳定值如下：

- 日期：`YYYY-MM-DD`；时间：24 小时制 `HH:mm`。
- 带时刻的输入使用 ISO-8601 且必须带 offset；业务计算时区固定为 `Asia/Shanghai`。
- `repeatRule` 只能是 `""`、`"仅单周"`、`"仅双周"`；ID 是不透明字符串。
- 认证只记录可观察 phase/结果，不记录账号、密码、Cookie、token、验证码或身份标识。

## Android seam mapping

| Fixture kind | Android seam |
| --- | --- |
| `grades-api`, `grades-portrait-fallback` | `PortalApiParsers.gradeRows/gpa/portraitGpa/selectGpa` |
| `grades-component-html`, `grades-retake` | `GradeRecord.from/keepHighest` |
| `schedule-*` | `PortalApiParsers.schedulePayload`, `ScheduleImport`, `ScheduleUtils` |
| `electricity-*` | `PortalApiParsers.electricityBalance`, `SyncTimePolicy` |
| `authentication-states` | `AuthenticationPolicy`, `UnifiedAuthTracker` |
| `update-diff-notifications` | `UpdateDiff.changedNames/notificationText` |

这些 seam 是纯输入/输出边界，Android 测试不启动 Activity、WebView 或真实登录；
这样 iOS 可以用 Swift 的 Foundation/HTML 解析器对同一文件做等价测试，同时把平台
会话保留在 Keychain/WKWebsiteDataStore 等各自边界内。

## iOS XCTest 接入

在仓库 checkout 中将 `contract-fixtures/golden` 作为显式注入的测试 corpus（可通过
`AOXIANG_GOLDEN_FIXTURES` 指定非标准路径），自动发现连续的 `vN` 目录，
读取每个 manifest 后按 `schemaVersion/id`（并使用 `kind` 选择 domain adapter）
分派到与上表对应的 domain adapter。测试比较 JSON 值而非文本成员顺序，并对数字使用
明确容差；日期只作为业务日历值处理，不按设备时区平移。iOS 端缺少某个 seam 时，
先补同名纯函数/协议适配器并用 fixture 驱动，再接 UI，不要在测试中复制 Android 的
硬编码 expected。

独立校验命令默认扫描整个 `contract-fixtures/golden/`，而不是只扫描某一个版本。新增
`v2` 时必须保留 `v1`，版本目录从 `v1` 连续编号，且各目录 manifest 的
`schemaVersion` 必须与目录号一致；还要同步更新 Swift `supportedSchemaVersions`、capability
report 和迁移测试。`v1` 使用当前已知场景的严格清单；`v2+` 可以增加新的稳定
kebab-case `id`/`kind`，但每个 `schemaVersion/id` 都必须在 Android 测试、iOS capability
report 和对应平台 adapter 中显式登记，不能靠 validator 的“未知即通过”来宣称兼容：

```bash
python scripts/validate_golden_fixtures.py
```

## 安全门禁

PR 声明由 `pull_request_target` 的受信任 base workflow 校验；Android 的 `GoldenManifestTest` 会检查当前 v1 manifest 覆盖列表、引用文件存在性和敏感字段
名；`GoldenCorpusCoverageTest` 会扫描整个 corpus，并要求每个版本的 scenario `id` 都映射到一个
真实的 Android fixture 测试方法。独立 Python validator 是 manifest 精确字段、重复 JSON key 和
敏感内容的结构权威；iOS 测试保留路径/引用/能力门禁并在 macOS CI 编译执行。
允许出现 `sms_required` 这类状态标签，但禁止验证码值、Cookie、Authorization header、密码字段
及真实身份/宿舍信息进入仓库。
