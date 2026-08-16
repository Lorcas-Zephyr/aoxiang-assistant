package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public class ScheduleImportTest {
    @Test public void importedSemesterDefaultsToSeventeenWeeks() {
        ScheduleImport.RawSemester raw = new ScheduleImport.RawSemester("测试学期", null);

        ScheduleModels.Semester semester = ScheduleImport.createImportedSemester(
                raw, Collections.emptyList());

        assertEquals(17, semester.weekCount);
    }

    @Test public void importedSemesterKeepsCoursesBeyondWeekSeventeen() {
        ScheduleModels.Course course = new ScheduleModels.Course(
                "course", "测试课程", "semester",
                Collections.singletonList(new ScheduleModels.TimeSlot(
                        "19", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(1, 2))));

        ScheduleModels.Semester semester = ScheduleImport.createImportedSemester(
                new ScheduleImport.RawSemester("测试学期", null), Collections.singletonList(course));

        assertEquals(19, semester.weekCount);
    }

    @Test public void importedSemesterUsesJwxtStartDate() {
        ScheduleModels.Semester semester = ScheduleImport.createImportedSemester(
                new ScheduleImport.RawSemester("2026-2027秋", "362", "2026-08-31", "2026-12-27"),
                Collections.emptyList());

        assertEquals("2026-08-31", semester.startDate);
        assertEquals("2026-12-27", semester.endDate);
    }

    @Test public void importedSemesterEndsOnTheLastScheduledCourse() {
        ScheduleModels.Course course = new ScheduleModels.Course(
                "course", "测试课程", "semester",
                Collections.singletonList(new ScheduleModels.TimeSlot(
                        "16", ScheduleModels.RepeatRule.ALL, 6, Arrays.asList(1, 2))));

        ScheduleModels.Semester semester = ScheduleImport.createImportedSemester(
                new ScheduleImport.RawSemester("2026-2027秋", "362", "2026-08-31", "2027-01-17"),
                Collections.singletonList(course));

        assertEquals(16, semester.weekCount);
        assertEquals("2026-12-19", semester.endDate);
    }

    @Test public void importedSemesterLastsAtLeastTwoWeeks() {
        ScheduleModels.Course course = new ScheduleModels.Course(
                "course", "测试课程", "semester",
                Collections.singletonList(new ScheduleModels.TimeSlot(
                        "1", ScheduleModels.RepeatRule.ALL, 1, Arrays.asList(1, 2))));

        ScheduleModels.Semester semester = ScheduleImport.createImportedSemester(
                new ScheduleImport.RawSemester("2026-2027秋", "362", "2026-08-31", null),
                Collections.singletonList(course));

        assertEquals(2, semester.weekCount);
        assertEquals("2026-09-13", semester.endDate);
    }

    @Test public void parsesJwxtWeekAndSectionText() {
        List<ScheduleModels.TimeSlot> slots = ScheduleImport.parseScheduleText(
                "1~4周 星期一 1-2节; 5~8周 星期一 1-2节; "
                        + "2~4，7~9周 星期三 7-8节");

        assertEquals(3, slots.size());
        assertEquals("1-8", slots.get(0).weekRange);
        assertEquals(1, slots.get(0).dayOfWeek);
        assertEquals(Arrays.asList(1, 2), slots.get(0).classSections);
        assertEquals("2-4", slots.get(1).weekRange);
        assertEquals("7-9", slots.get(2).weekRange);
    }

    @Test public void mergesTheSameCourseAcrossTimetableCells() {
        ScheduleImport.RawCourse monday = rawCourse("数学建模", "U14M21159.03",
                "13周 星期一 7-8节", "362");
        ScheduleImport.RawCourse sunday = rawCourse("数学建模", "U14M21159.03",
                "14周 星期日 7-8节", "362");

        List<ScheduleModels.Course> courses = ScheduleImport.convertToCourses(
                Arrays.asList(monday, sunday), "semester-id", "362");

        assertEquals(1, courses.size());
        assertEquals(2, courses.get(0).timeSlots.size());
        assertEquals("semester-id", courses.get(0).semesterId);
    }

    @Test public void mergesAndDeduplicatesTeachersAcrossTimetableCells() {
        ScheduleImport.RawCourse monday = rawCourse("软件工程", "U14M11143.01",
                "1-8周 星期一 1-2节", "362");
        monday.teacher = "张三、李四、学科基础";
        ScheduleImport.RawCourse friday = rawCourse("软件工程", "U14M11143.01",
                "1-8周 星期五 3-4节", "362");
        friday.teacher = "李四 / 王五";

        List<ScheduleModels.Course> courses = ScheduleImport.convertToCourses(
                Arrays.asList(monday, friday), "semester-id", "362");

        assertEquals(1, courses.size());
        assertEquals("张三、李四、王五", courses.get(0).teacher);
    }

    @Test public void keepsTeacherAndLocationOnEachScheduledMeeting() {
        ScheduleImport.RawCourse week14 = rawCourse("软件实验", "U14M11143.01",
                "14周 星期三 9-10节", "362");
        week14.teacher = "石玲娟";
        week14.location = "长安校区 实验大楼B110（软件实验室）";
        ScheduleImport.RawCourse week15 = rawCourse("软件实验", "U14M11143.01",
                "15周 星期三 9-10节", "362");
        week15.teacher = "郭佳";
        week15.location = "长安校区 实验大楼B110（软件实验室）";

        ScheduleModels.Course course = ScheduleImport.convertToCourses(
                Arrays.asList(week14, week15), "semester-id", "362").get(0);

        assertEquals(2, course.timeSlots.size());
        assertEquals("石玲娟", course.timeSlots.get(0).teacher);
        assertEquals("郭佳", course.timeSlots.get(1).teacher);
        assertEquals("长安校区 实验大楼B110（软件实验室）", course.timeSlots.get(0).location);
        assertEquals("石玲娟、郭佳", course.teacher);
        assertEquals("长安校区 实验大楼B110（软件实验室）", course.location);
    }

    @Test public void parsesDisjointWeeksInsideOnePairOfParentheses() {
        ScheduleImport.RawCourse courseRow = rawCourse("大学英语", "U10M11001.01",
                "2~3,11周 星期一 1-2节", "362");
        courseRow.teacher = "李彩香";
        courseRow.location = "长安校区 教西B3-101";

        ScheduleModels.Course course = ScheduleImport.convertToCourses(
                Arrays.asList(courseRow), "semester-id", "362").get(0);

        assertEquals(2, course.timeSlots.size());
        assertEquals("2-3", course.timeSlots.get(0).weekRange);
        assertEquals("11", course.timeSlots.get(1).weekRange);
        assertEquals("李彩香", course.timeSlots.get(0).teacher);
        assertEquals("李彩香", course.timeSlots.get(1).teacher);
    }

    private static ScheduleImport.RawCourse rawCourse(String name, String code, String schedule, String semester) {
        ScheduleImport.RawCourse course = new ScheduleImport.RawCourse();
        course.name = name;
        course.code = code;
        course.scheduleText = schedule;
        course.dataSemester = semester;
        return course;
    }
}
