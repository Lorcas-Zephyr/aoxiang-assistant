package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

public class PortalApiParsersTest {
    @Test public void mapsPublishedGradesAndPortraitGpa() throws Exception {
        JSONObject grade = new JSONObject()
                .put("published", true)
                .put("course", new JSONObject().put("nameZh", "软件工程").put("credits", 3.0))
                .put("gp", 4.0)
                .put("gaGrade", "95")
                .put("gradeDetail", "期末");
        JSONObject response = new JSONObject().put("semesterId2studentGrades",
                new JSONObject().put("362", new JSONArray().put(grade)));

        JSONArray rows = PortalApiParsers.gradeRows(new JSONArray().put(response));
        double gpa = PortalApiParsers.gpa(new JSONObject().put("stdGpaRankDto",
                new JSONObject().put("gpa", 3.763)));

        assertEquals(1, rows.length());
        assertEquals("软件工程", rows.getJSONArray(0).getString(0));
        assertEquals(95.0, rows.getJSONArray(0).getDouble(3), 0.001);
        assertEquals(3.763, gpa, 0.001);
    }

    @Test public void readsGpaFromWrappedStringFieldAndCleansGradeDetailHtml() throws Exception {
        double gpa = PortalApiParsers.gpa(new JSONObject().put("data",
                new JSONObject().put("cumulative_gpa", "3.76")));
        GradeRecord record = GradeRecord.from(new JSONObject()
                .put("course", "数据库")
                .put("credits", 3)
                .put("point", 4.0)
                .put("score", 95)
                .put("detail", "&lt;span&gt;期末成绩:95&lt;/span&gt;\\n&lt;span&gt;平时成绩:95&lt;/span&gt;"));

        assertEquals(3.76, gpa, 0.001);
        assertEquals("期末成绩:95 平时成绩:95", record.detail);
    }

    @Test public void mapsScheduleMeetingLocationTeachersAndDisjointWeeks() throws Exception {
        JSONObject activity = new JSONObject()
                .put("courseName", "大学英语")
                .put("courseCode", "U10M11001.01")
                .put("credits", 2.0)
                .put("weekday", 1)
                .put("startUnit", 1)
                .put("endUnit", 2)
                .put("weekIndexes", new JSONArray().put(2).put(3).put(11))
                .put("campus", "长安校区")
                .put("building", "教西")
                .put("room", "B3-101")
                .put("teachers", new JSONArray().put("李彩香").put("赵海霞"));
        JSONObject printData = new JSONObject().put("studentTableVm",
                new JSONObject().put("activities", new JSONArray().put(activity)));
        JSONObject semester = new JSONObject().put("id", 362).put("nameZh", "2026-2027秋")
                .put("startDate", "2026-08-31").put("endDate", "2027-01-17");

        JSONObject payload = PortalApiParsers.schedulePayload(semester, printData);
        JSONObject course = payload.getJSONArray("courses").getJSONObject(0);

        assertEquals("2~3,11周 星期一 1-2节", course.getString("scheduleText"));
        assertEquals("长安校区 教西 B3-101", course.getString("location"));
        assertEquals("李彩香、赵海霞", course.getString("teacher"));
        assertEquals("2026-11-09",
                payload.getJSONArray("semesters").getJSONObject(0).getString("endDate"));
    }

    @Test public void preservesExplicitlyEmptyScheduleForAtLeastTwoWeeks() throws Exception {
        JSONObject semester = new JSONObject().put("id", 361).put("nameZh", "2025-2026夏")
                .put("startDate", "2026-07-06").put("endDate", "2026-07-19");

        JSONObject payload = PortalApiParsers.schedulePayload(semester,
                new JSONObject().put("studentTableVm",
                        new JSONObject().put("activities", new JSONArray())));

        assertEquals(0, payload.getJSONArray("courses").length());
        assertEquals("2026-07-19",
                payload.getJSONArray("semesters").getJSONObject(0).getString("endDate"));
    }

    @Test public void readsElectricityBalanceFromApiResponse() throws Exception {
        JSONObject response = new JSONObject().put("map", new JSONObject().put("showData",
                new JSONObject().put("当前剩余电量", "18.52")));

        double balance = PortalApiParsers.electricityBalance(response);

        assertEquals(18.52, balance, 0.001);
        assertTrue(balance >= 0.0);
    }
}
