package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.time.LocalDate;
import java.util.Arrays;
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

    @Test public void preservesUnknownRepeatRuleWhenARecordIsReadAndWritten() throws Exception {
        JSONObject source = new JSONObject()
                .put("weekRange", "1-17")
                .put("repeatRule", "future-rule")
                .put("dayOfWeek", 1)
                .put("classSections", new JSONArray().put(1))
                .put("futureSlotField", "keep-me");

        ScheduleModels.TimeSlot slot = ScheduleModels.TimeSlot.from(source);

        assertEquals("future-rule", slot.json().getString("repeatRule"));
        assertEquals("keep-me", slot.json().getString("futureSlotField"));
    }

    @Test public void knownRepeatRuleCanBeChangedAfterReading() throws Exception {
        JSONObject source = new JSONObject()
                .put("weekRange", "1-17")
                .put("repeatRule", "仅单周")
                .put("dayOfWeek", 1)
                .put("classSections", new JSONArray().put(1));

        ScheduleModels.TimeSlot slot = ScheduleModels.TimeSlot.from(source);
        slot.repeatRule = ScheduleModels.RepeatRule.EVEN;

        assertEquals("仅双周", slot.json().getString("repeatRule"));
    }

    @Test public void preservesUnknownAssessmentMethodWhenARecordIsReadAndWritten() throws Exception {
        JSONObject source = new JSONObject()
                .put("id", "course-stable")
                .put("name", "课程")
                .put("semesterId", "semester-stable")
                .put("assessmentMethod", "future-method")
                .put("timeSlots", new JSONArray().put(new JSONObject()
                        .put("weekRange", "1-17")
                        .put("repeatRule", "")
                        .put("dayOfWeek", 1)
                        .put("classSections", new JSONArray().put(1))));

        ScheduleModels.Course course = ScheduleModels.Course.from(source);

        assertEquals("future-method", course.json().getString("assessmentMethod"));
    }

    @Test public void rejectsSemesterWithoutIdInsteadOfInventingOne() throws Exception {
        try {
            ScheduleModels.Semester.from(new JSONObject().put("name", "学期"));
            fail("Expected missing semester id to be rejected");
        } catch (IllegalArgumentException error) {
            assertTrue(error.getMessage().contains("Semester id"));
        }
    }

    @Test public void rejectsBlankSemesterIdInsteadOfInventingOne() throws Exception {
        try {
            ScheduleModels.Semester.from(new JSONObject().put("id", " \t"));
            fail("Expected blank semester id to be rejected");
        } catch (IllegalArgumentException error) {
            assertTrue(error.getMessage().contains("Semester id"));
        }
    }

    @Test public void rejectsCourseWithoutIdInsteadOfInventingOne() throws Exception {
        try {
            ScheduleModels.Course.from(new JSONObject().put("semesterId", "semester-stable"));
            fail("Expected missing course id to be rejected");
        } catch (IllegalArgumentException error) {
            assertTrue(error.getMessage().contains("Course id"));
        }
    }

    @Test public void rejectsCourseWithoutSemesterId() throws Exception {
        try {
            ScheduleModels.Course.from(new JSONObject().put("id", "course-stable"));
            fail("Expected missing course semesterId to be rejected");
        } catch (IllegalArgumentException error) {
            assertTrue(error.getMessage().contains("Course semesterId"));
        }
    }

    @Test public void rejectsBlankCourseSemesterId() throws Exception {
        try {
            ScheduleModels.Course.from(new JSONObject()
                    .put("id", "course-stable")
                    .put("semesterId", ""));
            fail("Expected blank course semesterId to be rejected");
        } catch (IllegalArgumentException error) {
            assertTrue(error.getMessage().contains("Course semesterId"));
        }
    }

    private static void assertTime(List<ScheduleModels.SectionTime> times, int index, String start, String end) {
        assertEquals(start, times.get(index).start);
        assertEquals(end, times.get(index).end);
    }
}
