package cn.nwpu.campus;

import java.time.Instant;
import java.time.ZoneId;
import java.time.ZonedDateTime;

final class SyncTimePolicy {
    static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");

    private SyncTimePolicy() {}

    static boolean isElectricitySettlementTime(long epochMillis) {
        return isElectricitySettlementTime(epochMillis, BUSINESS_ZONE);
    }

    static boolean isElectricitySettlementTime(long epochMillis, ZoneId zone) {
        return ZonedDateTime.ofInstant(Instant.ofEpochMilli(epochMillis), zone).getHour() == 0;
    }

    static long deferElectricityDueAt(long dueAt, long now) {
        return deferElectricityDueAt(dueAt, now, BUSINESS_ZONE);
    }

    static long deferElectricityDueAt(long dueAt, long now, ZoneId zone) {
        long candidate = Math.max(dueAt, now);
        ZonedDateTime local = ZonedDateTime.ofInstant(Instant.ofEpochMilli(candidate), zone);
        if (local.getHour() != 0) return dueAt;
        return local.withHour(1).withMinute(0).withSecond(0).withNano(0).toInstant().toEpochMilli();
    }
}
