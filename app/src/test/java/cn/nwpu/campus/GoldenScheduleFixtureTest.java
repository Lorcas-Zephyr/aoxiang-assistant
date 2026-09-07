package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public class GoldenScheduleFixtureTest {
    @Test public void emptyScheduleFixturePreservesTheExplicitSemesterEnd() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson("golden/v1/schedule-empty/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson("golden/v1/schedule-empty/expected.json");

        JSONObject payload = PortalApiParsers.schedulePayload(
                input.getJSONObject("semester"), input.getJSONObject("printData"));

        assertEquals(expected.getInt("courseCount"), payload.getJSONArray("courses").length());
        assertEquals(expected.getString("semesterEndDate"),
                payload.getJSONArray("semesters").getJSONObject(0).getString("endDate"));
    }

    @Test public void mixedRepeatFixtureKeepsARepeatRulePerWeekPart() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson("golden/v1/schedule-mixed-repeat/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson("golden/v1/schedule-mixed-repeat/expected.json");

        List<ScheduleModels.TimeSlot> actual = ScheduleImport.parseScheduleText(
                input.getString("scheduleText"));
        JSONArray expectedSlots = expected.getJSONArray("slots");

        assertEquals(expectedSlots.length(), actual.size());
        for (int i = 0; i < actual.size(); i++) {
            assertSlot(expectedSlots.getJSONObject(i), actual.get(i));
        }
    }

    @Test public void nonContiguousWeekFixtureDoesNotInventIntermediateWeeks() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson("golden/v1/schedule-non-contiguous/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson("golden/v1/schedule-non-contiguous/expected.json");

        List<ScheduleModels.TimeSlot> actual = ScheduleImport.parseScheduleText(
                input.getString("scheduleText"));
        JSONArray expectedSlots = expected.getJSONArray("slots");

        assertEquals(expectedSlots.length(), actual.size());
        for (int i = 0; i < actual.size(); i++) {
            assertSlot(expectedSlots.getJSONObject(i), actual.get(i));
        }
    }

    @Test public void friendshipSummerFixtureUsesSummerSectionTimes() throws Exception {
        assertFriendshipFixture("schedule-friendship-summer");
    }

    @Test public void friendshipWinterFixtureUsesWinterSectionTimes() throws Exception {
        assertFriendshipFixture("schedule-friendship-winter");
    }

    @Test public void multipleTeachersAndLocationsStayOnTheirOwnMeetings() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson(
                "golden/v1/schedule-teachers-locations/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson(
                "golden/v1/schedule-teachers-locations/expected.json");
        JSONArray source = input.getJSONArray("courses");
        List<ScheduleImport.RawCourse> raw = new ArrayList<>();
        for (int i = 0; i < source.length(); i++) {
            JSONObject item = source.getJSONObject(i);
            ScheduleImport.RawCourse course = new ScheduleImport.RawCourse();
            course.name = item.getString("name");
            course.code = item.getString("code");
            course.dataSemester = item.getString("dataSemester");
            course.teacher = item.getString("teacher");
            course.location = item.getString("location");
            course.scheduleText = item.getString("scheduleText");
            raw.add(course);
        }

        List<ScheduleModels.Course> actual = ScheduleImport.convertToCourses(
                raw, input.getString("semesterId"), input.getString("targetDataSemester"));
        ScheduleModels.Course course = actual.get(0);

        assertEquals(expected.getInt("courseCount"), actual.size());
        assertEquals(expected.getString("teacher"), course.teacher);
        assertEquals(expected.getString("location"), course.location);
        assertEquals(expected.getInt("slotCount"), course.timeSlots.size());
        for (int i = 0; i < course.timeSlots.size(); i++) {
            assertEquals(expected.getJSONArray("slotTeachers").getString(i),
                    course.timeSlots.get(i).teacher);
            assertEquals(expected.getJSONArray("slotLocations").getString(i),
                    course.timeSlots.get(i).location);
        }
    }

    @Test public void onlineScheduleFixtureIsFilteredBeforeExport() throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson(
                "golden/v1/schedule-online-filter/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson(
                "golden/v1/schedule-online-filter/expected.json");

        JSONObject payload = PortalApiParsers.schedulePayload(
                input.getJSONObject("semester"), input.getJSONObject("printData"));

        JSONArray courses = payload.getJSONArray("courses");
        assertEquals(expected.getInt("courseCount"), courses.length());
        assertEquals(expected.getJSONArray("courseNames").getString(0),
                courses.getJSONObject(0).getString("name"));
    }

    private static void assertFriendshipFixture(String name) throws Exception {
        JSONObject input = GoldenFixtureSupport.readJson("golden/v1/" + name + "/input.json");
        JSONObject expected = GoldenFixtureSupport.readJson("golden/v1/" + name + "/expected.json");
        JSONObject semesterJson = input.getJSONObject("semester");
        ScheduleModels.Semester semester = ScheduleModels.Semester.from(semesterJson);
        JSONObject slotJson = input.getJSONObject("slot");
        List<Integer> sections = new ArrayList<>();
        JSONArray sectionArray = slotJson.getJSONArray("classSections");
        for (int i = 0; i < sectionArray.length(); i++) sections.add(sectionArray.getInt(i));
        ScheduleModels.TimeSlot slot = new ScheduleModels.TimeSlot(
                slotJson.getString("weekRange"),
                ScheduleModels.RepeatRule.fromStoredValue(slotJson.getString("repeatRule")),
                slotJson.getInt("dayOfWeek"), sections, null, slotJson.getString("location"));

        String actual = ScheduleUtils.formatMeetingTime(semester, slot, null,
                LocalDate.parse(input.getString("date")));

        assertEquals(expected.getString("meetingTime"), actual);
    }

    private static void assertSlot(JSONObject expected, ScheduleModels.TimeSlot actual)
            throws Exception {
        assertEquals(expected.getString("weekRange"), actual.weekRange);
        assertEquals(ScheduleModels.RepeatRule.fromStoredValue(
                expected.getString("repeatRule")), actual.repeatRule);
        assertEquals(expected.getInt("dayOfWeek"), actual.dayOfWeek);
        assertEquals(expected.getJSONArray("classSections").toString(),
                new JSONArray(actual.classSections).toString());
    }
}
