package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.time.LocalDate;
import java.util.List;

public class ScheduleModelsTest {
    @Test public void usesCampusSectionTimes() {
        List<ScheduleModels.SectionTime> times = ScheduleModels.buildDefaultSectionTimes(13);

        assertEquals(13, times.size());
        assertTime(times, 0, "08:30", "09:15");
        assertTime(times, 4, "12:20", "13:05");
        assertTime(times, 5, "13:05", "13:50");
        assertTime(times, 8, "16:00", "16:45");
        assertTime(times, 10, "19:00", "19:45");
        assertTime(times, 12, "20:40", "21:25");
    }

    @Test public void usesFriendshipSummerSectionTimesFromMayThroughSeptember() {
        List<ScheduleModels.SectionTime> may = ScheduleModels.buildFriendshipSectionTimes(
                13, LocalDate.of(2026, 5, 1));
        List<ScheduleModels.SectionTime> september = ScheduleModels.buildFriendshipSectionTimes(
                13, LocalDate.of(2026, 9, 30));

        assertTime(may, 0, "08:00", "08:50");
        assertTime(may, 6, "14:30", "15:20");
        assertTime(may, 12, "21:30", "22:20");
        assertTime(september, 9, "17:40", "18:30");
    }

    @Test public void usesFriendshipWinterSectionTimesFromOctoberThroughApril() {
        List<ScheduleModels.SectionTime> october = ScheduleModels.buildFriendshipSectionTimes(
                13, LocalDate.of(2026, 10, 1));
        List<ScheduleModels.SectionTime> april = ScheduleModels.buildFriendshipSectionTimes(
                13, LocalDate.of(2027, 4, 30));

        assertTime(october, 6, "14:00", "14:50");
        assertTime(october, 10, "19:00", "19:50");
        assertTime(april, 12, "21:00", "21:50");
    }

    @Test public void recognizesFriendshipCampusByTheFriendshipCharacters() {
        assertEquals(true, ScheduleModels.isFriendshipCampus("友谊校区 公字楼"));
        assertEquals(true, ScheduleModels.isFriendshipCampus("西工大友谊教学区"));
        assertEquals(false, ScheduleModels.isFriendshipCampus("长安校区 教西B座"));
    }

    private static void assertTime(List<ScheduleModels.SectionTime> times, int index, String start, String end) {
        assertEquals(start, times.get(index).start);
        assertEquals(end, times.get(index).end);
    }
}
