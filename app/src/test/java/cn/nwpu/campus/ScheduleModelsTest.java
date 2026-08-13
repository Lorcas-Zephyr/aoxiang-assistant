package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

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

    private static void assertTime(List<ScheduleModels.SectionTime> times, int index, String start, String end) {
        assertEquals(start, times.get(index).start);
        assertEquals(end, times.get(index).end);
    }
}
