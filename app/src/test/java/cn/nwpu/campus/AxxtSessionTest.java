package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.time.LocalDate;
import java.util.Arrays;

public class AxxtSessionTest {
    @Test public void mapsFriendshipScheduleApiMeeting() throws Exception {
        JSONObject source = new JSONObject()
                .put("course_name", "形势与政策（4）")
                .put("course_number", "U44G11016")
                .put("course_begin", "2026-09-19 14:30:00")
                .put("course_end", "2026-09-19 18:30:00")
                .put("teacher", new JSONObject().put("name", "测试教师"))
                .put("area", "友谊校区 研究生西馆 西馆XA401");

        JSONObject course = AxxtSession.coursePayload(source, 3,
                "2026-2027学年秋季", null);

        assertEquals("形势与政策（4）", course.getString("name"));
        assertEquals("3周 星期6 7-10节", course.getString("scheduleText"));
        assertEquals("测试教师", course.getString("teacher"));
        assertEquals("友谊校区 研究生西馆 西馆XA401", course.getString("location"));
    }

    @Test public void readsActualWeeksAndSemesterBounds() throws Exception {
        JSONArray weeks = new JSONArray()
                .put(new JSONObject().put("week", 1)
                        .put("start_time", "2026-08-31 00:00:00")
                        .put("end_time", "2026-09-06 23:59:59"))
                .put(new JSONObject().put("week", 3)
                        .put("start_time", "2026-09-14 00:00:00")
                        .put("end_time", "2026-09-20 23:59:59"));
        JSONObject response = new JSONObject().put("data",
                new JSONObject().put("week_list", weeks));

        AxxtSession.SemesterWeeks parsed = AxxtSession.parseSemesterWeeks(response);

        assertEquals(Arrays.asList(1, 3), parsed.weeks);
        assertEquals(LocalDate.of(2026, 8, 31), parsed.startDate);
        assertEquals(LocalDate.of(2026, 9, 20), parsed.endDate);
    }

    @Test public void readsSectionsFromOfficialApiField() {
        assertEquals(9, AxxtSession.sectionRangeFromValue("9-10节")[0]);
        assertEquals(10, AxxtSession.sectionRangeFromValue("9-10节")[1]);
        assertEquals(1, AxxtSession.sectionRangeFromValue("[1, 2, 3, 4]")[0]);
        assertEquals(4, AxxtSession.sectionRangeFromValue("[1, 2, 3, 4]")[1]);
    }
}
