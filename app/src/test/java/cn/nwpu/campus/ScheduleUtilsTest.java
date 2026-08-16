package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collections;

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

    @Test public void weekCountUsesSemesterStartAndEndDates() {
        assertEquals(16, ScheduleUtils.weekCountForRange(
                LocalDate.of(2026, 8, 31), LocalDate.of(2026, 12, 19)));
        assertEquals(17, ScheduleUtils.weekCountForRange(
                LocalDate.of(2026, 8, 31), LocalDate.of(2026, 12, 27)));
    }

    @Test public void formatsMeetingTimeForItsCampusAndDate() {
        ScheduleModels.Semester semester = new ScheduleModels.Semester(
                "test", "测试", "2026-08-31", "2026-12-31", 17, 13,
                ScheduleModels.buildDefaultSectionTimes(13));
        ScheduleModels.TimeSlot friendship = new ScheduleModels.TimeSlot(
                "1", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(7, 8),
                null, "友谊校区 公字楼");
        ScheduleModels.TimeSlot changan = new ScheduleModels.TimeSlot(
                "1", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(7, 8),
                null, "长安校区 教西B座");

        assertEquals("第7-8节 · 14:30-16:20", ScheduleUtils.formatMeetingTime(
                semester, friendship, null, LocalDate.of(2026, 9, 30)));
        assertEquals("第7-8节 · 14:00-15:50", ScheduleUtils.formatMeetingTime(
                semester, friendship, null, LocalDate.of(2026, 10, 1)));
        assertEquals("第7-8节 · 14:00-15:40", ScheduleUtils.formatMeetingTime(
                semester, changan, null, LocalDate.of(2026, 9, 30)));
    }

    @Test public void detectsWeeksContainingOnlyFriendshipCampusMeetings() {
        ScheduleModels.TimeSlot firstSlot = new ScheduleModels.TimeSlot(
                "1-2", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(1, 2),
                null, "友谊校区 公字楼");
        ScheduleModels.TimeSlot secondSlot = new ScheduleModels.TimeSlot(
                "1-2", ScheduleModels.RepeatRule.ALL, 3, Arrays.asList(3, 4),
                null, "西工大友谊教学区");
        ScheduleModels.Course first = new ScheduleModels.Course(
                "first", "课程一", "semester", Collections.singletonList(firstSlot));
        ScheduleModels.Course second = new ScheduleModels.Course(
                "second", "课程二", "semester", Collections.singletonList(secondSlot));

        assertEquals(true, ScheduleUtils.allMeetingsUseFriendshipCampus(
                Arrays.asList(first, second), 1));

        secondSlot.location = "长安校区 教西B座";
        assertEquals(false, ScheduleUtils.allMeetingsUseFriendshipCampus(
                Arrays.asList(first, second), 1));
        assertEquals(false, ScheduleUtils.allMeetingsUseFriendshipCampus(
                Arrays.asList(first, second), 3));
    }
}
