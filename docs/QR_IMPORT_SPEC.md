# 课表二维码内容规范 v1

本规范约定"扫码导入课表"功能的二维码内容格式。应用端（翱翔助手 `applyBackupText`）按本文档解析；生成端（教务增强脚本、网页工具等）按本文档构造二维码。

## 1. 内容格式

二维码文本由三部分拼接：

```text
aoxiang-schedule:v1:<base64>
```

| 部分 | 说明 |
| --- | --- |
| 前缀 | 固定 `aoxiang-schedule:v1:`（版本号用于未来演进，当前固定 `v1`） |
| `<base64>` | `gzip(备份JSON)` 的标准 Base64 编码 |

处理链：**备份 JSON → UTF-8 字节 → gzip 压缩 → 标准 Base64（含 `+/=`，非 URL-safe，无换行）→ 拼接前缀**。

### 兼容模式

应用同时接受**未经压缩、无前缀的备份 JSON 明文**直接作为二维码内容（纯 ASCII 才推荐；含中文的 JSON 明文会占满二维码容量，不推荐）。

### 容量约束

QR Version 40 / 纠错级别 L 的字节容量为 2953 字节。生成端校验：

```text
len("aoxiang-schedule:v1:") + ceil(gzip字节数/3)*4 ≤ 2953
```

即 gzip 后约 ≤ 2199 字节。典型学期课表（30~50 门课程）的紧凑 JSON 经 gzip 后约 1~2 KB，可以装下。超限时按顺序裁剪：删除 `courses[].notes` → `code` → `assessmentMethod`；仍超限则提示无法生成，不要降低纠错级别以下（最低用 L）。

## 2. 备份 JSON 结构

顶层两个字段，结构与应用"导出课表数据"的 JSON 文件完全一致：

```json
{
  "courses": [ {课程对象} ],
  "settings": {
    "semesters": [ {学期对象} ],
    "themeColor": "#2F80ED",
    "darkMode": false
  }
}
```

JSON 生成时使用紧凑序列化（无缩进、无多余空格）以减小体积。

### 2.1 课程对象（courses[]）

| 字段 | 类型 | 必填 | 缺省行为 |
| --- | --- | --- | --- |
| `name` | string | 是 | 缺省为"课程"，建议必给 |
| `semesterId` | string | 是 | 必须与某个 `semesters[].id` 一致，否则该课程不可见 |
| `timeSlots` | array | 是 | 空时应用会塞入一个默认时段（第 1 周周一 1-2 节），应给出真实值 |
| `id` | string | 否 | 应用按 `course-<时间戳>` 生成 |
| `code` | string\|null | 否 | 课程代码 |
| `location` | string\|null | 否 | 默认地点，会被复制到未单独指定地点的时段 |
| `credits` | number\|null | 否 | 学分 |
| `teacher` | string\|null | 否 | 默认教师，同上 |
| `assessmentMethod` | string\|null | 否 | 只识别 `考试` / `考察` / `PnP`，其他值按 null 处理 |
| `notes` | string\|null | 否 | 备注 |
| `color` | string\|null | 否 | `#RRGGBB`，可从应用预设色板选取：`#E53935 #1E88E5 #43A047 #FB8C00 #8E24AA #00ACC1 #FFB300 #3949AB` |

### 2.2 时段对象（courses[].timeSlots[]）

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `weekRange` | string | 是 | 周次，支持 `1-17`、`1,3,5`、`1-8,11` 组合；单周写 `12` |
| `repeatRule` | string | 是 | `""`=全部周，`"仅单周"`，`"仅双周"`（注意是中文存储值） |
| `dayOfWeek` | int | 是 | 1~7 表示周一至周日 |
| `classSections` | int[] | 是 | 节次号列表，连续节次写展开形式 `[5,6,7]`；空时应用按 `[1]` 处理 |
| `teacher` | string\|null | 否 | 覆盖课程级教师 |
| `location` | string\|null | 否 | 覆盖课程级地点；友谊校区地点（含"友谊"）会触发校区作息切换 |

### 2.3 学期对象（settings.semesters[]）

| 字段 | 类型 | 必填 | 缺省行为 |
| --- | --- | --- | --- |
| `id` | string | 是 | 自定义稳定 ID（如 `semester-2026-20271`），课程按它归属 |
| `name` | string | 否 | 缺省"学期" |
| `startDate` | `yyyy-MM-dd` | 是 | **必须是周一**；非周一会被应用到该周周一（`mondayOnOrBefore`） |
| `endDate` | `yyyy-MM-dd` | 否 | 缺省为开始日期 + 17 周 |
| `weekCount` | int | 否 | 缺省 17 |
| `sectionCount` | int | 否 | 缺省 13 |
| `sectionTimes` | array | 否 | `{start:"HH:mm", end:"HH:mm"}` 数组；**可省略**，省略时应用按节次表补齐默认作息 |

学期日期采用教务口径（`startDate`~`endDate` 包含考试周），与教学周推算、考试显示一致。

### 2.4 settings 其他字段

| 字段 | 说明 |
| --- | --- |
| `themeColor` | 可省略或显式 `null`，缺省 `#2F80ED`；提供时必须为合法 `#RRGGBB` |
| `darkMode` | 可省略，缺省 `false` |

扫码导入**只替换**课表（学期、课程、主题），不影响已同步的成绩、考试安排、电费等数据。

## 3. 完整示例

```json
{
  "courses": [
    {
      "id": "course-1",
      "name": "高等数学A(一)",
      "semesterId": "semester-2026-20271",
      "timeSlots": [
        {"weekRange": "1-16", "repeatRule": "", "dayOfWeek": 1,
         "classSections": [1, 2], "teacher": "张三", "location": "长安校区 教学西楼D座 教西D-206"}
      ],
      "code": "MATH1001",
      "location": "长安校区 教学西楼D座 教西D-206",
      "credits": 5.0,
      "teacher": "张三",
      "assessmentMethod": "考试",
      "notes": null,
      "color": "#1E88E5"
    }
  ],
  "settings": {
    "semesters": [
      {
        "id": "semester-2026-20271",
        "name": "2026-2027秋",
        "startDate": "2026-08-31",
        "endDate": "2027-01-17",
        "weekCount": 20,
        "sectionCount": 13,
        "sectionTimes": []
      }
    ],
    "themeColor": "#2F80ED",
    "darkMode": false
  }
}
```

## 4. 生成端参考实现（JavaScript）

浏览器端压缩使用 `CompressionStream`（Chrome 103+；油猴环境为现代 Chromium，可用）：

```javascript
/**
 * 将备份 JSON 字符串构造为二维码内容。
 * @param {string} backupJson - 第 2 节结构的紧凑 JSON 字符串
 * @returns {Promise<string|null>} 二维码文本；超容量时返回 null
 */
async function buildAoxiangQrPayload(backupJson) {
    const gzipped = new Uint8Array(await new Response(
        new Blob([backupJson]).stream().pipeThrough(new CompressionStream("gzip"))
    ).arrayBuffer());
    let binary = "";
    for (const byte of gzipped) binary += String.fromCharCode(byte);
    const payload = "aoxiang-schedule:v1:" + btoa(binary);  // 标准 base64
    return payload.length <= 2953 ? payload : null;
}
```

生成的字符串交给二维码绘制库的**字节模式**编码（payload 为纯 ASCII，无编码歧义），纠错级别用 `L` 以最大化容量。`zxing` 的 `QRCodeWriter`、`qrcode-generator` 等均可。

解析侧（应用端）对应实现：`MainActivity.applyBackupText` —— 前缀识别 → `Base64.NO_WRAP` 解码 → GZIP 解压 → 与文件导入共用 `applyBackupJson`。
