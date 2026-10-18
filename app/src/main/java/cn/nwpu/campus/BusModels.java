package cn.nwpu.campus;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;

/**
 * 校车（后勤通勤车 hq-bus.nwpu.edu.cn）的数据模型。
 *
 * 与课表/成绩一样，这里只保存“能直接展示给用户”的字段，原始响应由
 * {@link BusApiParsers} 转换后再落盘，避免把接口结构泄漏到 UI 层。
 */
public final class BusModels {
    public static final DateTimeFormatter API_DATE = DateTimeFormatter.ofPattern("yyyy/M/d");
    public static final DateTimeFormatter CLOCK = DateTimeFormatter.ofPattern("H:mm");
    public static final DateTimeFormatter DISPLAY_DATE = DateTimeFormatter.ofPattern("M月d日");

    private BusModels() {}

    public static String formatDate(LocalDate date) {
        return date == null ? "" : date.toString();
    }

    /** yyyy/M/d、yyyy-MM-dd、yyyy/M/d HH:mm 都能解析，失败返回 null。 */
    public static LocalDate parseDate(String raw) {
        String value = raw == null ? "" : raw.trim();
        if (value.isEmpty()) return null;
        int space = value.indexOf(' ');
        if (space > 0) value = value.substring(0, space);
        try {
            return LocalDate.parse(value, DateTimeFormatter.ISO_LOCAL_DATE);
        } catch (DateTimeParseException ignored) {}
        try {
            return LocalDate.parse(value, API_DATE);
        } catch (DateTimeParseException ignored) {}
        return null;
    }

    /** HH:mm / H:mm / HH:mm:ss 都能解析，失败返回 null。 */
    public static LocalTime parseTime(String raw) {
        String value = raw == null ? "" : raw.trim();
        if (value.isEmpty()) return null;
        if (value.length() > 5) value = value.substring(0, 5);
        try {
            return LocalTime.parse(value, CLOCK);
        } catch (DateTimeParseException ignored) {}
        return null;
    }

    public static String displayDate(String isoDate) {
        LocalDate date = parseDate(isoDate);
        if (date == null) return isoDate == null ? "" : isoDate;
        if (LocalDate.now().equals(date)) return "今天";
        if (LocalDate.now().plusDays(1).equals(date)) return "明天";
        return DISPLAY_DATE.format(date);
    }

    /** 一条班车线路，来自 /api/GetRouteByType。 */
    public static final class Route {
        public String objId = "";
        public String type = "";
        public String name = "";
        public String startStation = "";
        public String endStation = "";
        public String studentCharge = "";
        public String staffCharge = "";

        public String chargeText() {
            List<String> parts = new ArrayList<>();
            if (!studentCharge.isEmpty()) parts.add("学生 " + studentCharge + " 元");
            if (!staffCharge.isEmpty()) parts.add("教职工 " + staffCharge + " 元");
            return String.join(" · ", parts);
        }

        public String stationText() {
            if (startStation.isEmpty() && endStation.isEmpty()) return "";
            return startStation + " → " + endStation;
        }
    }

    /** 某个日期、某条线路下的一个班次，来自 /api/GetReserveInfoList。 */
    public static final class Trip {
        public String date = "";
        public String routeId = "";
        public String routeName = "";
        public String objId = "";
        public String departTime = "";
        public int capacity;
        public int booked;
        public int remaining;
        public boolean open;
        public String deadline = "";
        public String hint = "";
        public String note = "";

        /** 发车时刻；日期或时间不可解析时返回 null。 */
        public LocalDateTime departureAt() {
            LocalDate day = parseDate(date);
            LocalTime clock = parseTime(departTime);
            if (day == null || clock == null) return null;
            return LocalDateTime.of(day, clock);
        }

        /** 是否为“可预约但快满”的班次。 */
        public boolean scarce() {
            return open && remaining >= 0 && remaining <= 5;
        }

        public String seatText() {
            if (!open) return "已截止";
            if (remaining < 0) return "余位未知";
            return "余 " + remaining + " / " + capacity;
        }
    }

    /**
     * 一条“我的预约”。
     *
     * 该接口在本次盘点时列表为空，服务端字段名未能确认，因此这里对常见字段名做
     * 多候选提取，并保留 {@link #summary} 作为兜底展示文本。
     */
    public static final class Reservation {
        public String orderNo = "";
        public String status = "";
        public String reviewer = "";
        public String routeName = "";
        public String date = "";
        public String departTime = "";
        public String driverPhone = "";
        public String fee = "";
        public String noticeUrl = "";
        public String summary = "";

        public LocalDateTime departureAt() {
            LocalDate day = parseDate(date);
            LocalTime clock = parseTime(departTime);
            if (day == null || clock == null) return null;
            return LocalDateTime.of(day, clock);
        }

        public boolean pending() {
            return status.contains("待") || status.contains("未");
        }

        public boolean rejected() {
            return status.contains("驳回") || status.contains("取消") || status.contains("失效");
        }

        public String title() {
            if (!routeName.isEmpty()) return routeName;
            return orderNo.isEmpty() ? "校车预约" : "预约 " + orderNo;
        }

        public String whenText() {
            List<String> parts = new ArrayList<>();
            if (!date.isEmpty()) parts.add(displayDate(date));
            if (!departTime.isEmpty()) parts.add(departTime);
            return String.join(" ", parts);
        }

        /** 用于去重与提醒：预约号优先，其次 线路+日期+时刻。 */
        public String key() {
            if (!orderNo.isEmpty()) return orderNo;
            return routeName + "|" + date + "|" + departTime;
        }
    }

    /** 一次采集得到的完整快照。 */
    public static final class Snapshot {
        public long updatedAt;
        /** 通勤车可提前预约天数（reservationDays.TQYYXZTS）。 */
        public int reserveDays;
        public List<Route> routes = new ArrayList<>();
        public List<Trip> trips = new ArrayList<>();
        public List<Reservation> reservations = new ArrayList<>();

        public boolean isEmpty() {
            return reservations.isEmpty() && trips.isEmpty();
        }

        /** 最近一条尚未出发的预约，用于首页与提醒。 */
        public Reservation nextReservation() {
            Reservation best = null;
            LocalDateTime now = LocalDateTime.now();
            for (Reservation reservation : reservations) {
                if (reservation.rejected()) continue;
                LocalDateTime at = reservation.departureAt();
                if (at == null || at.isBefore(now)) continue;
                if (best == null || best.departureAt() == null || at.isBefore(best.departureAt())) {
                    best = reservation;
                }
            }
            if (best != null) return best;
            return reservations.isEmpty() ? null : reservations.get(0);
        }

        /** 下一个可预约班次，用于「最近一班」提示。 */
        public Trip nextOpenTrip() {
            Trip best = null;
            LocalDateTime now = LocalDateTime.now();
            for (Trip trip : trips) {
                if (!trip.open) continue;
                LocalDateTime at = trip.departureAt();
                if (at == null || at.isBefore(now)) continue;
                if (best == null || best.departureAt() == null || at.isBefore(best.departureAt())) {
                    best = trip;
                }
            }
            return best;
        }

        public List<Trip> tripsForDate(String isoDate) {
            List<Trip> out = new ArrayList<>();
            for (Trip trip : trips) {
                if (trip.date.equals(isoDate)) out.add(trip);
            }
            return out;
        }
    }
}
