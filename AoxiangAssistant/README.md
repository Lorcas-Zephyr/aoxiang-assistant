# 翱翔教务助手 (HarmonyOS)

西北工业大学教务系统助手，HarmonyOS (ArkTS) 原生客户端。

## 功能

- **成绩查询** — 自动采集全部课程成绩，计算加权 GPA 和加权平均分
- **电费查询** — 实时查询宿舍电费余额
- **课表导入** — 自动导入课程表（开发中）

## 技术实现

- 通过 WebView 自动化模拟 SSO 统一身份认证登录
- `auto_collect.js` 状态机驱动页面导航和数据提取
- HUKS AES-256-GCM 加密安全存储用户凭证
- 成绩与电费数据持久化到 Preferences

## 构建

使用 DevEco Studio 打开 `AoxiangAssistant` 目录，连接 HarmonyOS 设备或模拟器后直接运行。

- 最低 API 版本：12
- 目标 SDK：API 24 (HarmonyOS 6.1.1)
- ArkTS 严格模式

## 项目结构

```
AoxiangAssistant/
├── entry/src/main/
│   ├── ets/
│   │   ├── pages/Index.ets          # 主页面（Tab 导航 + WebView 自动化）
│   │   ├── model/
│   │   │   ├── CredentialStore.ets  # HUKS 加密凭证存储
│   │   │   └── GradeModel.ets       # 成绩数据模型与加权计算
│   │   └── common/Constants.ets     # SSO URL 与状态常量
│   ├── resources/rawfile/
│   │   └── auto_collect.js          # WebView JS 自动化脚本
│   └── module.json5                 # 模块配置与权限声明
├── AppScope/app.json5
└── build-profile.json5
```

## 原安卓版

安卓原版代码位于 `aoxiang-assistant/`（未纳入本仓库版本管理）。
