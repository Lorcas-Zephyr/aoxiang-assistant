package cn.nwpu.campus;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.temporal.ChronoUnit;

/** Maps a clock time to the same section-height axis used by the timetable grid. */
final class ScheduleTimeLayout {
    private ScheduleTimeLayout() {}

    static float offsetPx(ScheduleModels.Semester semester, LocalDate date, String location,
                          LocalTime time, float sectionHeightPx) {
        if (semester == null || time == null || sectionHeightPx <= 0f) return 0f;
        for (int section = 1; section <= semester.sectionCount; section++) {
            ScheduleModels.SectionTime sectionTime = ScheduleModels.sectionTimeFor(
                    semester, location, date, section);
            if (sectionTime == null) continue;
            LocalTime start = parse(sectionTime.start);
            LocalTime end = parse(sectionTime.end);
            if (start == null || end == null || !end.isAfter(start)) continue;

            float top = (section - 1) * sectionHeightPx;
            float bottom = section * sectionHeightPx;
            if (!time.isAfter(start)) return top;
            if (time.isBefore(end)) {
                long totalNanos = ChronoUnit.NANOS.between(start, end);
                long elapsedNanos = ChronoUnit.NANOS.between(start, time);
                float fraction = totalNanos <= 0L ? 0f : (float) elapsedNanos / totalNanos;
                return top + Math.max(0f, Math.min(1f, fraction)) * sectionHeightPx;
            }
            if (time.equals(end)) return bottom;
        }
        return semester.sectionCount * sectionHeightPx;
    }

    private static LocalTime parse(String value) {
        try {
            String cleaned = value == null ? "" : value.trim();
            if (cleaned.length() >= 8) cleaned = cleaned.substring(0, 5);
            return cleaned.isEmpty() ? null : LocalTime.parse(cleaned);
        } catch (Exception ignored) {
            return null;
        }
    }
}
