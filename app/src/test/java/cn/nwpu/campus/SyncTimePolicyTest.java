package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.time.ZoneId;
import java.time.ZonedDateTime;

import org.junit.Test;

public class SyncTimePolicyTest {
    private static final ZoneId CHINA = ZoneId.of("Asia/Shanghai");

    @Test public void electricitySettlementRunsFromMidnightUntilOne() {
        assertTrue(SyncTimePolicy.isElectricitySettlementTime(at(0, 0), CHINA));
        assertTrue(SyncTimePolicy.isElectricitySettlementTime(at(0, 59), CHINA));
        assertFalse(SyncTimePolicy.isElectricitySettlementTime(at(1, 0), CHINA));
        assertFalse(SyncTimePolicy.isElectricitySettlementTime(at(23, 59), CHINA));
    }

    @Test public void electricityDueDuringSettlementMovesToOne() {
        long now = at(23, 50);
        long dueAt = ZonedDateTime.of(2026, 8, 17, 0, 30, 0, 0, CHINA).toInstant().toEpochMilli();
        long expected = ZonedDateTime.of(2026, 8, 17, 1, 0, 0, 0, CHINA).toInstant().toEpochMilli();

        assertEquals(expected, SyncTimePolicy.deferElectricityDueAt(dueAt, now, CHINA));
    }

    @Test public void overdueElectricityUpdateRunsImmediatelyAfterSettlement() {
        long dueAt = at(0, 10);
        long now = at(2, 0);

        assertEquals(dueAt, SyncTimePolicy.deferElectricityDueAt(dueAt, now, CHINA));
    }

    private static long at(int hour, int minute) {
        return ZonedDateTime.of(2026, 8, 16, hour, minute, 0, 0, CHINA).toInstant().toEpochMilli();
    }
}
