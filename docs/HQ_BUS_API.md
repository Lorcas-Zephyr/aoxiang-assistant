# 西工大后勤通勤车（小车预约）API 清单

本文档记录 `https://hq-bus.nwpu.edu.cn` 的 H5 预约端接口，来自 2026-09-23 一次真实的浏览器只读操作（打开 `/h5/` → 选路线 → 查班次 → 填预约单）。与 [JWXT_API.md](JWXT_API.md)、[API.md](API.md) 并列。

## 使用边界

- 所有接口都需要合法会话；页面由门户/统一认证跳转进入，本站自身不暴露登录接口。
- 请求应在 `hq-bus.nwpu.edu.cn` 同源页面内发送，并携带当前浏览器 Cookie。
- **必须带防护参数**：直接构造请求会被前置 WAF 拦截（详见文末「防护层」）。
- 本文只记录路径、参数名和字段名，不记录任何真实工号、姓名、Cookie、令牌或班次人数快照。
- `{工号}`、`{路线Objid}`、`{班次objId}` 是占位符，实际值由前一个接口返回。
- 带 `Appointment`/`Order` 的接口涉及真实预约，未在本次盘点中提交任何预约。

## 站点与入口

| 项目 | 值 |
| --- | --- |
| 站点 | `https://hq-bus.nwpu.edu.cn` |
| H5 入口 | `/h5/`（`Referer` 固定为该地址） |
| 首页菜单 | `/api/GetIcon` 返回「通勤车」`CommuterCar?type=通勤车` 和「直通车」`CommuterCar?type=机场\|高铁站` |
| 后端 | ASP.NET（Cookie 含 `ASP.NET_SessionId`） |
| 响应包装 | `{"isSuccess": bool, "data": ..., "IsOpenDialog": bool}` |
| 请求编码 | 全部 `POST` + `application/x-www-form-urlencoded`（字段名区分大小写） |

## 接口清单

以下 5 个接口都是本次真实发生的请求，方法均为 `POST`。

| 路径 | 请求体字段 | 用途 |
| --- | --- | --- |
| `/api/GetIcon` | `GH`=工号, `no`=工号 | 首页功能菜单（通勤车 / 直通车） |
| `/api/GetRouteByType` | `type`=线路类型, `no`=工号 | 按类型取路线列表 + 可提前预约天数 |
| `/api/GetReserveInfoList` | `rq`=乘车日期, `xllx`=线路类型, `xlId`=路线 `Objid`, `gh`=工号, `no`=工号 | 某日某路线的全部班次与余位 |
| `/api/GetMyAppointment` | `YYRGH`=工号, `YYZT`=预约状态, `no`=工号 | 我的预约列表 |
| `/api/GetAppointmentOrder` | `YYRGH`=工号, `CCRQ`=乘车日期, `objid`=班次 `objId`, `SJD`=发车时刻, `no`=工号 | 预约确认页数据（费用、须知、下单前信息） |

> 本次**未捕获**实际提交预约/取消预约的接口。`GetAppointmentOrder` 只到「确认页」，提交动作需要再操作一步才能抓到。

## 关键字段

### `/api/GetRouteByType`

```json
{
  "isSuccess": true,
  "data": {
    "filteredBusRoutes": [
      {
        "Objid": "<路线Objid>",
        "Type": "通勤车",
        "Name": "友谊到长安",
        "StartStation": "友谊校区",
        "EndStation": "长安校区",
        "StudentCharge": "5",
        "TeacherStaffCharge": "0"
      }
    ],
    "reservationDays": { "YYWYXZTS": "7", "TQYYXZTS": "2", "JCTQYYXZTS": "60" },
    "isNeedServerTime": true
  }
}
```

- `Objid` 是后续 `GetReserveInfoList` 的 `xlId`。
- `StudentCharge` / `TeacherStaffCharge` 是字符串形式的金额（学生 5 元，教职工 0 元）。
- `reservationDays`：`TQYYXZTS`=通勤车可提前天数（2），`YYWYXZTS`=预约有效限制天数（7），`JCTQYYXZTS`=机场/高铁站直通车可提前天数（60）。
- `isNeedServerTime` 出现即表示前端要用服务端时间判断能否预约，不能只看本地时间。

### `/api/GetReserveInfoList`

`data` 是班次数组，每个元素：

| 字段 | 含义 |
| --- | --- |
| `objId` | 班次 ID，预约时作为 `objid` 回传 |
| `fcsj` | 发车时刻，`HH:mm` |
| `yyrs` / `kyyrs` | 已预约人数 / 可预约人数（`kyyrs` 为字符串） |
| `sfkyy` | 该班次当前是否可预约 |
| `yyjzxx` | 预约截止说明，如「2026-09-24 06:10截止预约」 |
| `tsxx` | 前端提示文案，含「距离发车时间还有…」 |
| `xshyrs` / `jshyrs` / `zhyrs` | 学生 / 教师 / 综合已约人数 |
| `bcms` | 班次描述 |

注意：

- 日期格式为 `yyyy/M/d`（未补零）。
- 查当天返回空数组、查次日才有班次；预约截止时间是发车前 30 分钟。
- 同一时刻可能不同容量，班次 ID 与时刻一一对应。

### `/api/GetMyAppointment`

```json
{ "isSuccess": true, "data": { "list": [], "isNeedServerTime": true }, "IsOpenDialog": false }
```

`YYZT`（预约状态）为中文枚举，本次使用的是「待核验」。`list` 为空表示当前无预约。

### `/api/GetAppointmentOrder`

```json
{
  "isSuccess": true,
  "data": {
    "yktyfddh": "",
    "yyzt": "",
    "yydh": "",
    "name": "<姓名>",
    "bm": "<部门/单位代码>",
    "yyxz": "<预约须知链接>",
    "fy": "5"
  }
}
```

- `fy` 是本次应付金额；`yyxz` 是公众号图文形式的预约须知。
- `yktyfddh`（一卡通云服务电话）、`yyzt`、`yydh`（预约单号）此时为空，说明还没真正下单。

## 业务流程串联

```text
/h5/
  └─ GetIcon                             取首页菜单，确认功能入口
       └─ GetRouteByType(type=通勤车)     取路线 Objid、费用、可提前天数
            └─ GetReserveInfoList(rq, xlId)  取当日班次、余位、是否可约
                 └─ GetAppointmentOrder(objid, CCRQ, SJD)  取费用与须知（确认页）
                      └─ (未捕获) 提交预约
  └─ GetMyAppointment(YYZT=待核验)        查我的预约
```

## 防护层（与教务系统同源）

本站与 `jwxt.nwpu.edu.cn` 使用**同一套前置 WAF**，两者特征完全一致：

- 响应头 `Server: ******` 被抹除。
- 站点给每个 XHR 追加动态后缀参数。**参数名同为 `qLx64euN`**（8 位大小写字母数字随机串），且在本站**出现两份**：
  - URL 查询串里一份，如 `POST /api/GetRouteByType?qLx64euN=<值A>`；
  - **同名请求头**一份，如 `qLx64euN: <值B>`，与查询串的值不同。
  - 两份值随每次请求重新计算，同一页面内连续请求的值各不相同。
- 浏览器携带一对同前缀 Cookie（名字是随机串，末位分别为 `O` 和 `P`），其中 `O` 的值首位为 `6`。
- 直接以命令行请求教务首页会返回 **412 Precondition Failed**，响应体是一段带随机 `<meta>` 和 `$_ts` 种子的混淆脚本。
- 以上是动态防护（瑞数一类）的「412 挑战 + jsvm 生成后缀 + Cookie 校验」组合，与 [JWXT_API.md](JWXT_API.md) 中「路径已经去除防护参数」的记录互相印证。

结论：**这批后缀参数不是业务参数，无法离线复算或硬编码**，只能在真实浏览器页面上下文里请求时由页面脚本自动附加。任何自动化集成都必须走「真浏览器 + 页面内 `fetch`」的模式。

## 盘点方法

2026-09-23 用 Edge 经 Reqable 代理访问 `/h5/`，依次执行：打开首页 → 选择通勤车 → 查看次日班次 → 进入预约确认页 → 查看我的预约。全程只读，未提交任何预约。落盘前已删除 Cookie、防护参数值、工号、姓名和班次人数快照。
