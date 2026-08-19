# 翱翔助手

翱翔助手是一款面向西北工业大学学生的非官方 Android 应用，用于集中查看课表、成绩与宿舍电费。应用通过校方统一身份认证访问相关系统，采集过程在设备端完成。

> 本项目不是西北工业大学官方应用，与学校及相关系统运营方无隶属关系。校方页面或接口调整后，部分同步功能可能需要适配。

## 功能

- 首页汇总 GPA、课程数量、剩余电费与今日课程。
- 成绩页展示课程成绩、学分、绩点、成绩构成及加权结果。
- 周课表在一页显示周一至周日，支持跟手滑动切换周次、月历滑动切换月份和课程详情。
- 提供今日/今明课表、GPA、剩余电费、GPA 与电费组合及首页数据概览桌面小组件，覆盖 `1×1`、`2×1`、`4×1` 和 `2×2` 尺寸，并在系统选择器中显示布局预览。
- 自动识别地点中包含“友谊”的课程，按上课日期切换友谊校区夏季或冬季作息；全友谊课程周的左侧节次时间也会同步切换。
- 支持从教务系统手动或定时同步成绩与课表，课表变化时发送通知。
- 支持从一卡通平台读取宿舍剩余电量，并按自定义阈值提醒。
- 支持手动管理学期与课程，以及导入、导出本地课表数据。
- 支持深色模式、主题色和分钟/小时/天级别的更新间隔。
- 自动更新由 Android 到期闹钟和短时前台同步服务维持，设备重启后会按设置恢复。
- 设置采用分类二级面板，成绩和课表变化通知可分别控制并显示具体课程。
- 登录时先验证翱翔门户账号和密码，首次登录成功后自动同步成绩、课表和电费。
- 登录或切换账号连续两次失败后会打开校方统一认证页面，只有实际进入教务系统首页才判定认证成功。
- 可选择打开应用时进入首页、课表、成绩、管理或设置页。
- GPA 从学生画像读取，加权成绩在本地按学分计算；同名重修课程只保留分数最高的记录。
- 首次登录后的数据同步在后台完成；电费系统每日 00:00–01:00 结算期间会暂停查询，并在 01:00 后恢复。
- 每次打开应用时从 GitCode 检查新版本，关于页也可手动检查；可查看更新内容、下载安装包或跳过当前版本。

## 更新日志

版本变化请查看 [CHANGELOG.md](CHANGELOG.md)。

当前使用的教务及一卡通数据路径、字段映射和采集状态协议见 [接口文档](docs/API.md)；教务学生端已发现的完整接口清单见 [JWXT API 清单](docs/JWXT_API.md)。

## 安装

国内用户可从 [GitCode Releases](https://gitcode.com/lorcas/aoxiang-assistant/releases) 下载最新 APK，也可以使用 [GitHub Releases](https://github.com/Lorcas-Zephyr/aoxiang-assistant/releases)。Android 可能要求允许浏览器或文件管理器“安装未知应用”。

正式版本使用固定发布证书签名。升级时直接安装新版 APK 即可保留本地数据，无需先卸载旧版本。

## 登录与隐私

- 教务账号和密码使用 Android Keystore 加密后保存在本机私有存储中。
- 设置页保存账号时会先向校方统一认证验证；密码或验证码错误会直接提示。
- 登录、成绩、课表和电费采集均在应用内完成，不上传到开发者服务器。
- 退出登录会清除本地账号、Cookie、成绩、课表、电费缓存和相关通知。
- 自动更新通过不可见的应用内 WebView 访问校方系统；登录失效时需要重新认证。
- Android 唤醒后台同步期间会暂时显示更新通知，同步完成后自动消失；可在设置中关闭全部自动更新来停止后台同步。

使用本项目代表你理解并同意遵守学校相关系统的使用规定。请勿将账号、发布签名、Cookie 或其他敏感数据提交到仓库。

## 构建

要求：

- JDK 17
- Android SDK Platform 35
- Android SDK Build Tools 35

配置 `local.properties`：

```properties
sdk.dir=/path/to/Android/Sdk
```

运行测试、Lint 和调试构建：

```bash
./scripts/build.sh :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

调试 APK 输出到：

```text
app/build/outputs/apk/debug/app-debug.apk
```

Release 构建需要在项目根目录提供未纳入版本控制的 `keystore.properties` 和对应密钥库。请勿复用示例密码，也不要公开发布私钥。

## 项目结构

```text
app/src/main/java/cn/nwpu/campus/  Android 原生代码
app/src/main/assets/api_collect.js  校方结构化数据采集脚本
app/src/main/assets/auto_collect.js 页面兼容采集脚本
app/src/test/                       单元测试
docs/API.md                         数据接口与采集协议
docs/JWXT_API.md                   教务学生端接口盘点
scripts/build.sh                    构建入口
```

## 致谢

课表管理相关功能参考了 [Whippap/soaring-schedule-remake](https://github.com/Whippap/soaring-schedule-remake)，感谢原作者。

## 反馈

用户交流群：`450804497`。也可以通过 [GitHub Issues](https://github.com/Lorcas-Zephyr/aoxiang-assistant/issues) 提交问题。报告同步故障时请隐藏学号、姓名、Cookie、房间号等个人信息。
