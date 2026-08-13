package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.util.Arrays;
import java.util.List;

public class ScheduleImportTest {
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

    private static ScheduleImport.RawCourse rawCourse(String name, String code, String schedule, String semester) {
        ScheduleImport.RawCourse course = new ScheduleImport.RawCourse();
        course.name = name;
        course.code = code;
        course.scheduleText = schedule;
        course.dataSemester = semester;
        return course;
    }
}
