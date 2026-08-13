package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import java.time.LocalDate;

import org.junit.Test;

public class ScheduleUtilsTest {
    @Test public void normalizesStartDateToMondayOnOrBefore() {
        assertEquals(LocalDate.of(2026, 8, 10),
                ScheduleUtils.mondayOnOrBefore(LocalDate.of(2026, 8, 13)));
        assertEquals(LocalDate.of(2026, 8, 10),
                ScheduleUtils.mondayOnOrBefore(LocalDate.of(2026, 8, 10)));
    }

    @Test public void weekNumberUsesNormalizedMondayStart() {
        ScheduleModels.Semester semester = new ScheduleModels.Semester(
                "test", "测试", "2026-08-13", "2026-12-31", 20, 13,
                ScheduleModels.buildDefaultSectionTimes(13));
        assertEquals(1, ScheduleUtils.weekNumberForDate(LocalDate.of(2026, 8, 13), semester));
        assertEquals(2, ScheduleUtils.weekNumberForDate(LocalDate.of(2026, 8, 17), semester));
    }
}
