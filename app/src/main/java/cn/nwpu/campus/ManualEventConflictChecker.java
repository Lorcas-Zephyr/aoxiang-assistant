package cn.nwpu.campus;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** 手动日程与已有日程、当前学期课程的时间冲突检查。 */
final class ManualEventConflictChecker {
    private final List<ManualEvent> events;
    private final List<ScheduleModels.Semester> semesters;
    private final List<ScheduleModels.Course> courses;
    private final String selectedSemesterId;

    ManualEventConflictChecker(List<ManualEvent> events, List<ScheduleModels.Semester> semesters,
                               List<ScheduleModels.Course> courses, String selectedSemesterId) {
        this.events = events;
        this.semesters = semesters;
        this.courses = courses;
        this.selectedSemesterId = selectedSemesterId;
    }

    String findConflict(ManualEvent candidate, String excludeId) {
        int start = minutesOfDay(candidate.startTime);
        int end = minutesOfDay(candidate.endTime);
        if (start < 0 || end <= start) return null;

        int occurrences = candidate.weekly ? Math.max(1, candidate.repeatWeeks) : 1;
        LocalDate firstDate = candidate.localDate();
        for (int week = 0; week < occurrences; week++) {
            LocalDate date = firstDate.plusWeeks(week);
            for (ManualEvent other : ManualEventStore.onDate(events, date)) {
                if (other == null) continue;
                if (excludeId != null && excludeId.equals(other.id)) continue;
                int otherStart = minutesOfDay(other.startTime);
                int otherEnd = minutesOfDay(other.endTime);
                if (otherStart >= 0 && otherEnd > otherStart
                        && start < otherEnd && end > otherStart) {
                    return "与日程「" + other.title + "」在 " + ManualEvent.formatDateLabel(date)
                            + " " + other.timeRange() + " 冲突";
                }
            }
            String courseConflict = findCourseConflict(date, start, end);
            if (courseConflict != null) return courseConflict;
        }
        return null;
    }

    private String findCourseConflict(LocalDate date, int candidateStart, int candidateEnd) {
        ScheduleModels.Semester semester = selectedSemester();
        if (semester == null) return null;
        int week = ScheduleUtils.weekNumberForDate(date, semester);
        if (week <= 0) return null;

        int day = date.getDayOfWeek().getValue();
        for (ScheduleModels.Course course : coursesForSemester(semester.id)) {
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                if (slot.dayOfWeek != day
                        || !ScheduleUtils.isWeekInRange(week, slot.weekRange)
                        || !ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)
                        || slot.classSections == null || slot.classSections.isEmpty()) {
                    continue;
                }
                int first = Collections.min(slot.classSections);
                int last = Collections.max(slot.classSections);
                if (first < 1 || last > semester.sectionCount) continue;

                int courseStart = sectionStartMinutes(semester, course, slot, date, first);
                int courseEnd = sectionEndMinutes(semester, course, slot, date, last);
                if (courseEnd <= courseStart) continue;
                if (candidateStart < courseEnd && candidateEnd > courseStart) {
                    return "与课程「" + course.name + "」在 " + ManualEvent.formatDateLabel(date)
                            + " " + formatMinutes(courseStart) + "–" + formatMinutes(courseEnd) + " 冲突";
                }
            }
        }
        return null;
    }

    private ScheduleModels.Semester selectedSemester() {
        for (ScheduleModels.Semester semester : semesters) {
            if (semester.id.equals(selectedSemesterId)) return semester;
        }
        return null;
    }

    private List<ScheduleModels.Course> coursesForSemester(String semesterId) {
        List<ScheduleModels.Course> result = new ArrayList<>();
        if (semesterId == null) return result;
        for (ScheduleModels.Course course : courses) {
            if (course != null && semesterId.equals(course.semesterId)) result.add(course);
        }
        return result;
    }

    private int sectionStartMinutes(ScheduleModels.Semester semester, ScheduleModels.Course course,
                                    ScheduleModels.TimeSlot slot, LocalDate date, int section) {
        String location = slot != null && slot.location != null
                ? slot.location : (course == null ? null : course.location);
        ScheduleModels.SectionTime time = ScheduleModels.sectionTimeFor(semester, location, date, section);
        if (time != null) {
            int value = minutesOfDay(time.start);
            if (value >= 0) return value;
        }
        return 8 * 60 + Math.max(0, section - 1) * 60;
    }

    private int sectionEndMinutes(ScheduleModels.Semester semester, ScheduleModels.Course course,
                                  ScheduleModels.TimeSlot slot, LocalDate date, int section) {
        String location = slot != null && slot.location != null
                ? slot.location : (course == null ? null : course.location);
        ScheduleModels.SectionTime time = ScheduleModels.sectionTimeFor(semester, location, date, section);
        if (time != null) {
            int value = minutesOfDay(time.end);
            if (value > 0) return value;
        }
        return sectionStartMinutes(semester, course, slot, date, section) + 45;
    }

    private int minutesOfDay(String value) {
        try {
            LocalTime time = LocalTime.parse(value);
            return time.getHour() * 60 + time.getMinute();
        } catch (Exception ignored) {
            return -1;
        }
    }

    private String formatMinutes(int value) {
        int safe = Math.max(0, value);
        return String.format(Locale.CHINA, "%02d:%02d", safe / 60, safe % 60);
    }
}
