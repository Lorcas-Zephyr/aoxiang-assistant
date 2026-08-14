package cn.nwpu.campus;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

final class ScheduleWidgetData {
    static final class Item {
        final String name;
        final String location;
        final String color;
        final String sections;
        final String start;
        final String end;
        final int startSection;

        Item(String name, String location, String color, String sections,
             String start, String end, int startSection) {
            this.name = name;
            this.location = location;
            this.color = color;
            this.sections = sections;
            this.start = start;
            this.end = end;
            this.startSection = startSection;
        }

        String timeText() {
            String range = sections;
            if (start != null && !start.isEmpty() && end != null && !end.isEmpty()) {
                range += "  " + start + "-" + end;
            }
            return range;
        }
    }

    private ScheduleWidgetData() {}

    static DayData forDate(java.util.Date ignored, boolean upcomingOnly) {
        return forDate(LocalDate.now(), upcomingOnly);
    }

    static DayData forDate(LocalDate date, boolean upcomingOnly) {
        android.content.Context context = ScheduleWidgetContext.get();
        if (context == null) return new DayData(new ArrayList<>(), "假期");
        android.content.SharedPreferences store = context.getSharedPreferences("campus_private", android.content.Context.MODE_PRIVATE);
        List<ScheduleModels.Semester> semesters = ScheduleStorage.loadSemesters(store);
        List<ScheduleModels.Course> courses = ScheduleStorage.loadCourses(store);
        ScheduleModels.Semester semester = semesterForDate(date, semesters);
        if (semester == null) return new DayData(new ArrayList<>(), "假期");

        int week = ScheduleUtils.weekNumberForDate(date, semester);
        int day = date.getDayOfWeek().getValue();
        List<Item> items = new ArrayList<>();
        for (ScheduleModels.Course course : courses) {
            if (!semester.id.equals(course.semesterId)) continue;
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                if (slot.dayOfWeek != day || !ScheduleUtils.isWeekInRange(week, slot.weekRange)
                        || !ScheduleUtils.matchesRepeatRule(week, slot.repeatRule) || slot.classSections.isEmpty()) continue;
                List<Integer> sections = new ArrayList<>(slot.classSections);
                Collections.sort(sections);
                int first = sections.get(0);
                int last = sections.get(sections.size() - 1);
                String start = sectionTime(semester, first, true);
                String end = sectionTime(semester, last, false);
                items.add(new Item(course.name, safe(slot.location == null ? course.location : slot.location), safe(course.color),
                        ScheduleUtils.formatSections(sections), start, end, first));
            }
        }
        items.sort(Comparator.comparingInt(item -> item.startSection));
        if (upcomingOnly) {
            int now = java.time.LocalTime.now().getHour() * 60 + java.time.LocalTime.now().getMinute();
            items.removeIf(item -> toMinutes(item.end) <= now);
        }
        return new DayData(items, semester.name);
    }

    static ScheduleModels.Semester semesterForDate(LocalDate date, List<ScheduleModels.Semester> semesters) {
        for (ScheduleModels.Semester semester : semesters) {
            try {
                LocalDate start = ScheduleUtils.mondayOnOrBefore(LocalDate.parse(semester.startDate));
                LocalDate end = start.plusWeeks(Math.max(1, semester.weekCount)).minusDays(1);
                if (!date.isBefore(start) && !date.isAfter(end)) return semester;
            } catch (Exception ignored) {
                // Ignore malformed semester entries and continue looking for a valid one.
            }
        }
        return null;
    }

    static String sectionTime(ScheduleModels.Semester semester, int section, boolean start) {
        if (section < 1 || section > semester.sectionTimes.size()) return "";
        ScheduleModels.SectionTime time = semester.sectionTimes.get(section - 1);
        return start ? time.start : time.end;
    }

    static int toMinutes(String value) {
        try {
            String[] parts = value.split(":");
            return Integer.parseInt(parts[0]) * 60 + Integer.parseInt(parts[1]);
        } catch (Exception ignored) {
            return Integer.MAX_VALUE;
        }
    }

    static String safe(String value) {
        return value == null ? "" : value;
    }

    static final class DayData {
        final List<Item> items;
        final String semesterName;

        DayData(List<Item> items, String semesterName) {
            this.items = items;
            this.semesterName = semesterName;
        }
    }

}
