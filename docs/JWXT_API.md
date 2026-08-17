# 西工大教务系统 API 清单

本文档是对 `https://jwxt.nwpu.edu.cn` 学生端前端的接口盘点，独立于 [翱翔助手当前采集接口](API.md)。盘点时间为 2026-08-17，使用模拟器中的学生账号打开教务首页及 29 个只读菜单页，记录了 164 个网络请求，其中去掉静态资源和 HTML 模板后得到 65 个业务 XHR/Fetch 接口。

这里的“全部”指当前学生角色可以从前端菜单、页面源码和已加载脚本发现的接口，不等于服务端所有控制器，也不包含教师、管理员或未授权模块。学校升级前端后，接口路径和字段可能变化。

## 使用边界

- 所有接口都要求合法的统一身份认证会话；不要尝试绕过登录、验证码或权限检查。
- 请求应在教务系统同源页面中发送，并携带当前 WebView Cookie。命令行直接请求可能被 412 风控拦截。
- 下表只记录路径、参数名和字段名，不记录任何真实学号、Cookie、令牌、姓名或接口返回数据。
- `{studentId}`、`{semesterId}`、`{id}`、`{uuid}` 是占位符，不能照抄为固定值。
- “源码候选”来自前端脚本字符串，未在本次只读页面加载中主动调用；其中带 `save`、`delete`、`upload`、`cancel` 等名称的接口可能改变数据，禁止盲目尝试。

## 认证和地址

| 项目 | 地址或规则 |
| --- | --- |
| 教务站点 | `https://jwxt.nwpu.edu.cn` |
| 学生端上下文 | `/student` |
| 统一认证入口 | `https://jwxt.nwpu.edu.cn/student/sso-login` |
| 学生首页 | `/student/home` |
| 会话 | 由统一认证建立，通常表现为教务域 Cookie；名称和有效期由学校部署决定 |
| 通用响应 | 以页面 AJAX 实际返回的 JSON 为准，不能假定所有接口都有统一包装字段 |
| 评教后端 | `https://jwxt.nwpu.edu.cn/evaluation-student-backend` |
| 评教前端 | `https://jwxt.nwpu.edu.cn/evaluation-student-frontend/` |

## 已验证业务接口

以下接口是在模拟器中实际发生的 `Document`、`XHR` 或 `Fetch` 请求。路径已经去除防护参数和真实 ID；除特别注明外，请求方法为 `GET`。

### 首页、菜单和公共字典

| 方法 | 路径 | 参数或请求体 |
| --- | --- | --- |
| GET | `/student/home/get-account-login-info` | 无 |
| GET | `/student/home/get-current-teach-week` | 无 |
| GET | `/student/home/get-login-count` | 无 |
| GET | `/student/home/get-preference-setting` | 无 |
| GET | `/student/home/get-shortcut-permCodes` | 无 |
| GET | `/student/home/menu` | 无 |
| GET | `/student/individual-setting/get-setting` | 无 |
| GET | `/student/my-notification/get-notices` | 无 |
| GET | `/student/my-notification/get-notifications` | 无 |
| GET | `/student/ws/home-expressway/index-data` | 无 |
| GET | `/student/ws/menu-parameter/get-parameter` | 无 |
| GET | `/student/ws/select-department/departments/getAll` | 无 |
| GET | `/student/ws/select-department/departments/getByBizType` | 业务类型由页面注入 |
| GET | `/student/ws/semester/get/{semesterId}` | 路径中的学期 ID |
| GET | `/student/ws/major-select/data/cultivate-types` | 无 |
| GET | `/student/ws/major-select/data/departments` | 无 |
| GET | `/student/ws/major-select/data/mulMajors` | 无 |
| GET | `/student/ws/major-select/perm-data/mulMajors` | 无 |
| GET | `/student/ws/major-select/perm-data/mulMajors-without-permission` | 无 |
| GET | `/student/ws/thesis-batch/get-batches-by-school-year` | 学年由页面状态决定 |
| POST | `/student/ws/schedule-table/week-indices-digest` | JSON 数组；字段为 `weekIndicesGroupId`、`weekIndices` |

### 成绩和学生画像

| 方法 | 路径 | 参数或用途 |
| --- | --- | --- |
| GET | `/student/for-std/grade/sheet/get-not-retake-grade/{studentId}` | 学生 ID；读取非重修成绩视图 |
| GET | `/student/for-std/grade/sheet/info/{studentId}` | 学生 ID；学期通常通过页面状态或查询参数传入 |
| GET | `/student/for-std/student-portrait/getStdInfo` | 当前学生基础 ID |
| GET | `/student/for-std/student-portrait/getMyGpa` | GPA；翱翔助手直接调用时使用 `studentAssoc={studentId}` |
| GET | `/student/for-std/student-portrait/getMyGrades` | 学生画像成绩概览 |
| GET | `/student/for-std/student-portrait/getMyGradesByProgram` | 按培养方案聚合成绩 |
| GET | `/student/for-std/student-portrait/getSemesterGrades` | 按学期聚合成绩 |
| GET | `/student/for-std/student-portrait/getGradeAnalysis` | 成绩分析 |
| GET | `/student/for-std/student-portrait/getCourseModuleTypeAvgScore` | 课程模块平均分 |
| GET | `/student/for-std/student-portrait/getHistoryAvgScoreTrend` | 历史平均分趋势 |
| GET | `/student/for-std/student-portrait/getScoreRangeGrades` | 分数段统计 |
| GET | `/student/for-std/student-portrait/getUnPassRate` | 未通过率 |
| GET | `/student/for-std/student-portrait/getExamInfos` | 考试信息 |
| GET | `/student/for-std/student-portrait/getProgramCompletionPreview` | 培养方案完成度 |
| GET | `/student/for-student/my-cert/search` | 学生证书或资质信息 |

学生画像接口的具体参数由页面初始化对象提供，不同账户和学期可能不同。GPA 应优先读取 `getMyGpa` 的个人 GPA 字段，不要把画像中的平均分当作 GPA。

### 课表、课程和考试

| 方法 | 路径 | 参数或用途 |
| --- | --- | --- |
| GET | `/student/for-std/course-table/get-data` | 课表页面数据 |
| GET | `/student/for-std/course-table/semester/{semesterId}/print-data/{studentId}` | 结构化课表；学期 ID、学生 ID |
| GET | `/student/for-std/adminclass-course-table/get-data` | 行政班课表 |
| GET | `/student/for-std/adminclass-course-table/print-data` | 行政班课表打印数据 |
| GET | `/student/for-std/course-level/get-search-data/{id}` | 课程层次查询 |
| GET | `/student/for-std/course-notice/semester/{semesterId}/search` | 学期课程通知 |
| GET | `/student/for-std/sports-subject-grade-query/search` | 体育成绩查询 |
| GET | `/student/for-std/program/root-module-json/{id}` | 培养方案根模块 |
| GET | `/student/for-std/majorPrograms/search` | 专业培养方案搜索 |
| GET | `/student/for-std/publicPrograms/search` | 公共培养方案搜索 |

课表打印数据的主要字段为 `studentTableVm.activities`；常见排课字段包括 `weekday`、`startUnit`、`endUnit`、`weekIndexes`、`campus`、`building`、`room` 和 `teachers`。

### 教材、文件和过程材料

| 方法 | 路径 | 参数或用途 |
| --- | --- | --- |
| GET | `/student/for-std/my-textbook/search` | 我的教材查询 |
| GET | `/student/for-std/textbook-order/info/{id}` | 教材订单详情 |
| GET | `/student/common-file/search/download-data` | 公共文件下载数据 |
| GET | `/student/for-std/thesis-topic-ind/student/{id}/search` | 论文题目查询 |

### 教学评价后端

评教页面使用独立的后端前缀 `/evaluation-student-backend`，不能把下列路径拼到 `/student` 后面。

| 方法 | 路径 | 参数或用途 |
| --- | --- | --- |
| GET | `/evaluation-student-backend/api/v1/evaluation/account-setting/get-setting` | 评教账户设置 |
| GET | `/evaluation-student-backend/api/v1/evaluation/account/my-info` | 评教账户信息 |
| GET | `/evaluation-student-backend/api/v1/evaluation/base/current-semester` | 当前评教学期 |
| GET | `/evaluation-student-backend/api/v1/evaluation/base/semesters` | 可用评教学期 |
| GET | `/evaluation-student-backend/api/v1/evaluation/get-enable-semesters` | 已开放评教的学期 |
| POST | `/evaluation-student-backend/api/v1/evaluation/token-check` | JSON 或表单字段 `token` |
| GET | `/evaluation-student-backend/api/v1/student/get-question-category` | 问卷题目分类 |
| GET | `/evaluation-student-backend/api/v1/student/immediate-evaluation/task/{id}` | 即时评价任务 |
| GET | `/evaluation-student-backend/api/v1/student/process-evaluation/task/{id}` | 过程评价任务 |
| GET | `/evaluation-student-backend/api/v1/student/questionnaire/get-tasks` | 问卷任务 |
| GET | `/evaluation-student-backend/api/v1/student/summative-evaluation/config` | 总结性评价配置 |
| GET | `/evaluation-student-backend/api/v1/student/summative-evaluation/results/semester/{semesterId}` | 总结性评价结果 |
| GET | `/evaluation-student-backend/api/v1/student/summative-evaluation/task/semester/{semesterId}` | 总结性评价任务 |
| GET | `/evaluation-student-backend/api/v1/student/textbook-evaluation/get-tasks/semester/{semesterId}` | 教材评价任务 |
| GET | `/evaluation-student-backend/api/v1/student/textbook-evaluation/results/semester/{semesterId}` | 教材评价结果 |

## 页面路由

页面路由不是 JSON API，但它们是前端发现和进入功能的入口。直接打开页面时仍需教务会话。

```text
/student/home
/student/for-std/room-free
/student/for-std/majorPrograms
/student/for-std/publicPrograms
/student/for-std/common-file
/student/for-std/sports-subject-grade-query
/student/for-student/my-cert
/student/for-std/student-info
/student/for-std/student-portrait
/student/for-std/program
/student/for-std/program-completion-preview
/student/for-std/random-program-completion-preview
/student/for-std/adminclass-course-table
/student/for-std/course-table
/student/for-std/course-notice
/student/for-std/textbook-order
/student/for-std/my-textbook
/student/for-std/course-level
/student/for-std/exam-arrange
/student/for-std/other-exam-signup
/student/for-std/grade/sheet
/student/for-std/evaluation/process
/student/for-std/evaluation/timely
/student/for-std/evaluation/summative
/student/for-std/questionnaire
/student/for-std/evaluation/textbook-evaluation
/student/for-std/thesis-topic-ind
/student/for-std/thesis-flow
/student/for-std/process-document
```

页面详情或查询路由还包括：

```text
/student/for-std/adminclass-course-table/info/{id}
/student/for-std/common-file/index/{id}
/student/for-std/course-level/search/{id}
/student/for-std/course-notice/notice-index/{id}
/student/for-std/exam-arrange/info/{id}
/student/for-std/grade/sheet/semester-index/{id}
/student/for-std/my-textbook/search-index/{id}
/student/for-std/other-exam-signup/index/{id}?semeters={semesterId}
/student/for-std/process-document/search/{id}
/student/for-std/program-completion-preview/info/{id}
/student/for-std/program/info/{id}
/student/for-std/random-program-completion-preview/info/{id}
/student/for-std/student-info/info/{id}
/student/for-std/textbook-order/search/{id}
/student/for-std/thesis-flow/info/{id}
/student/for-std/thesis-topic-ind/index/student/{id}
```

## 源码候选接口

下面这些路径在当前前端脚本中出现，但本次盘点没有为了“试接口”主动触发。它们按模块分组，方法和权限必须通过对应页面实际调用确认。

### 课程、选课和公共查询

```text
/student/course-select/admin-proxy
/student/course-select/college-proxy
/student/course-table/info/{studentId}
/student/course-table/get-data
/student/course-table/semester/{semesterId}
/student/courses/info/{studentId}
/student/courses-search/info/{studentId}
/student/educations?bizTypeId={bizTypeId}
/student/ws/course-notice/info/{studentId}
/student/ws/schedule-table/week-indices-digest
/student/ws/room-borrow/free-list
/student/ws/room-borrow/get-table-layout-campus
/student/ws/room-borrow/get-unit-campus
/student/ws/room/get-buildings
/student/ws/room/get-rooms
/student/ws/student/query-by-term
/student/ws/student-perm/query-by-term
/student/ws/teacher/query-by-term
/student/ws/students/export-zaidu-new
/student/ws/select-department/departments/{action}
```

### 申请、培养方案和成绩辅助

```text
/student/for-std/grade/sheet/get-process-grade
/student/for-std/other-exam-signup/checkCommitMent
/student/for-std/other-exam-signup/checkTimeConflict
/student/for-std/program-completion-preview/check-substitute-open
/student/for-std/program-completion-preview/insert-view-log
/student/for-std/program-completion-preview/save-course-substitute-apply
/student/for-std/program-completion-preview/save-credit-outer-apply
/student/for-std/credit-certification-apply/other_apply
/student/ws/bizType/{bizTypeId}/outer-course-credit-certification-switch/is-open
/student/ws/outer-course-credit-certification-apply/get-assignees
/student/ws/personal-course-substitute/get-assignees
/student/ws/personal-course-substitute/get-original-course
/student/ws/common-audit-service/wait-audit-nodes
/student/for-std/process-document/delete
```

### 论文和毕业流程

```text
/student/ws/thesis-batch/data-perm/get-batches-by-school-year
/student/ws/thesis-batch/get-all-batches
/student/ws/thesis-batch/get-batches-by-school-year
/student/ws/thesis-batch/in-time/data-perm/get-batches-by-school-year
/student/ws/thesis-in-school-adviser/get-by-adviser
/student/ws/thesis-in-school-adviser/get-by-advisers
/student/ws/thesis-in-school-adviser/query-by-term
/student/ws/thesis-selection/check-can-audit-pass
/student/ws/thesis/major-select/data/mulMajors
/student/ws/thesis/selection/check-in-time
/student/ws/thesis/topic-apply/check-in-time
/student/ws/thesis/topic-apply/check-in-time-by-applyId
/student/ws/thesis/topic-apply/check-in-time-by-applyIds
/student/ws/thesis/topic-batch-check/check-audit-dowlond
/student/ws/thesis/topic-batch-check/check-audit-open
/student/ws/thesis/topic-batch-check/check-is-open
/student/ws/thesis/topic-batch-check/multiple/check-apply-is-open
/student/ws/thesis/topic-batch-check/multiple/check-flow-is-open
/student/ws/thesis/topic-batch-check/multiple/check-is-open
/student/ws/thesis/topic-batch-check/multiple/check-selection-is-open
/student/for-std/thesis-selection/check-can-cancel
/student/for-std/thesis-selection/check-can-enter-select
/student/for-std/thesis-selection/check-can-select
/student/for-std/thesis-selection/check-can-upload
/student/for-std/thesis-selection/selection-info
/student/for-std/thesis-selection/cancel
/student/for-std/thesis-selection/upload
/student/for-std/thesis-flow/check-defense-group-publish
```

### 首页配置和通知写接口

```text
/student/ws/menu-parameter/save-parameter
/student/ws/menu-parameter/remove-parameter
/student/ws/notification/get-alert-notifications
/student/ws/notification/update-notification-state/{id}
```

这些接口可能保存用户配置、改变通知状态或提交申请。除非已经确认请求体、权限和业务后果，否则只读集成不应调用它们。

## 调用和解析建议

1. 先访问 `/student/home` 或对应业务页，确认当前 URL 不在 `uis.nwpu.edu.cn`，再发起同源请求。
2. 用页面注入的 `studentId`、学期列表和业务参数，不要猜测或硬编码 ID。
3. 记录 HTTP 状态、响应 `Content-Type` 和业务错误字段；不要只用 HTTP 200 判断成功。
4. 结构化接口失败时回退页面读取；短信验证、安全验证和会话失效必须交给人工认证。
5. 查询接口应限制并发和频率；不要批量遍历学期、学生或教师 ID。
6. 接口变更时重新做一次“页面菜单 + Network XHR/Fetch”盘点，并更新本文件的日期和覆盖范围。

## 盘点方法

本次仅做只读操作：使用模拟器真实登录会话打开教务首页和学生菜单页，记录 `Document/XHR/Fetch` 请求，并从同页脚本提取未自动触发的候选路径。所有 URL 查询值、POST 数据值、数字 ID 和会话信息在落盘前均被删除或替换为占位符。
