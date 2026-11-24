package cn.nwpu.campus;

import org.junit.Test;

import java.time.LocalDate;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class ManualEventStoreTest {
    @Test
    public void betweenExpandsWeeklyEventsIntoEveryOccurrence() {
        ManualEvent weekly = new ManualEvent("event-1", "项目讨论",
                "2026-01-05", "10:00", "11:00");
        weekly.weekly = true;
        weekly.repeatWeeks = 4;
        weekly.note = "每周安排";
        weekly.color = "#123456";

        List<ManualEvent> occurrences = ManualEventStore.between(
                Collections.singletonList(weekly), LocalDate.parse("2026-01-05"),
                LocalDate.parse("2026-01-26"));

        assertEquals(4, occurrences.size());
        assertEquals("2026-01-05", occurrences.get(0).date);
        assertEquals("2026-01-26", occurrences.get(3).date);
        assertEquals("每周安排", occurrences.get(2).note);
        assertEquals("#123456", occurrences.get(2).color);
        assertFalse(occurrences.get(2).weekly);
        assertTrue(weekly.weekly);
    }

    @Test
    public void betweenReturnsEmptyForReversedRange() {
        ManualEvent event = new ManualEvent("event-1", "项目讨论",
                "2026-01-05", "10:00", "11:00");

        assertTrue(ManualEventStore.between(Collections.singletonList(event),
                LocalDate.parse("2026-01-06"), LocalDate.parse("2026-01-05")).isEmpty());
    }
}
