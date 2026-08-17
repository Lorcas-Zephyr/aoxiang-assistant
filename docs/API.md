# 翱翔助手接口文档

本文档记录翱翔助手 `v2.2.0` 使用的数据来源、请求路径、关键字段和应用内部采集协议，便于后续排查校方系统改版造成的同步故障。

这些地址是西北工业大学网页系统的内部接口，不是由本项目提供的公共 API，也不保证长期兼容。调用者必须拥有合法账号和有效登录会话，并遵守学校相关系统的使用规定。

## 总体流程

应用不把账号、Cookie 或采集结果发送到开发者服务器。登录和请求均在设备端完成：

1. 使用校方统一身份认证建立教务系统或一卡通平台会话。
2. 在对应域名的 WebView 中执行同源 `fetch`，自动携带当前会话 Cookie。
3. 将原始 JSON 交给原生解析器，转换为本地成绩、课表或电费数据。
4. 接口不可用时回退到页面采集；登录失效或触发短信验证时转为可见的人工认证。

所有结构化请求默认使用 `credentials: include`、`cache: no-store`，单个请求超时为 12 秒。代码入口为：

- `app/src/main/assets/api_collect.js`
- `app/src/main/java/cn/nwpu/campus/PortalApiParsers.java`
- `app/src/main/java/cn/nwpu/campus/BackgroundSyncService.java`

## 认证入口

| 系统 | 地址 | 用途 |
| --- | --- | --- |
| 教务系统 | `https://jwxt.nwpu.edu.cn/student/sso-login` | 建立教务系统会话 |
| 教务首页 | `https://jwxt.nwpu.edu.cn/student/home` | 验证是否已离开统一认证并进入教务系统 |
| 一卡通平台 | `https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/supwisdom?targetUrl=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat` | 建立一卡通平台会话 |
| 一卡通首页 | `https://yktapp.nwpu.edu.cn/plat/shouyeUser` | 获取平台令牌并进入电费页面 |

统一认证页面位于 `uis.nwpu.edu.cn`。应用只保存加密后的账号密码和 WebView 会话，不记录短信验证码。

## 教务基础信息

### 获取学生 ID

```http
GET https://jwxt.nwpu.edu.cn/student/for-std/student-portrait/getStdInfo
Accept: application/json
```

关键响应字段：

```json
{
  "student": {
    "id": "<studentId>"
  }
}
```

`studentId` 是教务系统内部关联 ID，不一定等于学号。成绩页或课表页 HTML 中存在 `studentId` 时优先使用页面值，否则调用此接口。

## 成绩

### 获取学期列表

```http
GET https://jwxt.nwpu.edu.cn/student/for-std/grade/sheet/
```

该请求返回 HTML。页面脚本中的 `semesters` JSON 用于获得学期 `id`、名称和顺序。

### 获取学期成绩

```http
GET https://jwxt.nwpu.edu.cn/student/for-std/grade/sheet/info/{studentId}?semester={semesterId}
Accept: application/json
```

路径参数：

| 参数 | 含义 |
| --- | --- |
| `studentId` | 教务系统内部学生 ID |
| `semesterId` | 学期 ID |

应用每批并发请求最多 4 个学期。单个学期失败会被跳过；全部学期均失败时本次更新失败并稍后重试。

关键响应结构：

```json
{
  "semesterId2studentGrades": {
    "<semesterId>": [
      {
        "published": true,
        "course": {
          "nameZh": "课程名称",
          "credits": 3.0
        },
        "gp": 4.0,
        "gaGrade": "95",
        "gradeDetail": "<span>期末成绩:95</span>"
      }
    ]
  }
}
```

字段映射：

| 接口字段 | 本地字段 | 说明 |
| --- | --- | --- |
| `published` | 是否读取 | 明确为未发布时忽略 |
| `course.nameZh` / `lessonNameZh` | 课程名 | 前者优先 |
| `course.credits` | 学分 | 缺失时为 `0` |
| `gp` | 绩点 | 可为空 |
| `gaGrade` | 成绩 | 支持数值或等级文本 |
| `gradeDetail` | 成绩构成 | HTML 实体解码并移除标签后保存 |

所有学期合并后，同名课程按成绩排序，只保留最高的一条，避免重修记录重复计入课程数和加权成绩。

### 获取 GPA

```http
GET https://jwxt.nwpu.edu.cn/student/for-std/student-portrait/getMyGpa?studentAssoc={studentId}
Accept: application/json
```

优先读取 `stdGpaRankDto.gpa`。为兼容不同账户的响应包装，解析器也会在嵌套对象中查找 `gpa`、`avgGpa`、`cumulativeGpa`、`平均绩点` 等同义字段，并只接受 `0-5` 范围内的值。

此接口只提供首页和成绩页显示的 GPA。应用中的加权平均分仍由本地课程成绩和学分计算，不读取学生画像中的平均分。

## 课表

### 获取学期列表

```http
GET https://jwxt.nwpu.edu.cn/student/for-std/course-table
```

该请求返回 HTML。应用解析页面脚本中的 `semesters` JSON，并使用其中的学期 ID 和 `startDate` 选择当前课表。

### 获取学期信息

```http
GET https://jwxt.nwpu.edu.cn/student/ws/semester/get/{semesterId}
Accept: application/json
```

使用字段包括 `id`、`code`、`nameZh`、`name`、`startDate` 和 `endDate`。接口失败时使用课表页学期列表中的数据。

### 获取课表打印数据

```http
GET https://jwxt.nwpu.edu.cn/student/for-std/course-table/semester/{semesterId}/print-data/{studentId}
Accept: application/json
```

关键响应结构：

```json
{
  "studentTableVm": {
    "activities": [
      {
        "courseName": "课程名称",
        "courseCode": "课程代码",
        "weekday": 1,
        "startUnit": 1,
        "endUnit": 2,
        "weekIndexes": [2, 3, 11],
        "campus": "长安校区",
        "building": "教西",
        "room": "B3-101",
        "teachers": ["教师甲", "教师乙"]
      }
    ]
  }
}
```

解析规则：

- `weekday` 使用 `1-7` 表示周一至周日。
- `weekIndexes` 会压缩为 `2~3,11周`，不连续周次不会被错误合并。
- 地点按 `campus + building + room` 去重拼接，保留完整教室号。
- `teachers` 支持字符串或教师对象，并使用 `、` 合并多名教师。
- 名称或地点包含“网课”“线上”“在线”的课程不导入实体课表。
- 空 `activities` 是有效空课表，不会自动跳过。

### 学期选择和结束时间

1. 优先选择当前日期位于 `startDate` 和 `endDate` 之间的学期。
2. 若当前日期不在任何学期内，选择最近的下一个学期；不存在下一个学期时选择最后一个学期。
3. 读取课表后，以最后一项排课的周次和星期计算实际结束日期，且学期至少保留两周。
4. 只有当前日期超过实际结束日期时才继续读取下一学期。

## 电费

当前一卡通页面没有在本项目中确认可长期复用的独立电费 HTTP 接口。应用先从一卡通首页取得 `synjones-auth` 或 `access_token`，再进入：

```text
https://yktapp.nwpu.edu.cn/jfdt/charge/feeitem/toAppitem
  ?feeitemid=182
  &synjones-auth=<token>
  &appId=36
  &loginFrom=h5
  &type=app
```

`feeitemid` 和 `appId` 属于当前一卡通部署配置，校方调整后可能变化。令牌不得写入日志、文档、Issue 或仓库。

页面加载完成后，应用遍历 `#app.__vue__` 组件树，从以下候选位置读取电费数据：

- `component.aboutEleric.electricInfo`
- `component.$data.aboutEleric.electricInfo`
- `component.electricInfo`
- `component.$data.electricInfo`

随后从 `map.showData` 中依次识别 `当前剩余电量`、`剩余电量`、`电费余额` 或 `剩余电费`。只接受大于等于 `0` 且小于 `100000` 的数值。`00:00-01:00` 结算期间不发起电费更新。

## 应用内部采集协议

`api_collect.js` 每次执行返回一个 JSON 字符串，公共字段为 `phase`。原生层根据阶段继续等待、导航、解析或回退。

| `phase` | 含义 | 附加字段 |
| --- | --- | --- |
| `api_waiting` | 异步请求仍在进行 | 无 |
| `api_unavailable` | 当前域名或页面不能使用结构化采集 | 无，原生层回退页面采集 |
| `clicked` | 已导航到目标页面 | `clicked` |
| `grade_api_raw` | 成绩和 GPA 请求完成 | `gradeResponses`、`gpaResponse` |
| `schedule_api_raw` | 学期和课表请求完成 | `semester`、`printData` |
| `electricity_api_raw` | 已从页面状态取得电费数据 | `response` |
| `target_error` | 目标接口请求失败 | `target`、`message` |

采集脚本通过以下占位符由原生层注入运行参数：

| 占位符 | 说明 |
| --- | --- |
| `__MODE__` | `grades`、`schedule` 或 `electricity` |
| `__ALLOW_NAV__` | 当前是否允许执行页面跳转，防止重复导航 |

同一页面内的异步状态保存在 `window.__aoxiangAssistantApiState_<mode>`。完成或失败后重复轮询会返回相同结果，不会重复请求。

## 失败和回退

- HTTP 状态不是 `2xx`、请求超时或 JSON 解析失败会进入 `target_error`。
- 结构化采集不可用时执行 `auto_collect.js` 页面兼容逻辑。
- 后台采集失败不会更新 `auto_last_<target>`，系统会安排稍后重试。
- 登录失效、短信验证码或安全验证不能在后台绕过，会发送认证通知并要求用户打开应用处理。
- 成绩接口成功但 GPA 缺失时，应用保留成绩结果并短暂回退学生画像页面读取 GPA；超时后仍保存成绩。

## 安全边界

- 不要在测试夹具、日志、截图、Issue 或提交记录中保存真实学号、姓名、Cookie、令牌、房间号和完整成绩。
- 不要在应用外复用或转发 WebView Cookie。
- 不要提高请求并发或缩短自动更新间隔来批量访问校方系统。
- 接口字段或路径变化时，优先更新解析器和脱敏测试样例，并保留页面采集回退。
