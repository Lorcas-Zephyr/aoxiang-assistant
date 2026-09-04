package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;

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
    private static final String[][] FRIENDSHIP_SUMMER_SECTION_TIMES = {
            {"08:00", "08:50"},
            {"09:00", "09:50"},
            {"10:10", "11:00"},
            {"11:10", "12:00"},
            {"12:20", "13:05"},
            {"13:05", "13:50"},
            {"14:30", "15:20"},
            {"15:30", "16:20"},
            {"16:40", "17:30"},
            {"17:40", "18:30"},
            {"19:30", "20:20"},
            {"20:30", "21:20"},
            {"21:30", "22:20"}
    };
    private static final String[][] FRIENDSHIP_WINTER_SECTION_TIMES = {
            {"08:00", "08:50"},
            {"09:00", "09:50"},
            {"10:10", "11:00"},
            {"11:10", "12:00"},
            {"12:20", "13:05"},
            {"13:05", "13:50"},
            {"14:00", "14:50"},
            {"15:00", "15:50"},
            {"16:10", "17:00"},
            {"17:10", "18:00"},
            {"19:00", "19:50"},
            {"20:00", "20:50"},
            {"21:00", "21:50"}
    };

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
        private JSONObject originalJson;

        public SectionTime(String start, String end) {
            this.start = start;
            this.end = end;
        }

        public JSONObject json() {
            JSONObject o = copyOf(originalJson);
            try {
                o.put("start", start);
                o.put("end", end);
            } catch (Exception ignored) {}
            return o;
        }

        public static SectionTime from(JSONObject o) {
            SectionTime time = new SectionTime(
                    o.optString("start", "08:00"), o.optString("end", "08:45"));
            time.originalJson = copyOf(o);
            return time;
        }
    }

    public static class TimeSlot {
        public String weekRange;
        public RepeatRule repeatRule;
        public int dayOfWeek;
        public List<Integer> classSections;
        public String teacher;
        public String location;
        private String repeatRuleWireValue;
        private JSONObject originalJson;

        public TimeSlot(String weekRange, RepeatRule repeatRule, int dayOfWeek, List<Integer> classSections) {
            this(weekRange, repeatRule, dayOfWeek, classSections, null, null);
        }

        public TimeSlot(String weekRange, RepeatRule repeatRule, int dayOfWeek, List<Integer> classSections,
                        String teacher, String location) {
            this.weekRange = weekRange;
            this.repeatRule = repeatRule == null ? RepeatRule.ALL : repeatRule;
            this.dayOfWeek = dayOfWeek;
            this.classSections = new ArrayList<>(classSections);
            this.teacher = teacher;
            this.location = location;
        }

        public JSONObject json() {
            JSONObject o = copyOf(originalJson);
            try {
                o.put("weekRange", weekRange);
                o.put("repeatRule", repeatRuleWireValue == null ? repeatRule.storedValue : repeatRuleWireValue);
                o.put("dayOfWeek", dayOfWeek);
                JSONArray sections = new JSONArray();
                for (Integer value : classSections) {
                    sections.put(value);
                }
                o.put("classSections", sections);
                o.put("teacher", teacher == null ? JSONObject.NULL : teacher);
                o.put("location", location == null ? JSONObject.NULL : location);
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
            TimeSlot slot = new TimeSlot(
                    o.optString("weekRange", "1-17"),
                    RepeatRule.fromStoredValue(o.optString("repeatRule", "")),
                    o.optInt("dayOfWeek", 1),
                    sections,
                    o.isNull("teacher") ? null : o.optString("teacher", null),
                    o.isNull("location") ? null : o.optString("location", null)
            );
            String repeatRuleValue = o.has("repeatRule") && !o.isNull("repeatRule")
                    ? o.optString("repeatRule", "") : null;
            // Preserve only values the current enum cannot interpret. Known values
            // must be serialized from the mutable enum so edits are not overwritten
            // by the original wire value.
            slot.repeatRuleWireValue = slot.repeatRule == RepeatRule.ALL
                    && repeatRuleValue != null
                    && !RepeatRule.ALL.storedValue.equals(repeatRuleValue)
                    && RepeatRule.ODD.storedValue.equals(repeatRuleValue) == false
                    && RepeatRule.EVEN.storedValue.equals(repeatRuleValue) == false
                    ? repeatRuleValue : null;
            slot.originalJson = copyOf(o);
            return slot;
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
        private JSONObject originalJson;

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
            JSONObject o = copyOf(originalJson);
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
            String id = requireId(o, "id", "Semester");
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
            Semester semester = new Semester(
                    id,
                    o.optString("name", "学期"),
                    o.optString("startDate", LocalDate.now().toString()),
                    o.optString("endDate", LocalDate.now().plusWeeks(17).minusDays(1).toString()),
                    Math.max(1, o.optInt("weekCount", 17)),
                    sectionCount,
                    sectionTimes
            );
            semester.originalJson = copyOf(o);
            return semester;
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
        private String assessmentMethodWireValue;
        private JSONObject originalJson;

        public Course(String id, String name, String semesterId, List<TimeSlot> timeSlots) {
            this.id = id;
            this.name = name;
            this.semesterId = semesterId;
            this.timeSlots = new ArrayList<>(timeSlots);
        }

        public JSONObject json() {
            JSONObject o = copyOf(originalJson);
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
                o.put("assessmentMethod", assessmentMethod != null
                        ? assessmentMethod.label
                        : assessmentMethodWireValue == null ? JSONObject.NULL : assessmentMethodWireValue);
                o.put("notes", notes == null ? JSONObject.NULL : notes);
                o.put("color", color == null ? JSONObject.NULL : color);
            } catch (Exception ignored) {}
            return o;
        }

        public static Course from(JSONObject o) {
            String id = requireId(o, "id", "Course");
            String semesterId = requireId(o, "semesterId", "Course");
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
                slots.add(new TimeSlot("1-17", RepeatRule.ALL, 1, Arrays.asList(1, 2)));
            }
            Course course = new Course(
                    id,
                    o.optString("name", "课程"),
                    semesterId,
                    slots
            );
            course.code = o.isNull("code") ? null : o.optString("code", null);
            course.location = o.isNull("location") ? null : o.optString("location", null);
            course.credits = o.isNull("credits") ? null : o.optDouble("credits");
            course.teacher = o.isNull("teacher") ? null : o.optString("teacher", null);
            for (TimeSlot slot : course.timeSlots) {
                if (slot.location == null) slot.location = course.location;
                if (slot.teacher == null) slot.teacher = course.teacher;
            }
            String assessmentValue = o.isNull("assessmentMethod")
                    ? null : o.optString("assessmentMethod", "");
            course.assessmentMethod = assessmentValue == null ? null : AssessmentMethod.fromLabel(assessmentValue);
            course.assessmentMethodWireValue = course.assessmentMethod == null ? assessmentValue : null;
            course.notes = o.isNull("notes") ? null : o.optString("notes", null);
            course.color = o.isNull("color") ? null : o.optString("color", null);
            course.originalJson = copyOf(o);
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

    public static boolean isFriendshipCampus(String location) {
        return location != null && location.contains("友谊");
    }

    public static List<SectionTime> buildFriendshipSectionTimes(int count, LocalDate date) {
        LocalDate effectiveDate = date == null ? LocalDate.now() : date;
        int month = effectiveDate.getMonthValue();
        String[][] standard = month >= 5 && month <= 9
                ? FRIENDSHIP_SUMMER_SECTION_TIMES
                : FRIENDSHIP_WINTER_SECTION_TIMES;
        List<SectionTime> times = new ArrayList<>();
        int standardCount = Math.min(Math.max(0, count), standard.length);
        for (int i = 0; i < standardCount; i++) {
            times.add(new SectionTime(standard[i][0], standard[i][1]));
        }
        int cursor = parseMinutes(standard[standard.length - 1][1]) + 10;
        for (int i = standard.length; i < count; i++) {
            times.add(new SectionTime(formatMinutes(cursor), formatMinutes(cursor + 50)));
            cursor += 60;
        }
        return times;
    }

    public static SectionTime sectionTimeFor(Semester semester, String location,
                                             LocalDate date, int section) {
        if (section < 1) return null;
        if (isFriendshipCampus(location)) {
            int count = Math.max(section, semester == null ? 13 : semester.sectionCount);
            List<SectionTime> times = buildFriendshipSectionTimes(count, date);
            return section <= times.size() ? times.get(section - 1) : null;
        }
        if (semester == null || section > semester.sectionTimes.size()) return null;
        return semester.sectionTimes.get(section - 1);
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

    private static int parseMinutes(String value) {
        String[] parts = value.split(":", 2);
        return Integer.parseInt(parts[0]) * 60 + Integer.parseInt(parts[1]);
    }

    private static JSONObject copyOf(JSONObject source) {
        if (source == null) return new JSONObject();
        try {
            return new JSONObject(source.toString());
        } catch (Exception ignored) {
            return new JSONObject();
        }
    }

    private static String requireId(JSONObject object, String key, String kind) {
        if (object == null || !object.has(key) || object.isNull(key)) {
            throw new IllegalArgumentException(kind + " " + key + " must be a non-empty string");
        }
        Object value;
        try {
            value = object.get(key);
        } catch (Exception error) {
            throw new IllegalArgumentException(kind + " " + key + " must be a non-empty string", error);
        }
        if (!(value instanceof String) || ((String) value).trim().isEmpty()) {
            throw new IllegalArgumentException(kind + " " + key + " must be a non-empty string");
        }
        return (String) value;
    }
}
