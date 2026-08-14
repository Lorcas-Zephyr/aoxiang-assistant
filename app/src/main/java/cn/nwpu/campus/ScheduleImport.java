package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class ScheduleImport {
    private ScheduleImport() {}

    public static class RawSemester {
        public String name;
        public String dataSemester;

        public RawSemester(String name, String dataSemester) {
            this.name = name;
            this.dataSemester = dataSemester;
        }
    }

    public static class RawCourse {
        public String name;
        public String code;
        public Double credits;
        public String teacher;
        public String assessmentMethod;
        public String scheduleText;
        public String location;
        public String dataSemester;
    }

    public static class ParsedData {
        public List<RawSemester> semesters = new ArrayList<>();
        public List<RawCourse> courses = new ArrayList<>();
    }

    private static final Pattern CHINESE_SECTION_RANGE = Pattern.compile("第(十一|十二|十三|十四|十五|十六|十七|十八|十九|二十|一|二|三|四|五|六|七|八|九|十)节[~至\\-—]?第?(十一|十二|十三|十四|十五|十六|十七|十八|十九|二十|一|二|三|四|五|六|七|八|九|十)?节");
    private static final Pattern ARABIC_SECTION_RANGE_A = Pattern.compile("第(\\d+)[节~至\\-](?:第)?(\\d+)节");
    private static final Pattern ARABIC_SECTION_RANGE_B = Pattern.compile("(\\d+)[节~至\\-](\\d+)节");
    private static final Pattern ARABIC_SECTION_LIST = Pattern.compile("第((?:\\d+,)*\\d+)节");
    private static final Pattern ARABIC_SECTION_LIST_B = Pattern.compile("((?:\\d+,)*\\d+)节");
    private static final Pattern CHINESE_SECTION_SINGLE = Pattern.compile("第(十一|十二|十三|十四|十五|十六|十七|十八|十九|二十|一|二|三|四|五|六|七|八|九|十)节");
    private static final Pattern ARABIC_SECTION_SINGLE = Pattern.compile("第(\\d+)节");
    private static final Pattern ARABIC_SECTION_SINGLE_B = Pattern.compile("(\\d+)节");
    private static final Pattern WEEK_RANGE = Pattern.compile("(\\d{1,3})[~至\\-—](\\d{1,3})");
    private static final Pattern WEEK_SINGLE = Pattern.compile("(\\d{1,3})");
    private static final String[] ONLINE_KEYWORDS = {"网课", "线上", "在线"};
    private static final Map<String, Integer> CHINESE_NUMBERS = buildChineseNumbers();
    private static final Map<String, Integer> DAY_MAP = buildDayMap();

    public static ParsedData parsePayload(JSONObject payload) {
        ParsedData result = new ParsedData();
        JSONArray semesters = payload.optJSONArray("semesters");
        JSONArray courses = payload.optJSONArray("courses");
        if (semesters != null) {
            for (int i = 0; i < semesters.length(); i++) {
                JSONObject item = semesters.optJSONObject(i);
                if (item == null) continue;
                String name = item.optString("name");
                String value = item.optString("dataSemester", name);
                if (!name.isEmpty()) result.semesters.add(new RawSemester(name, value));
            }
        }
        if (courses != null) {
            for (int i = 0; i < courses.length(); i++) {
                JSONObject item = courses.optJSONObject(i);
                if (item == null) continue;
                RawCourse course = new RawCourse();
                course.name = item.optString("name");
                course.code = item.isNull("code") ? null : item.optString("code", null);
                course.credits = item.isNull("credits") ? null : item.optDouble("credits");
                course.teacher = item.isNull("teacher") ? null : item.optString("teacher", null);
                course.assessmentMethod = item.isNull("assessmentMethod") ? null : item.optString("assessmentMethod", null);
                course.scheduleText = item.optString("scheduleText");
                course.location = item.isNull("location") ? null : item.optString("location", null);
                course.dataSemester = item.optString("dataSemester");
                if (course.name != null && !course.name.trim().isEmpty()) result.courses.add(course);
            }
        }
        if (result.semesters.isEmpty()) {
            result.semesters.add(new RawSemester("当前学期", "current"));
        }
        return result;
    }

    public static List<ScheduleModels.Course> convertToCourses(List<RawCourse> rawCourses, String semesterId, String targetDataSemester) {
        Map<String, ScheduleModels.Course> grouped = new LinkedHashMap<>();
        int colorIndex = 0;
        for (RawCourse raw : rawCourses) {
            if (targetDataSemester != null && !targetDataSemester.isEmpty() && !targetDataSemester.equals(raw.dataSemester)) continue;
            if (raw.scheduleText == null || raw.scheduleText.trim().isEmpty()) continue;
            List<ScheduleModels.TimeSlot> timeSlots = parseScheduleText(raw.scheduleText);
            if (timeSlots.isEmpty()) continue;
            String teacher = mergeTeachers(raw.teacher);
            String location = emptyToNull(formatLocation(raw.location));
            for (ScheduleModels.TimeSlot slot : timeSlots) {
                slot.teacher = teacher;
                slot.location = location;
            }
            String code = emptyToNull(raw.code);
            String key = (code == null ? "" : code.toLowerCase(Locale.ROOT)) + "|" + raw.name.trim();
            ScheduleModels.Course existing = grouped.get(key);
            if (existing != null) {
                existing.timeSlots.addAll(timeSlots);
                existing.timeSlots = mergeSlots(existing.timeSlots);
                existing.location = mergeLocations(existing.location, location);
                existing.teacher = mergeTeachers(existing.teacher, teacher);
                continue;
            }
            ScheduleModels.Course course = new ScheduleModels.Course(UUID.randomUUID().toString(), raw.name.trim(), semesterId, timeSlots);
            course.code = emptyToNull(raw.code);
            course.credits = raw.credits;
            course.teacher = teacher;
            course.assessmentMethod = parseAssessment(raw.assessmentMethod);
            course.location = location;
            course.color = ScheduleModels.PRESET_COLORS.get(colorIndex % ScheduleModels.PRESET_COLORS.size());
            grouped.put(key, course);
            colorIndex++;
        }
        return new ArrayList<>(grouped.values());
    }

    public static ScheduleModels.Semester createImportedSemester(RawSemester raw, List<ScheduleModels.Course> courses) {
        int maxWeek = Math.max(20, calculateMaxWeek(courses));
        int year = LocalDate.now().getYear();
        int month = 9;
        if (raw.dataSemester != null) {
            Matcher matcher = Pattern.compile("(\\d{4})-(\\d{4})-(\\d+)").matcher(raw.dataSemester);
            if (matcher.find()) {
                year = Integer.parseInt(matcher.group(1));
                int term = Integer.parseInt(matcher.group(3));
                month = term == 2 ? 2 : 9;
                if (term == 2) year = Integer.parseInt(matcher.group(2));
            }
        }
        LocalDate start = ScheduleUtils.mondayOnOrBefore(LocalDate.of(year, month, month == 2 ? 24 : 1));
        LocalDate end = start.plusWeeks(maxWeek).minusDays(1);
        return new ScheduleModels.Semester(
                "semester-" + UUID.randomUUID(),
                raw.name == null || raw.name.trim().isEmpty() ? "导入学期" : raw.name.trim(),
                start.toString(),
                end.toString(),
                maxWeek,
                13,
                ScheduleModels.buildDefaultSectionTimes(13)
        );
    }

    public static List<ScheduleModels.TimeSlot> parseScheduleText(String value) {
        List<ScheduleModels.TimeSlot> slots = new ArrayList<>();
        if (value == null || value.trim().isEmpty()) {
            return slots;
        }
        String cleaned = value.replaceAll("<[^>]+>", " ").replace("&nbsp;", " ").replaceAll("\\s+", " ").trim();
        String[] segments = cleaned.split("[;；]");
        for (String rawSegment : segments) {
            String segment = rawSegment.trim();
            if (segment.isEmpty() || containsAny(segment, ONLINE_KEYWORDS)) continue;
            Integer day = parseDayOfWeek(segment);
            if (day == null) continue;
            int dayPosition = findDayPosition(segment);
            String weekPart = dayPosition >= 0 ? segment.substring(0, dayPosition) : segment;
            String restPart = dayPosition >= 0 ? segment.substring(dayPosition) : segment;
            List<Integer> sections = parseSections(restPart);
            if (sections.isEmpty()) continue;
            ScheduleModels.RepeatRule rule = parseRepeatRule(segment);
            List<String> weekRanges = extractWeekRanges(weekPart);
            for (String weekRange : weekRanges) {
                slots.add(new ScheduleModels.TimeSlot(weekRange, rule, day, sections));
            }
        }
        return mergeSlots(slots);
    }

    private static List<ScheduleModels.TimeSlot> mergeSlots(List<ScheduleModels.TimeSlot> slots) {
        Map<String, List<ScheduleModels.TimeSlot>> grouped = new LinkedHashMap<>();
        for (ScheduleModels.TimeSlot slot : slots) {
            String key = slot.dayOfWeek + ":" + slot.classSections.toString() + ":" + slot.repeatRule.name()
                    + ":" + nullToEmpty(slot.teacher) + ":" + nullToEmpty(slot.location);
            grouped.computeIfAbsent(key, unused -> new ArrayList<>()).add(slot);
        }
        List<ScheduleModels.TimeSlot> merged = new ArrayList<>();
        for (List<ScheduleModels.TimeSlot> group : grouped.values()) {
            List<int[]> intervals = new ArrayList<>();
            for (ScheduleModels.TimeSlot slot : group) {
                List<Integer> weeks = ScheduleUtils.parseWeeks(slot.weekRange);
                if (weeks.isEmpty()) continue;
                intervals.add(new int[]{Collections.min(weeks), Collections.max(weeks)});
            }
            intervals.sort((a, b) -> Integer.compare(a[0], b[0]));
            List<int[]> mergedIntervals = new ArrayList<>();
            for (int[] interval : intervals) {
                if (mergedIntervals.isEmpty()) {
                    mergedIntervals.add(interval);
                    continue;
                }
                int[] last = mergedIntervals.get(mergedIntervals.size() - 1);
                if (interval[0] <= last[1] + 1) last[1] = Math.max(last[1], interval[1]);
                else mergedIntervals.add(interval);
            }
            for (int[] interval : mergedIntervals) {
                merged.add(new ScheduleModels.TimeSlot(
                        interval[0] == interval[1] ? String.valueOf(interval[0]) : interval[0] + "-" + interval[1],
                        group.get(0).repeatRule,
                        group.get(0).dayOfWeek,
                        group.get(0).classSections,
                        group.get(0).teacher,
                        group.get(0).location
                ));
            }
        }
        return merged;
    }

    private static List<Integer> parseSections(String text) {
        Matcher m = CHINESE_SECTION_RANGE.matcher(text);
        if (m.find()) return range(chineseNumber(m.group(1)), chineseNumber(m.group(2) == null ? m.group(1) : m.group(2)));
        m = ARABIC_SECTION_RANGE_A.matcher(text);
        if (m.find()) return range(parseInt(m.group(1)), parseInt(m.group(2)));
        m = ARABIC_SECTION_RANGE_B.matcher(text);
        if (m.find()) return range(parseInt(m.group(1)), parseInt(m.group(2)));
        m = ARABIC_SECTION_LIST.matcher(text);
        if (m.find()) return parseCsv(m.group(1));
        m = ARABIC_SECTION_LIST_B.matcher(text);
        if (m.find()) return parseCsv(m.group(1));
        m = CHINESE_SECTION_SINGLE.matcher(text);
        if (m.find()) return Arrays.asList(chineseNumber(m.group(1)));
        m = ARABIC_SECTION_SINGLE.matcher(text);
        if (m.find()) return Arrays.asList(parseInt(m.group(1)));
        m = ARABIC_SECTION_SINGLE_B.matcher(text);
        if (m.find()) return Arrays.asList(parseInt(m.group(1)));
        return new ArrayList<>();
    }

    private static ScheduleModels.RepeatRule parseRepeatRule(String text) {
        if (text.contains("单周") || text.contains("(单)") || text.contains("（单）")) return ScheduleModels.RepeatRule.ODD;
        if (text.contains("双周") || text.contains("(双)") || text.contains("（双）")) return ScheduleModels.RepeatRule.EVEN;
        return ScheduleModels.RepeatRule.ALL;
    }

    private static List<String> extractWeekRanges(String text) {
        String converted = text;
        for (Map.Entry<String, Integer> entry : CHINESE_NUMBERS.entrySet()) {
            converted = converted.replace("第" + entry.getKey() + "周", String.valueOf(entry.getValue()));
        }
        converted = converted.replace("周", "").trim();
        if (converted.isEmpty()) return Arrays.asList("1-16");
        List<String> ranges = new ArrayList<>();
        for (String raw : converted.split("[,，、]")) {
            String part = raw.trim();
            Matcher rangeMatcher = WEEK_RANGE.matcher(part);
            if (rangeMatcher.find()) {
                int start = parseInt(rangeMatcher.group(1));
                int end = parseInt(rangeMatcher.group(2));
                if (start > 0 && end >= start) ranges.add(start == end ? String.valueOf(start) : start + "-" + end);
                continue;
            }
            Matcher singleMatcher = WEEK_SINGLE.matcher(part);
            if (singleMatcher.find()) {
                int week = parseInt(singleMatcher.group(1));
                if (week > 0) ranges.add(String.valueOf(week));
            }
        }
        return ranges.isEmpty() ? Arrays.asList("1-16") : ranges;
    }

    private static Integer parseDayOfWeek(String text) {
        for (Map.Entry<String, Integer> entry : DAY_MAP.entrySet()) {
            if (text.contains(entry.getKey())) return entry.getValue();
        }
        return null;
    }

    private static int findDayPosition(String text) {
        int index = -1;
        for (String key : DAY_MAP.keySet()) {
            int found = text.indexOf(key);
            if (found >= 0 && (index < 0 || found < index)) index = found;
        }
        return index;
    }

    private static int calculateMaxWeek(List<ScheduleModels.Course> courses) {
        int max = 0;
        for (ScheduleModels.Course course : courses) {
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                for (Integer week : ScheduleUtils.parseWeeks(slot.weekRange)) {
                    max = Math.max(max, week);
                }
            }
        }
        return max;
    }

    private static ScheduleModels.AssessmentMethod parseAssessment(String value) {
        if (value == null) return null;
        if (value.contains("考试")) return ScheduleModels.AssessmentMethod.EXAM;
        if (value.contains("考察")) return ScheduleModels.AssessmentMethod.INSPECTION;
        if (value.contains("PnP")) return ScheduleModels.AssessmentMethod.PNP;
        return null;
    }

    private static String mergeTeachers(String... values) {
        List<String> out = new ArrayList<>();
        for (String value : values) {
            if (value == null) continue;
            for (String name : value.split("[,，、;/；|｜\\s]+")) {
                String trimmed = name.trim();
                if (!trimmed.isEmpty() && !isTeacherMetadata(trimmed) && !out.contains(trimmed)) out.add(trimmed);
                if (out.size() == 15) break;
            }
            if (out.size() == 15) break;
        }
        return out.isEmpty() ? null : ScheduleUtils.join(out, "、");
    }

    private static boolean isTeacherMetadata(String value) {
        return value.matches(".*(?:学科基础|专业基础|专业核心|公共基础|通识教育|实践实训|集中实践|创新创业|素质拓展|全校|本科|研究生|培养方案|课程类别|必修|选修|限选|任选).*");
    }

    private static String mergeLocations(String... values) {
        List<String> out = new ArrayList<>();
        for (String value : values) {
            if (value == null) continue;
            for (String part : value.split("[\\n;；]+")) {
                String location = formatLocation(part);
                if (!location.isEmpty() && !out.contains(location)) out.add(location);
            }
        }
        return out.isEmpty() ? null : ScheduleUtils.join(out, "\n");
    }

    private static String formatLocation(String raw) {
        if (raw == null) return null;
        return raw.replaceAll("\\s+", " ").trim();
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value.trim();
    }

    private static boolean containsAny(String text, String[] keywords) {
        for (String keyword : keywords) if (text.contains(keyword)) return true;
        return false;
    }

    private static List<Integer> range(int start, int end) {
        List<Integer> out = new ArrayList<>();
        for (int value = Math.min(start, end); value <= Math.max(start, end); value++) out.add(value);
        return out;
    }

    private static List<Integer> parseCsv(String value) {
        List<Integer> out = new ArrayList<>();
        for (String part : value.split(",")) {
            int parsed = parseInt(part.trim());
            if (parsed > 0) out.add(parsed);
        }
        return out;
    }

    private static int chineseNumber(String value) {
        if (value == null) return 0;
        Integer parsed = CHINESE_NUMBERS.get(value);
        return parsed == null ? parseInt(value) : parsed;
    }

    private static int parseInt(String value) {
        try {
            return Integer.parseInt(value);
        } catch (Exception ignored) {
            return 0;
        }
    }

    private static String emptyToNull(String value) {
        return value == null || value.trim().isEmpty() ? null : value.trim();
    }

    private static Map<String, Integer> buildChineseNumbers() {
        Map<String, Integer> map = new LinkedHashMap<>();
        map.put("一", 1); map.put("二", 2); map.put("三", 3); map.put("四", 4); map.put("五", 5);
        map.put("六", 6); map.put("七", 7); map.put("八", 8); map.put("九", 9); map.put("十", 10);
        map.put("十一", 11); map.put("十二", 12); map.put("十三", 13); map.put("十四", 14); map.put("十五", 15);
        map.put("十六", 16); map.put("十七", 17); map.put("十八", 18); map.put("十九", 19); map.put("二十", 20);
        map.put("二十一", 21); map.put("二十二", 22);
        return map;
    }

    private static Map<String, Integer> buildDayMap() {
        Map<String, Integer> map = new LinkedHashMap<>();
        map.put("周一", 1); map.put("周二", 2); map.put("周三", 3); map.put("周四", 4); map.put("周五", 5); map.put("周六", 6); map.put("周日", 7);
        map.put("星期一", 1); map.put("星期二", 2); map.put("星期三", 3); map.put("星期四", 4); map.put("星期五", 5); map.put("星期六", 6); map.put("星期日", 7); map.put("星期天", 7);
        return map;
    }
}
