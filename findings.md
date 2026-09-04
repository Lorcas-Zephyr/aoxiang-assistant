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
