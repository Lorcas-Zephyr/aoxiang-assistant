package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;

import java.util.Arrays;
import java.util.List;
import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.junit.Assert.assertEquals;

public class ExamStorageTest {
    @Test
    public void mergeRowsReplacesOnlyTargetSemesterAndDeduplicatesIncomingRows() throws Exception {
        ScheduleModels.Exam priorFall = new ScheduleModels.Exam(
                "旧考试", "期末", "2026-01-05", "09:00", "11:00", "A101", "01", "fall");
        ScheduleModels.Exam otherSemester = new ScheduleModels.Exam(
                "保留考试", "期中", "2026-04-05", "09:00", "11:00", "B202", "02", "spring");
        JSONObject currentRow = new JSONObject()
                .put("name", "新考试")
                .put("type", "期末")
                .put("date", "2026-01-12")
                .put("startTime", "14:00")
                .put("endTime", "16:00")
                .put("location", "C303")
                .put("seat", "03");
        JSONArray incoming = new JSONArray().put(currentRow).put(new JSONObject(currentRow.toString()));

        List<ScheduleModels.Exam> result = ExamStorage.mergeRows(
                Arrays.asList(priorFall, otherSemester), incoming, "fall");

        assertEquals(2, result.size());
        assertEquals("spring", result.get(0).semesterId);
        assertEquals("新考试", result.get(1).name);
        assertEquals("fall", result.get(1).semesterId);
    }

    @Test
    public void finishedExamDetectionKeepsUpcomingAndHidesEndedExams() {
        ScheduleModels.Exam yesterday = exam("2026-11-23", "23:59");
        ScheduleModels.Exam earlierToday = exam("2026-11-24", "09:00");
        ScheduleModels.Exam laterToday = exam("2026-11-24", "18:00");
        ScheduleModels.Exam tomorrow = exam("2026-11-25", "09:00");
        LocalDateTime now = LocalDateTime.parse("2026-11-24T12:00:00");

        org.junit.Assert.assertTrue(ExamStorage.isFinished(yesterday, now));
        org.junit.Assert.assertTrue(ExamStorage.isFinished(earlierToday, now));
        org.junit.Assert.assertFalse(ExamStorage.isFinished(laterToday, now));
        org.junit.Assert.assertFalse(ExamStorage.isFinished(tomorrow, now));
    }

    @Test
    public void examSectionRangeIncludesEveryActuallyIntersectedSection() {
        ScheduleModels.Semester semester = new ScheduleModels.Semester(
                "s", "测试学期", "2026-08-31", "2026-12-31", 17, 3,
                java.util.Arrays.asList(
                        new ScheduleModels.SectionTime("08:30", "09:15"),
                        new ScheduleModels.SectionTime("09:25", "10:10"),
                        new ScheduleModels.SectionTime("10:30", "11:15")));
        ScheduleModels.Exam exam = new ScheduleModels.Exam("阶段考试", "期中",
                "2026-09-01", "09:00", "10:40", "长安校区", "", "fall");

        assertEquals(java.util.Arrays.asList(1, 2, 3),
                ExamStorage.examSections(semester, exam, LocalDate.parse(exam.date)));
    }

    private ScheduleModels.Exam exam(String date, String endTime) {
        return new ScheduleModels.Exam("期末考试", "期末", date,
                "08:00", endTime, "教西A101", "01", "fall");
    }
}
