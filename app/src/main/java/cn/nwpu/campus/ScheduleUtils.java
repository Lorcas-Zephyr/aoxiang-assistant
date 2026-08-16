package cn.nwpu.campus;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public final class ScheduleUtils {
    private ScheduleUtils() {}

    public static List<Integer> parseWeeks(String range) {
        List<Integer> weeks = new ArrayList<>();
        if (range == null) return weeks;
        for (String raw : range.split(",")) {
            String part = raw.trim();
            if (part.isEmpty()) continue;
            String[] bounds = part.split("-", 2);
            try {
                int start = Integer.parseInt(bounds[0].trim());
                int end = bounds.length == 1 ? start : Integer.parseInt(bounds[1].trim());
                for (int week = start; week <= end; week++) {
                    if (week > 0 && week <= 53) weeks.add(week);
                }
            } catch (NumberFormatException ignored) {}
        }
        return weeks;
    }

    public static boolean isWeekInRange(int week, String range) {
        return parseWeeks(range).contains(week);
    }

    public static boolean matchesRepeatRule(int week, ScheduleModels.RepeatRule rule) {
        if (rule == ScheduleModels.RepeatRule.ODD) return week % 2 == 1;
        if (rule == ScheduleModels.RepeatRule.EVEN) return week % 2 == 0;
        return true;
    }

    public static int weekNumberForDate(LocalDate date, ScheduleModels.Semester semester) {
        try {
            LocalDate start = mondayOnOrBefore(LocalDate.parse(semester.startDate));
            long diff = ChronoUnit.DAYS.between(start, date);
            return diff < 0 ? 0 : (int) (diff / 7) + 1;
        } catch (Exception ignored) {
            return 1;
        }
    }

    public static LocalDate dateForWeekDay(LocalDate semesterStart, int week, int dayOfWeek) {
        int safeWeek = Math.max(1, week);
        int safeDay = Math.max(1, Math.min(7, dayOfWeek));
        return semesterStart.plusDays((long) (safeWeek - 1) * 7 + safeDay - 1);
    }

    public static int weekCountForRange(LocalDate start, LocalDate end) {
        if (start == null || end == null || end.isBefore(start)) return 1;
        return (int) (ChronoUnit.DAYS.between(start, end) / 7) + 1;
    }

    /** Returns the Monday on the selected date's week, including the date itself. */
    public static LocalDate mondayOnOrBefore(LocalDate date) {
        if (date == null) return null;
        return date.minusDays(date.getDayOfWeek().getValue() - 1L);
    }

    public static boolean isTimeSlotConflict(ScheduleModels.TimeSlot first, ScheduleModels.TimeSlot second) {
        if (first.dayOfWeek != second.dayOfWeek) return false;
        Set<Integer> firstWeeks = effectiveWeeks(first);
        Set<Integer> secondWeeks = effectiveWeeks(second);
        for (Integer week : firstWeeks) {
            if (!secondWeeks.contains(week)) continue;
            for (Integer section : first.classSections) {
                if (second.classSections.contains(section)) return true;
            }
        }
        return false;
    }

    public static String findConflictDescription(ScheduleModels.Course candidate, List<ScheduleModels.Course> existing, String excludeId) {
        for (ScheduleModels.Course course : existing) {
            if (course.id.equals(excludeId) || !course.semesterId.equals(candidate.semesterId)) continue;
            for (ScheduleModels.TimeSlot first : candidate.timeSlots) {
                for (ScheduleModels.TimeSlot second : course.timeSlots) {
                    if (isTimeSlotConflict(first, second)) return "与「" + course.name + "」时间冲突";
                }
            }
        }
        return null;
    }

    public static String formatSections(List<Integer> sections) {
        if (sections == null || sections.isEmpty()) return "";
        List<Integer> sorted = new ArrayList<>(sections);
        Collections.sort(sorted);
        List<String> parts = new ArrayList<>();
        int start = sorted.get(0);
        int previous = start;
        for (int i = 1; i < sorted.size(); i++) {
            int current = sorted.get(i);
            if (current == previous + 1) {
                previous = current;
            } else {
                parts.add(sectionRange(start, previous));
                start = previous = current;
            }
        }
        parts.add(sectionRange(start, previous));
        return join(parts, "、");
    }

    public static String formatSlot(ScheduleModels.TimeSlot slot) {
        String[] days = {"", "周一", "周二", "周三", "周四", "周五", "周六", "周日"};
        String repeat = slot.repeatRule == ScheduleModels.RepeatRule.ALL ? "" : "(" + slot.repeatRule.label + ")";
        return slot.weekRange + "周" + repeat + " " + days[Math.max(1, Math.min(7, slot.dayOfWeek))] + " " + formatSections(slot.classSections);
    }

    public static String formatCourseTime(ScheduleModels.Course course) {
        List<String> values = new ArrayList<>();
        for (ScheduleModels.TimeSlot slot : course.timeSlots) values.add(formatSlot(slot));
        return join(values, "\n");
    }

    public static String meetingTimeRange(ScheduleModels.Semester semester,
                                          ScheduleModels.TimeSlot slot,
                                          String fallbackLocation,
                                          LocalDate date) {
        if (slot == null || slot.classSections == null || slot.classSections.isEmpty()) return "";
        int first = Collections.min(slot.classSections);
        int last = Collections.max(slot.classSections);
        String location = slot.location == null ? fallbackLocation : slot.location;
        ScheduleModels.SectionTime firstTime = ScheduleModels.sectionTimeFor(
                semester, location, date, first);
        ScheduleModels.SectionTime lastTime = ScheduleModels.sectionTimeFor(
                semester, location, date, last);
        if (firstTime == null || lastTime == null) return "";
        return firstTime.start + "-" + lastTime.end;
    }

    public static String formatMeetingTime(ScheduleModels.Semester semester,
                                           ScheduleModels.TimeSlot slot,
                                           String fallbackLocation,
                                           LocalDate date) {
        if (slot == null) return "";
        String sections = formatSections(slot.classSections);
        String range = meetingTimeRange(semester, slot, fallbackLocation, date);
        return range.isEmpty() ? sections : sections + " · " + range;
    }

    public static boolean allMeetingsUseFriendshipCampus(List<ScheduleModels.Course> courses,
                                                          int week) {
        boolean foundMeeting = false;
        for (ScheduleModels.Course course : courses) {
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                if (!isWeekInRange(week, slot.weekRange)
                        || !matchesRepeatRule(week, slot.repeatRule)
                        || slot.classSections == null || slot.classSections.isEmpty()) continue;
                foundMeeting = true;
                String location = slot.location == null ? course.location : slot.location;
                if (!ScheduleModels.isFriendshipCampus(location)) return false;
            }
        }
        return foundMeeting;
    }

    public static String join(List<String> values, String separator) {
        StringBuilder result = new StringBuilder();
        for (String value : values) {
            if (result.length() > 0) result.append(separator);
            result.append(value);
        }
        return result.toString();
    }

    private static Set<Integer> effectiveWeeks(ScheduleModels.TimeSlot slot) {
        Set<Integer> result = new HashSet<>();
        for (Integer week : parseWeeks(slot.weekRange)) {
            if (matchesRepeatRule(week, slot.repeatRule)) result.add(week);
        }
        return result;
    }

    private static String sectionRange(int start, int end) {
        return start == end ? "第" + start + "节" : "第" + start + "-" + end + "节";
    }
}
