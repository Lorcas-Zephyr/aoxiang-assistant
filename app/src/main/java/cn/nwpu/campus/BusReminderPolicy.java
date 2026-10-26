package cn.nwpu.campus;

import java.time.Duration;
import java.time.LocalDateTime;

/**
 * 校车提醒的纯判定逻辑：何时该提醒、提醒一次之后如何不再重复。
 *
 * 不依赖 Android，便于单元测试；通知渠道与文案拼接在 MainActivity。
 */
final class BusReminderPolicy {
    /** 发车前多久开始提醒。 */
    static final long DEPARTURE_LEAD_MS = 30L * 60_000L;
    /** 余位低于该值视为「快满」。 */
    static final int LOW_SEAT_THRESHOLD = 5;

    private BusReminderPolicy() {}

    /** 出发时刻落在 [now, now+30min] 之间时应当提醒。 */
    static boolean shouldRemindDeparture(LocalDateTime departure, long now) {
        if (departure == null) return false;
        long at = departure.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli();
        return at >= now && at - now <= DEPARTURE_LEAD_MS;
    }

    /** 还有多少分钟发车；已过点返回负数。 */
    static long minutesUntil(LocalDateTime departure, long now) {
        if (departure == null) return Long.MIN_VALUE;
        long at = departure.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli();
        return Duration.ofMillis(at - now).toMinutes();
    }

    /** 发车提醒的去重键：同一条预约只提醒一次。 */
    static String departureKey(BusModels.Reservation reservation) {
        return "departure:" + reservation.key() + "|" + reservation.date + "|" + reservation.departTime;
    }

    /** 状态提醒的去重键：带上状态，状态再变会重新提醒。 */
    static String statusKey(BusModels.Reservation reservation) {
        return "status:" + reservation.key() + "|" + reservation.status;
    }

    /**
     * 状态是否值得提醒。
     *
     * 首次出现（previousStatus 为空）不提醒，避免刚打开应用就被历史预约刷屏。
     * 「待核验」本身也不提醒；只有变成审核结果或异常状态才通知。
     */
    static boolean shouldRemindStatus(String previousStatus, String currentStatus) {
        if (currentStatus == null || currentStatus.trim().isEmpty()) return false;
        if (previousStatus == null || previousStatus.trim().isEmpty()) return false;
        if (previousStatus.equals(currentStatus)) return false;
        return !currentStatus.contains("待核验") && !currentStatus.contains("待审核");
    }

    static String departureText(BusModels.Reservation reservation, long now) {
        long minutes = minutesUntil(reservation.departureAt(), now);
        String when = reservation.whenText();
        if (minutes <= 0) return when + " 的班车即将发车";
        if (minutes <= 1) return when + " 的班车 1 分钟后发车";
        return when + " 的班车 " + minutes + " 分钟后发车";
    }

    static String statusText(BusModels.Reservation reservation) {
        String title = reservation.title();
        String status = reservation.status.isEmpty() ? "状态已更新" : reservation.status;
        String when = reservation.whenText();
        return when.isEmpty() ? title + " · " + status : title + " · " + when + " · " + status;
    }

    /** 班次余位提示文案；不可预约或余位充足时返回空串。 */
    static String scarceSeatText(BusModels.Trip trip) {
        if (trip == null || !trip.open || trip.remaining < 0) return "";
        if (trip.remaining > LOW_SEAT_THRESHOLD) return "";
        return BusModels.displayDate(trip.date) + " " + trip.departTime + " 仅剩 " + trip.remaining + " 个余位";
    }
}
