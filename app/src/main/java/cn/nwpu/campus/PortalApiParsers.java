package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

final class PortalApiParsers {
    private static final String[] DAY_LABELS = {
            "", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"
    };

    private PortalApiParsers() {}

    static JSONArray gradeRows(JSONArray responses) {
        JSONArray rows = new JSONArray();
        if (responses == null) return rows;
        for (int responseIndex = 0; responseIndex < responses.length(); responseIndex++) {
            JSONObject response = responses.optJSONObject(responseIndex);
            JSONObject semesterGrades = response == null
                    ? null : response.optJSONObject("semesterId2studentGrades");
            if (semesterGrades == null) continue;
            JSONArray semesterIds = semesterGrades.names();
            if (semesterIds == null) continue;
            for (int semesterIndex = 0; semesterIndex < semesterIds.length(); semesterIndex++) {
                JSONArray grades = semesterGrades.optJSONArray(semesterIds.optString(semesterIndex));
                if (grades == null) continue;
                for (int gradeIndex = 0; gradeIndex < grades.length(); gradeIndex++) {
                    JSONObject grade = grades.optJSONObject(gradeIndex);
                    if (grade == null || !grade.optBoolean("published", true)) continue;
                    JSONObject course = grade.optJSONObject("course");
                    String name = firstNonEmpty(course == null ? "" : course.optString("nameZh"),
                            grade.optString("lessonNameZh"));
                    if (name.isEmpty()) continue;
                    JSONArray row = new JSONArray();
                    row.put(name);
                    row.put(Double.valueOf(course == null ? 0.0 : course.optDouble("credits", 0.0)));
                    putNullable(row, grade, "gp");
                    row.put(grade.isNull("gaGrade") ? "" : grade.optString("gaGrade"));
                    row.put(grade.isNull("gradeDetail") ? "" : grade.optString("gradeDetail"));
                    rows.put(row);
                }
            }
        }
        return rows;
    }

    static double gpa(JSONObject response) {
        if (response == null) return Double.NaN;
        JSONObject rank = response.optJSONObject("stdGpaRankDto");
        double value = gpaField(rank);
        if (!Double.isNaN(value)) return value;
        value = gpaField(response);
        if (!Double.isNaN(value)) return value;
        return findGpa(response, 0);
    }

    private static double findGpa(Object value, int depth) {
        if (value == null || depth > 6) return Double.NaN;
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            JSONArray names = object.names();
            if (names == null) return Double.NaN;
            for (int i = 0; i < names.length(); i++) {
                String key = names.optString(i);
                if (isGpaKey(key)) {
                    double candidate = parseGpa(object.opt(key));
                    if (!Double.isNaN(candidate)) return candidate;
                }
            }
            for (int i = 0; i < names.length(); i++) {
                double candidate = findGpa(object.opt(names.optString(i)), depth + 1);
                if (!Double.isNaN(candidate)) return candidate;
            }
        } else if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) {
                double candidate = findGpa(array.opt(i), depth + 1);
                if (!Double.isNaN(candidate)) return candidate;
            }
        }
        return Double.NaN;
    }

    private static double gpaField(JSONObject object) {
        if (object == null) return Double.NaN;
        JSONArray names = object.names();
        if (names == null) return Double.NaN;
        for (int i = 0; i < names.length(); i++) {
            String key = names.optString(i);
            if (isGpaKey(key)) {
                double value = parseGpa(object.opt(key));
                if (!Double.isNaN(value)) return value;
            }
        }
        return Double.NaN;
    }

    private static boolean isGpaKey(String key) {
        String normalized = key == null ? "" : key.replaceAll("[\\s_\\-]", "")
                .toLowerCase(java.util.Locale.ROOT);
        return normalized.equals("gpa") || normalized.equals("avggpa")
                || normalized.equals("averagegpa") || normalized.equals("studentgpa")
                || normalized.equals("cumulativegpa") || normalized.equals("gradepointaverage")
                || normalized.equals("averagegradepoint") || normalized.equals("平均绩点")
                || normalized.equals("平均学分绩点") || normalized.equals("累计平均学分绩点");
    }

    private static double parseGpa(Object raw) {
        if (raw == null || raw == JSONObject.NULL) return Double.NaN;
        java.util.regex.Matcher matcher = java.util.regex.Pattern
                .compile("(?:^|[^0-9])(\\d(?:\\.\\d{1,4})?)(?:[^0-9]|$)")
                .matcher(String.valueOf(raw));
        if (!matcher.find()) return Double.NaN;
        try {
            double value = Double.parseDouble(matcher.group(1));
            return value >= 0.0 && value <= 5.0 ? value : Double.NaN;
        } catch (Exception ignored) {
            return Double.NaN;
        }
    }

    static JSONObject schedulePayload(JSONObject semester, JSONObject printData) {
        JSONObject payload = new JSONObject();
        JSONArray semesters = new JSONArray();
        JSONArray courses = new JSONArray();
        JSONObject table = printData == null ? null : printData.optJSONObject("studentTableVm");
        JSONArray activities = table == null ? null : table.optJSONArray("activities");
        if (activities == null) activities = new JSONArray();

        String semesterId = semester == null ? "current"
                : firstNonEmpty(semester.optString("id"), semester.optString("code"), "current");
        String semesterName = semester == null ? "当前学期"
                : firstNonEmpty(semester.optString("nameZh"), semester.optString("name"),
                semester.optString("code"), "当前学期");
        String startDate = semester == null ? "" : semester.optString("startDate");
        String endDate = effectiveEndDate(startDate, activities);
        if (endDate.isEmpty() && semester != null) endDate = semester.optString("endDate");

        JSONObject semesterItem = new JSONObject();
        put(semesterItem, "name", semesterName);
        put(semesterItem, "dataSemester", semesterId);
        if (!startDate.isEmpty()) put(semesterItem, "startDate", startDate);
        if (!endDate.isEmpty()) put(semesterItem, "endDate", endDate);
        semesters.put(semesterItem);

        for (int i = 0; i < activities.length(); i++) {
            JSONObject activity = activities.optJSONObject(i);
            if (activity == null) continue;
            String name = activity.optString("courseName").trim();
            int weekday = activity.optInt("weekday", 0);
            int startUnit = activity.optInt("startUnit", 0);
            int endUnit = activity.optInt("endUnit", 0);
            if (name.isEmpty() || weekday < 1 || weekday > 7 || startUnit < 1 || endUnit < startUnit) {
                continue;
            }
            String location = joinUnique(activity.optString("campus"), activity.optString("building"),
                    activity.optString("room"));
            if (containsOnline(name) || containsOnline(location)) continue;
            JSONObject course = new JSONObject();
            put(course, "name", name);
            putOptional(course, "code", activity.optString("courseCode"));
            if (!activity.isNull("credits")) put(course, "credits", activity.optDouble("credits"));
            putOptional(course, "teacher", teacherNames(activity.optJSONArray("teachers")));
            put(course, "scheduleText", compactWeeks(activity.optJSONArray("weekIndexes")) + " "
                    + DAY_LABELS[weekday] + " " + startUnit + "-" + endUnit + "节");
            putOptional(course, "location", location);
            put(course, "dataSemester", semesterId);
            courses.put(course);
        }
        put(payload, "semesters", semesters);
        put(payload, "courses", courses);
        return payload;
    }

    static double electricityBalance(JSONObject response) {
        JSONObject map = response == null ? null : response.optJSONObject("map");
        JSONObject showData = map == null ? null : map.optJSONObject("showData");
        if (showData == null) return Double.NaN;
        String[] keys = {"当前剩余电量", "剩余电量", "电费余额", "剩余电费"};
        for (String key : keys) {
            if (!showData.has(key) || showData.isNull(key)) continue;
            double value = parseNumber(String.valueOf(showData.opt(key)));
            if (!Double.isNaN(value) && value >= 0.0 && value < 100000.0) return value;
        }
        return Double.NaN;
    }

    private static String effectiveEndDate(String startDate, JSONArray activities) {
        try {
            LocalDate start = ScheduleUtils.mondayOnOrBefore(LocalDate.parse(startDate));
            LocalDate last = start.plusDays(13);
            for (int i = 0; i < activities.length(); i++) {
                JSONObject activity = activities.optJSONObject(i);
                if (activity == null) continue;
                int weekday = activity.optInt("weekday", 0);
                if (weekday < 1 || weekday > 7) continue;
                JSONArray weeks = activity.optJSONArray("weekIndexes");
                if (weeks == null) continue;
                for (int weekIndex = 0; weekIndex < weeks.length(); weekIndex++) {
                    int week = weeks.optInt(weekIndex, 0);
                    if (week < 1) continue;
                    LocalDate date = ScheduleUtils.dateForWeekDay(start, week, weekday);
                    if (date.isAfter(last)) last = date;
                }
            }
            return last.toString();
        } catch (Exception ignored) {
            return "";
        }
    }

    private static String compactWeeks(JSONArray values) {
        Set<Integer> unique = new LinkedHashSet<>();
        if (values != null) {
            List<Integer> sorted = new ArrayList<>();
            for (int i = 0; i < values.length(); i++) {
                int value = values.optInt(i, 0);
                if (value > 0 && !sorted.contains(value)) sorted.add(value);
            }
            sorted.sort(Integer::compareTo);
            unique.addAll(sorted);
        }
        if (unique.isEmpty()) return "1~17周";
        List<Integer> weeks = new ArrayList<>(unique);
        List<String> ranges = new ArrayList<>();
        for (int index = 0; index < weeks.size();) {
            int start = weeks.get(index);
            int end = start;
            while (index + 1 < weeks.size() && weeks.get(index + 1) == end + 1) {
                index++;
                end = weeks.get(index);
            }
            ranges.add(start == end ? String.valueOf(start) : start + "~" + end);
            index++;
        }
        return String.join(",", ranges) + "周";
    }

    private static String teacherNames(JSONArray teachers) {
        Set<String> names = new LinkedHashSet<>();
        if (teachers != null) {
            for (int i = 0; i < teachers.length(); i++) {
                Object raw = teachers.opt(i);
                String name;
                if (raw instanceof JSONObject) {
                    JSONObject teacher = (JSONObject) raw;
                    name = firstNonEmpty(teacher.optString("nameZh"), teacher.optString("name"),
                            teacher.optString("teacherName"));
                } else {
                    name = raw == null ? "" : String.valueOf(raw).trim();
                }
                if (!name.isEmpty()) names.add(name);
            }
        }
        return String.join("、", names);
    }

    private static String joinUnique(String... values) {
        Set<String> parts = new LinkedHashSet<>();
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) parts.add(value.trim());
        }
        return String.join(" ", parts);
    }

    private static boolean containsOnline(String value) {
        return value != null && (value.contains("网课") || value.contains("线上") || value.contains("在线"));
    }

    private static String firstNonEmpty(String... values) {
        for (String value : values) {
            if (value != null && !value.trim().isEmpty()) return value.trim();
        }
        return "";
    }

    private static double parseNumber(String raw) {
        try {
            String cleaned = raw == null ? "" : raw.replaceAll("[^0-9.\\-]", "");
            return cleaned.isEmpty() ? Double.NaN : Double.parseDouble(cleaned);
        } catch (Exception ignored) {
            return Double.NaN;
        }
    }

    private static void putNullable(JSONArray array, JSONObject source, String key) {
        if (source.isNull(key)) array.put(JSONObject.NULL);
        else array.put(Double.valueOf(source.optDouble(key)));
    }

    private static void putOptional(JSONObject object, String key, String value) {
        if (value != null && !value.trim().isEmpty()) put(object, key, value.trim());
    }

    private static void put(JSONObject object, String key, Object value) {
        try {
            object.put(key, value);
        } catch (Exception ignored) {}
    }
}
