package cn.nwpu.campus;

import org.junit.Test;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.Arrays;

import static org.junit.Assert.assertEquals;

public class ScheduleTimeLayoutTest {
    @Test
    public void mapsMidSectionTimesProportionally() {
        ScheduleModels.Semester semester = new ScheduleModels.Semester(
                "s", "测试学期", "2026-08-31", "2026-12-31", 17, 2,
                Arrays.asList(new ScheduleModels.SectionTime("08:30", "09:15"),
                        new ScheduleModels.SectionTime("09:25", "10:10")));

        assertEquals(29.333f, ScheduleTimeLayout.offsetPx(semester,
                LocalDate.parse("2026-09-01"), null, LocalTime.parse("08:52"), 60f), 0.01f);
        assertEquals(60f, ScheduleTimeLayout.offsetPx(semester,
                LocalDate.parse("2026-09-01"), null, LocalTime.parse("09:20"), 60f), 0.01f);
        assertEquals(100f, ScheduleTimeLayout.offsetPx(semester,
                LocalDate.parse("2026-09-01"), null, LocalTime.parse("09:55"), 60f), 0.01f);
    }
}
