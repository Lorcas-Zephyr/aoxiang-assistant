package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

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

    @Test public void meetingsForWeekDayKeepsEveryMeetingScheduledOnTheSameDay() {
        ScheduleModels.TimeSlot morning = new ScheduleModels.TimeSlot(
                "1-16", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(1, 2));
        ScheduleModels.TimeSlot afternoon = new ScheduleModels.TimeSlot(
                "1-16", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(7, 8));
        ScheduleModels.TimeSlot oddWeeksOnly = new ScheduleModels.TimeSlot(
                "1-16", ScheduleModels.RepeatRule.ODD, 1, Arrays.asList(11, 12));
        ScheduleModels.TimeSlot wednesday = new ScheduleModels.TimeSlot(
                "1-16", ScheduleModels.RepeatRule.ALL, 3, Arrays.asList(3, 4));
        ScheduleModels.TimeSlot laterWeeks = new ScheduleModels.TimeSlot(
                "5-8", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(9, 10));
        ScheduleModels.Course course = new ScheduleModels.Course(
                "course", "高等数学", "semester",
                Arrays.asList(morning, afternoon, oddWeeksOnly, wednesday, laterWeeks));

        List<ScheduleModels.TimeSlot> monday = ScheduleUtils.meetingsForWeekDay(course, 1, 1);
        assertEquals(3, monday.size());
        assertEquals(Arrays.asList(1, 2), monday.get(0).classSections);
        assertEquals(Arrays.asList(7, 8), monday.get(1).classSections);
        assertEquals(Arrays.asList(11, 12), monday.get(2).classSections);
        assertEquals(2, ScheduleUtils.meetingsForWeekDay(course, 2, 1).size());
        assertEquals(Collections.singletonList(wednesday), ScheduleUtils.meetingsForWeekDay(course, 1, 3));
        List<ScheduleModels.TimeSlot> fifthWeek = ScheduleUtils.meetingsForWeekDay(course, 5, 1);
        assertEquals(4, fifthWeek.size());
        assertEquals(Arrays.asList(1, 2), fifthWeek.get(0).classSections);
        assertEquals(Arrays.asList(7, 8), fifthWeek.get(1).classSections);
        assertEquals(Arrays.asList(9, 10), fifthWeek.get(2).classSections);
        assertEquals(Arrays.asList(11, 12), fifthWeek.get(3).classSections);
        assertEquals(Collections.emptyList(), ScheduleUtils.meetingsForWeekDay(course, 1, 5));
    }

    @Test public void meetingsForWeekDaySkipsSlotsWithoutClassSections() {
        ScheduleModels.TimeSlot empty = new ScheduleModels.TimeSlot(
                "1-16", ScheduleModels.RepeatRule.ALL, 1, Collections.emptyList());
        ScheduleModels.TimeSlot valid = new ScheduleModels.TimeSlot(
                "1-16", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(3, 4));
        ScheduleModels.Course course = new ScheduleModels.Course(
                "course", "测试课程", "semester", Arrays.asList(empty, valid));

        assertEquals(Collections.singletonList(valid), ScheduleUtils.meetingsForWeekDay(course, 1, 1));
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
