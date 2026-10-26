package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * hq-bus.nwpu.edu.cn H5 接口的纯解析层。
 *
 * 全部输入都是页面内 fetch 拿到的原始 JSON，不依赖 Android 类型，便于单元测试。
 * 接口细节见 docs/HQ_BUS_API.md。
 */
final class BusApiParsers {
    private BusApiParsers() {}

    /** 响应统一包装 {"isSuccess":bool,"data":...,"IsOpenDialog":bool}。 */
    static boolean isSuccess(JSONObject response) {
        return response != null && response.optBoolean("isSuccess", false);
    }

    /** /api/GetRouteByType 的 data 段；失败返回空列表。 */
    static List<BusModels.Route> routes(JSONObject response) {
        List<BusModels.Route> out = new ArrayList<>();
        JSONObject data = data(response);
        JSONArray items = data == null ? null : data.optJSONArray("filteredBusRoutes");
        if (items == null) return out;
        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.optJSONObject(i);
            if (item == null) continue;
            BusModels.Route route = new BusModels.Route();
            route.objId = text(item, "Objid", "objId", "ObjId");
            route.type = text(item, "Type", "type");
            route.name = text(item, "Name", "name");
            route.startStation = text(item, "StartStation", "startStation");
            route.endStation = text(item, "EndStation", "endStation");
            route.studentCharge = text(item, "StudentCharge", "studentCharge");
            route.staffCharge = text(item, "TeacherStaffCharge", "teacherStaffCharge");
            if (!route.objId.isEmpty() || !route.name.isEmpty()) out.add(route);
        }
        return out;
    }

    /** 通勤车可提前预约天数 (reservationDays.TQYYXZTS)。缺失时返回 0。 */
    static int reserveDays(JSONObject response) {
        JSONObject data = data(response);
        JSONObject days = data == null ? null : data.optJSONObject("reservationDays");
        if (days == null) return 0;
        return positiveInt(days.opt("TQYYXZTS"));
    }

    /**
     * /api/GetReserveInfoList 的 data 段：某日某线路的全部班次。
     *
     * 字段含义（已用两次采集交叉验证）：
     * yyrs=已预约人数，kyyrs=该班次总名额，余位 = kyyrs - yyrs；
     * sfkyy 是服务端给出的“现在能否预约”，优先于本地推算。
     */
    static List<BusModels.Trip> trips(JSONObject response, String isoDate, BusModels.Route route) {
        List<BusModels.Trip> out = new ArrayList<>();
        JSONArray items = array(response);
        if (items == null) return out;
        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.optJSONObject(i);
            if (item == null) continue;
            BusModels.Trip trip = new BusModels.Trip();
            trip.date = isoDate == null ? "" : isoDate;
            trip.routeId = route == null ? "" : route.objId;
            trip.routeName = route == null ? "" : route.name;
            trip.objId = text(item, "objId", "Objid");
            trip.departTime = text(item, "fcsj", "FCSJ");
            trip.booked = positiveInt(item.opt("yyrs"));
            trip.capacity = positiveInt(item.opt("kyyrs"));
            trip.remaining = trip.capacity > 0 ? Math.max(0, trip.capacity - trip.booked) : -1;
            trip.open = item.optBoolean("sfkyy", false);
            trip.deadline = text(item, "yyjzxx", "YYJZXX");
            trip.hint = text(item, "tsxx", "TSXX");
            trip.note = text(item, "bcms", "BCMS");
            if (!trip.objId.isEmpty() || !trip.departTime.isEmpty()) out.add(trip);
        }
        return out;
    }

    /** /api/GetMyAppointment 的 data.list：我的预约。 */
    static List<BusModels.Reservation> reservations(JSONObject response) {
        List<BusModels.Reservation> out = new ArrayList<>();
        JSONObject data = data(response);
        if (data == null) return out;
        JSONArray list = data.optJSONArray("list");
        if (list == null) list = data.optJSONArray("List");
        if (list == null) return out;
        for (int i = 0; i < list.length(); i++) {
            JSONObject item = list.optJSONObject(i);
            if (item == null) continue;
            BusModels.Reservation reservation = new BusModels.Reservation();
            reservation.orderNo = text(item, "yydh", "YYDH", "orderNo", "OrderNo", "yybh");
            reservation.status = text(item, "yyzt", "YYZT", "status", "Status");
            reservation.reviewer = text(item, "shr", "SHR", "reviewer");
            reservation.routeName = text(item, "xlmc", "XLMC", "routeName", "lineName", "Name", "name");
            reservation.date = isoDate(text(item, "ccrq", "CCRQ", "yyrq", "YYRQ", "date", "Date"));
            reservation.departTime = isoTime(text(item, "fcsj", "FCSJ", "sjd", "SJD", "time", "Time"));
            reservation.driverPhone = text(item, "yktyfddh", "YKTYFDDH", "driverPhone");
            reservation.fee = text(item, "fy", "FY", "fee");
            reservation.noticeUrl = text(item, "yyxz", "YYXZ", "noticeUrl");
            reservation.summary = summarize(item, reservation);
            if (!reservation.key().trim().isEmpty()) out.add(reservation);
        }
        return out;
    }

    private static JSONObject data(JSONObject response) {
        return response == null ? null : response.optJSONObject("data");
    }

    /** data 有时是数组（班次列表），有时是对象，这里统一取数组。 */
    private static JSONArray array(JSONObject response) {
        if (response == null || response.isNull("data")) return null;
        Object raw = response.opt("data");
        if (raw instanceof JSONArray) return (JSONArray) raw;
        return null;
    }

    /**
     * 预约接口的日期/时刻格式未知，统一归一化：
     * 能解析的换成 yyyy-MM-dd / HH:mm，解析不了就原样保留。
     */
    private static String isoDate(String raw) {
        java.time.LocalDate date = BusModels.parseDate(raw);
        return date == null ? raw : date.toString();
    }

    private static String isoTime(String raw) {
        java.time.LocalTime time = BusModels.parseTime(raw);
        return time == null ? raw : String.format(java.util.Locale.ROOT, "%02d:%02d",
                time.getHour(), time.getMinute());
    }

    private static String text(JSONObject item, String... keys) {
        for (String key : keys) {
            if (item.isNull(key)) continue;
            Object raw = item.opt(key);
            if (raw == null) continue;
            String value = String.valueOf(raw).trim();
            if (!value.isEmpty() && !"null".equals(value)) return value;
        }
        return "";
    }

    private static int positiveInt(Object raw) {
        if (raw == null || raw == JSONObject.NULL) return 0;
        try {
            String value = String.valueOf(raw).replaceAll("[^0-9]", "");
            return value.isEmpty() ? 0 : Integer.parseInt(value);
        } catch (Exception ignored) {
            return 0;
        }
    }

    /**
     * 预约条目字段名未经确认，用「全部标量字段」拼一个兜底摘要，
     * 保证界面上永远不会出现一条只有标题的空记录。
     */
    private static String summarize(JSONObject item, BusModels.Reservation reservation) {
        Map<String, String> pairs = new LinkedHashMap<>();
        JSONArray names = item.names();
        if (names != null) {
            for (int i = 0; i < names.length() && pairs.size() < 12; i++) {
                String key = names.optString(i);
                if (item.isNull(key)) continue;
                Object raw = item.opt(key);
                if (raw instanceof JSONObject || raw instanceof JSONArray) continue;
                String value = String.valueOf(raw).trim();
                if (value.isEmpty() || "null".equals(value)) continue;
                if (value.equals(reservation.orderNo) || value.equals(reservation.noticeUrl)) continue;
                pairs.put(key, value);
            }
        }
        List<String> parts = new ArrayList<>();
        for (Map.Entry<String, String> entry : pairs.entrySet()) {
            parts.add(entry.getKey() + " " + entry.getValue());
        }
        return String.join(" · ", parts);
    }
}
