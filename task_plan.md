# iOS 第一阶段计划

## Goal

在 `iOS` 分支冻结翱翔助手 v2.2.2 的本地数据与备份契约，提供可迁移的 schemaVersion、兼容旧数据的迁移入口、脱敏跨平台 fixture 和测试入口；不改变现有 Android 用户可见行为，也不把凭据或 WebView 会话放入备份。

## Phases

- [x] Phase 1: 盘点 v2.2.2 的存储、备份字段和安全边界
- [ ] Phase 2: 接入版本化本地数组与备份 envelope，保留旧格式读取
- [ ] Phase 3: 写契约文档、跨平台 fixture 和 seam 测试
- [ ] Phase 4: 编译、测试、静态审计并完成目标逐项验收

## Decisions

- 新本地数组 envelope 使用 `schemaVersion: 1` 和 `items`；旧裸数组视为 schema 0，只读时迁移。
- 备份使用 `format: aoxiang-assistant.schedule-backup`、`schemaVersion: 1`；旧 `version: 2.0` 文档继续可读。
- 备份只覆盖课程、学期和主题/深色/选中学期设置；成绩、GPA、电费、同步状态、自动更新设置、凭据、Cookie 和短信验证码不在备份范围内。
- 日期使用 `YYYY-MM-DD`，节次时间使用 `HH:mm`，持久化时间戳使用 Unix epoch milliseconds；身份认证和会话由平台安全存储管理。
- 先测试纯 JSON contract seam，再接入 Android 存储适配器；不在本阶段重写 Activity 或 WebView。

## Errors Encountered

| Error | Attempt | Resolution |
|---|---:|---|
| Gradle wrapper download timeout | Earlier baseline | Record as verification gap; retry with available local cache or report network limitation, never claim green tests without output. |

## Verification Gates

- [ ] 旧 v2.2.2 裸数组可被读取并写成 schema 1 envelope
- [ ] 旧 `version: 2.0` 备份可导入，新备份含 `format` 与 `schemaVersion`
- [ ] 未来 schema 会拒绝且不覆盖原始数据
- [ ] fixture 不含账号、密码、Cookie、验证码或真实个人信息
- [ ] Android 所有成绩/课表消费者使用同一契约读写
- [ ] JUnit、编译和 lint 结果已记录
