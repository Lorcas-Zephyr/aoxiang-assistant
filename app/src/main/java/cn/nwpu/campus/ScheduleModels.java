package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.DecimalFormat;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

public final class ScheduleModels {
    private ScheduleModels() {}

    public static final String DEFAULT_THEME_COLOR = "#2F80ED";
    public static final List<String> PRESET_COLORS = Arrays.asList(
            "#E53935",
            "#1E88E5",
            "#43A047",
            "#FB8C00",
            "#8E24AA",
            "#00ACC1",
            "#FFB300",
            "#3949AB"
    );

    public enum RepeatRule {
        ALL("", "全部"),
        ODD("仅单周", "单周"),
        EVEN("仅双周", "双周");

        public final String storedValue;
        public final String label;

        RepeatRule(String storedValue, String label) {
            this.storedValue = storedValue;
            this.label = label;
        }

        public static RepeatRule fromStoredValue(String value) {
            for (RepeatRule rule : values()) {
                if (rule.storedValue.equals(value)) {
                    return rule;
                }
            }
            return ALL;
        }
    }

    public enum AssessmentMethod {
        EXAM("考试"),
        INSPECTION("考察"),
        PNP("PnP");

        public final String label;

        AssessmentMethod(String label) {
            this.label = label;
        }

        public static AssessmentMethod fromLabel(String value) {
            for (AssessmentMethod method : values()) {
                if (method.label.equals(value)) {
                    return method;
                }
            }
            return null;
        }
    }

    public static class SectionTime {
        public String start;
        public String end;

        public SectionTime(String start, String end) {
            this.start = start;
            this.end = end;
        }

        public JSONObject json() {
            JSONObject o = new JSONObject();
            try {
                o.put("start", start);
                o.put("end", end);
            } catch (Exception ignored) {}
            return o;
        }

        public static SectionTime from(JSONObject o) {
            return new SectionTime(o.optString("start", "08:00"), o.optString("end", "08:45"));
        }
    }

    public static class TimeSlot {
        public String weekRange;
        public RepeatRule repeatRule;
        public int dayOfWeek;
        public List<Integer> classSections;

        public TimeSlot(String weekRange, RepeatRule repeatRule, int dayOfWeek, List<Integer> classSections) {
            this.weekRange = weekRange;
            this.repeatRule = repeatRule == null ? RepeatRule.ALL : repeatRule;
            this.dayOfWeek = dayOfWeek;
            this.classSections = new ArrayList<>(classSections);
        }

        public JSONObject json() {
            JSONObject o = new JSONObject();
            try {
                o.put("weekRange", weekRange);
                o.put("repeatRule", repeatRule.storedValue);
                o.put("dayOfWeek", dayOfWeek);
                JSONArray sections = new JSONArray();
                for (Integer value : classSections) {
                    sections.put(value);
                }
                o.put("classSections", sections);
            } catch (Exception ignored) {}
            return o;
        }

        public static TimeSlot from(JSONObject o) {
            List<Integer> sections = new ArrayList<>();
            JSONArray array = o.optJSONArray("classSections");
            if (array != null) {
                for (int i = 0; i < array.length(); i++) {
                    sections.add(array.optInt(i, 1));
                }
            }
            if (sections.isEmpty()) {
                sections.add(1);
            }
            return new TimeSlot(
                    o.optString("weekRange", "1-16"),
                    RepeatRule.fromStoredValue(o.optString("repeatRule", "")),
                    o.optInt("dayOfWeek", 1),
                    sections
            );
        }
    }

    public static class Semester {
        public String id;
        public String name;
        public String startDate;
        public String endDate;
        public int weekCount;
        public int sectionCount;
        public List<SectionTime> sectionTimes;

        public Semester(String id, String name, String startDate, String endDate, int weekCount, int sectionCount, List<SectionTime> sectionTimes) {
            this.id = id;
            this.name = name;
            this.startDate = startDate;
            this.endDate = endDate;
            this.weekCount = weekCount;
            this.sectionCount = sectionCount;
            this.sectionTimes = new ArrayList<>(sectionTimes);
        }

        public JSONObject json() {
            JSONObject o = new JSONObject();
            try {
                o.put("id", id);
                o.put("name", name);
                o.put("startDate", startDate);
                o.put("endDate", endDate);
                o.put("weekCount", weekCount);
                o.put("sectionCount", sectionCount);
                JSONArray times = new JSONArray();
                for (SectionTime time : sectionTimes) {
                    times.put(time.json());
                }
                o.put("sectionTimes", times);
            } catch (Exception ignored) {}
            return o;
        }

        public static Semester from(JSONObject o) {
            List<SectionTime> sectionTimes = new ArrayList<>();
            JSONArray array = o.optJSONArray("sectionTimes");
            if (array != null) {
                for (int i = 0; i < array.length(); i++) {
                    JSONObject item = array.optJSONObject(i);
                    if (item != null) {
                        sectionTimes.add(SectionTime.from(item));
                    }
                }
            }
            int sectionCount = Math.max(1, o.optInt("sectionCount", 13));
            if (sectionTimes.isEmpty()) {
                sectionTimes = buildDefaultSectionTimes(sectionCount);
            }
            return new Semester(
                    o.optString("id", "semester-default"),
                    o.optString("name", "学期"),
                    o.optString("startDate", LocalDate.now().toString()),
                    o.optString("endDate", LocalDate.now().plusWeeks(19).toString()),
                    Math.max(1, o.optInt("weekCount", 20)),
                    sectionCount,
                    sectionTimes
            );
        }
    }

    public static class Course {
        public String id;
        public String name;
        public String semesterId;
        public List<TimeSlot> timeSlots;
        public String code;
        public String location;
        public Double credits;
        public String teacher;
        public AssessmentMethod assessmentMethod;
        public String notes;
        public String color;

        public Course(String id, String name, String semesterId, List<TimeSlot> timeSlots) {
            this.id = id;
            this.name = name;
            this.semesterId = semesterId;
            this.timeSlots = new ArrayList<>(timeSlots);
        }

        public JSONObject json() {
            JSONObject o = new JSONObject();
            try {
                o.put("id", id);
                o.put("name", name);
                o.put("semesterId", semesterId);
                JSONArray slots = new JSONArray();
                for (TimeSlot slot : timeSlots) {
                    slots.put(slot.json());
                }
                o.put("timeSlots", slots);
                o.put("code", code == null ? JSONObject.NULL : code);
                o.put("location", location == null ? JSONObject.NULL : location);
                o.put("credits", credits == null ? JSONObject.NULL : credits);
                o.put("teacher", teacher == null ? JSONObject.NULL : teacher);
                o.put("assessmentMethod", assessmentMethod == null ? JSONObject.NULL : assessmentMethod.label);
                o.put("notes", notes == null ? JSONObject.NULL : notes);
                o.put("color", color == null ? JSONObject.NULL : color);
            } catch (Exception ignored) {}
            return o;
        }

        public static Course from(JSONObject o) {
            List<TimeSlot> slots = new ArrayList<>();
            JSONArray array = o.optJSONArray("timeSlots");
            if (array != null) {
                for (int i = 0; i < array.length(); i++) {
                    JSONObject item = array.optJSONObject(i);
                    if (item != null) {
                        slots.add(TimeSlot.from(item));
                    }
                }
            }
            if (slots.isEmpty()) {
                slots.add(new TimeSlot("1-16", RepeatRule.ALL, 1, Arrays.asList(1, 2)));
            }
            Course course = new Course(
                    o.optString("id", "course-" + System.currentTimeMillis()),
                    o.optString("name", "课程"),
                    o.optString("semesterId", ""),
                    slots
            );
            course.code = o.isNull("code") ? null : o.optString("code", null);
            course.location = o.isNull("location") ? null : o.optString("location", null);
            course.credits = o.isNull("credits") ? null : o.optDouble("credits");
            course.teacher = o.isNull("teacher") ? null : o.optString("teacher", null);
            course.assessmentMethod = o.isNull("assessmentMethod") ? null : AssessmentMethod.fromLabel(o.optString("assessmentMethod", ""));
            course.notes = o.isNull("notes") ? null : o.optString("notes", null);
            course.color = o.isNull("color") ? null : o.optString("color", null);
            return course;
        }

        public int startSection() {
            int start = Integer.MAX_VALUE;
            for (TimeSlot slot : timeSlots) {
                for (Integer section : slot.classSections) {
                    start = Math.min(start, section);
                }
            }
            return start == Integer.MAX_VALUE ? 1 : start;
        }

        public int endSection() {
            int end = 1;
            for (TimeSlot slot : timeSlots) {
                for (Integer section : slot.classSections) {
                    end = Math.max(end, section);
                }
            }
            return end;
        }

        public String creditsText() {
            return credits == null ? "--" : new DecimalFormat("0.##").format(credits);
        }
    }

    public static List<SectionTime> buildDefaultSectionTimes(int count) {
        List<SectionTime> times = new ArrayList<>();
        String[][] standard = {
                {"08:30", "09:15"},
                {"09:25", "10:10"},
                {"10:30", "11:15"},
                {"11:25", "12:10"},
                {"12:20", "13:05"},
                {"13:05", "13:50"},
                {"14:00", "14:45"},
                {"14:55", "15:40"},
                {"16:00", "16:45"},
                {"16:55", "17:40"},
                {"19:00", "19:45"},
                {"19:55", "20:40"},
                {"20:40", "21:25"}
        };
        int standardCount = Math.min(Math.max(0, count), standard.length);
        for (int i = 0; i < standardCount; i++) {
            times.add(new SectionTime(standard[i][0], standard[i][1]));
        }
        int cursor = 21 * 60 + 35;
        for (int i = standard.length; i < count; i++) {
            times.add(new SectionTime(formatMinutes(cursor), formatMinutes(cursor + 45)));
            cursor += 55;
        }
        return times;
    }

    public static Semester createDefaultSemester() {
        int year = LocalDate.now().getYear();
        return new Semester(
                "semester-default",
                "假期",
                year + "-01-01",
                year + "-12-31",
                52,
                13,
                buildDefaultSectionTimes(13)
        );
    }

    private static String formatMinutes(int totalMinutes) {
        int hour = totalMinutes / 60;
        int minute = totalMinutes % 60;
        return String.format(Locale.US, "%02d:%02d", hour, minute);
    }
}
