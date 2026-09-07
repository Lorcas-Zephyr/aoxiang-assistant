package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.time.LocalDate;
import java.time.Clock;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;

/** Stable, non-sensitive schedule backup format shared by Android and iOS. */
public final class BackupContract {
    public static final int LEGACY_SCHEMA_VERSION = 0;
    public static final int CURRENT_SCHEMA_VERSION = 1;
    public static final String FORMAT = "aoxiang-assistant.schedule-backup";
    public static final String LEGACY_VERSION = "2.0";

    public static final String KEY_FORMAT = "format";
    public static final String KEY_SCHEMA_VERSION = "schemaVersion";
    public static final String KEY_VERSION = "version";
    public static final String KEY_EXPORT_DATE = "exportDate";
    public static final String KEY_COURSES = "courses";
    public static final String KEY_SETTINGS = "settings";
    public static final String KEY_SEMESTERS = "semesters";
    public static final String KEY_THEME_COLOR = "themeColor";
    public static final String KEY_DARK_MODE = "darkMode";
    public static final String KEY_SELECTED_SEMESTER_ID = "selectedSemesterId";
    public static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");

    private static final Set<String> TOP_LEVEL_KEYS = new HashSet<>(Arrays.asList(
            KEY_FORMAT,
            KEY_SCHEMA_VERSION,
            KEY_VERSION,
            KEY_EXPORT_DATE,
            KEY_COURSES,
            KEY_SETTINGS
    ));
    private static final Set<String> SETTINGS_KEYS = new HashSet<>(Arrays.asList(
            KEY_SEMESTERS,
            KEY_THEME_COLOR,
            KEY_DARK_MODE,
            KEY_SELECTED_SEMESTER_ID
    ));
    private static final Set<String> REPEAT_RULE_VALUES = new HashSet<>(Arrays.asList(
            "", "仅单周", "仅双周"
    ));
    private static final Set<String> ASSESSMENT_METHOD_VALUES = new HashSet<>(Arrays.asList(
            "考试", "考察", "PnP"
    ));
    /** Key fragments that identify credentials or session state, regardless of nesting. */
    private static final List<String> SENSITIVE_KEY_FRAGMENTS = Arrays.asList(
            "password",
            "passwd",
            "pwd",
            "credential",
            "token",
            "cookie",
            "session",
            "authorization",
            "auth",
            "secret",
            "account",
            "username",
            "studentid",
            "userid",
            "identity",
            "sms",
            "captcha",
            "verification",
            "login"
    );

    private BackupContract() {}

    public static JSONObject createDocument(List<ScheduleModels.Course> courses,
                                            List<ScheduleModels.Semester> semesters,
                                            String selectedSemesterId,
                                            String themeColor,
                                            boolean darkMode,
                                            LocalDate exportDate) {
        JSONArray courseArray = new JSONArray();
        JSONArray semesterArray = new JSONArray();
        if (courses != null) {
            for (ScheduleModels.Course course : courses) {
                if (course != null) courseArray.put(course.json());
            }
        }
        if (semesters != null) {
            for (ScheduleModels.Semester semester : semesters) {
                if (semester != null) semesterArray.put(semester.json());
            }
        }
        return createDocument(courseArray, semesterArray, selectedSemesterId, themeColor,
                darkMode, exportDate);
    }

    private static JSONObject createDocument(JSONArray courses, JSONArray semesters,
                                             String selectedSemesterId, String themeColor,
                                             boolean darkMode, LocalDate exportDate) {
        JSONObject backup = new JSONObject();
        JSONObject settings = new JSONObject();
        try {
            settings.put(KEY_SEMESTERS, semesters == null ? new JSONArray() : copy(semesters));
            settings.put(KEY_THEME_COLOR,
                    themeColor == null ? ScheduleModels.DEFAULT_THEME_COLOR : themeColor);
            settings.put(KEY_DARK_MODE, darkMode);
            settings.put(KEY_SELECTED_SEMESTER_ID,
                    selectedSemesterId == null ? "" : selectedSemesterId);
            backup.put(KEY_FORMAT, FORMAT);
            backup.put(KEY_SCHEMA_VERSION, CURRENT_SCHEMA_VERSION);
            // Keep the old marker so v2.2.x tooling can identify the document.
            backup.put(KEY_VERSION, LEGACY_VERSION);
            backup.put(KEY_EXPORT_DATE, (exportDate == null ? today() : exportDate).toString());
            backup.put(KEY_COURSES, courses == null ? new JSONArray() : copy(courses));
            backup.put(KEY_SETTINGS, settings);
            // Export is a security boundary: reject any secret-bearing record before
            // the caller gets a file to write.
            rejectSensitiveKeys(backup);
            validateForImport(readDocument(backup));
            return backup;
        } catch (JSONException invalid) {
            throw new IllegalArgumentException(
                    "Backup data violates the portable contract", invalid);
        }
    }

    public static BackupData readDocument(JSONObject source) throws JSONException {
        if (source == null) throw new JSONException("Backup is empty");
        rejectSensitiveKeys(source);
        rejectUnknownKeys(source, TOP_LEVEL_KEYS, "backup");
        int schemaVersion;
        boolean legacy;
        if (source.has(KEY_SCHEMA_VERSION)) {
            String format = stringValue(source, KEY_FORMAT, "");
            if (!FORMAT.equals(format)) {
                throw new JSONException("Unsupported backup format: " + format);
            }
            schemaVersion = integerValue(source, KEY_SCHEMA_VERSION, -1);
            if (schemaVersion < CURRENT_SCHEMA_VERSION) {
                throw new JSONException("Missing or invalid backup schemaVersion");
            }
            if (schemaVersion > CURRENT_SCHEMA_VERSION) {
                throw new JSONException("Unsupported backup schemaVersion: " + schemaVersion);
            }
            String marker = stringValue(source, KEY_VERSION, LEGACY_VERSION);
            if (!LEGACY_VERSION.equals(marker)) {
                throw new JSONException("Unsupported backup version marker: " + marker);
            }
            legacy = false;
        } else {
            if (source.has(KEY_FORMAT)) {
                throw new JSONException("Backup format marker requires schemaVersion");
            }
            String version = stringValue(source, KEY_VERSION, "");
            if (!LEGACY_VERSION.equals(version)) {
                throw new JSONException("Unsupported legacy backup version: " + version);
            }
            schemaVersion = LEGACY_SCHEMA_VERSION;
            legacy = true;
        }

        JSONArray courses = source.optJSONArray(KEY_COURSES);
        JSONObject settings = source.optJSONObject(KEY_SETTINGS);
        if (courses == null || settings == null) {
            throw new JSONException("Backup must contain courses and settings");
        }
        rejectUnknownKeys(settings, SETTINGS_KEYS, "backup settings");
        if (!legacy && !settings.has(KEY_SEMESTERS)) {
            throw new JSONException("Current backup must contain settings.semesters");
        }
        JSONArray semesters = settings.optJSONArray(KEY_SEMESTERS);
        if (semesters == null) {
            if (legacy && !settings.has(KEY_SEMESTERS)) {
                semesters = new JSONArray();
            } else {
                throw new JSONException("Backup settings.semesters must be an array");
            }
        }
        String exportDate = stringValue(source, KEY_EXPORT_DATE, "");
        validateExportDate(exportDate);
        String selectedSemesterId = stringValue(settings, KEY_SELECTED_SEMESTER_ID, "");
        String themeColor = stringValue(settings, KEY_THEME_COLOR,
                ScheduleModels.DEFAULT_THEME_COLOR);
        boolean darkMode = booleanValue(settings, KEY_DARK_MODE, false);
        return new BackupData(schemaVersion, legacy, exportDate,
                copy(courses), copy(semesters), selectedSemesterId, themeColor, darkMode);
    }

    /** Validate all identifiers before an import can replace platform state. */
    public static void validateForImport(BackupData data) throws JSONException {
        if (data == null) throw new JSONException("Backup is empty");
        Set<String> semesterIds = new HashSet<>();
        for (int i = 0; i < data.semesters.length(); i++) {
            JSONObject semester = data.semesters.optJSONObject(i);
            if (semester == null) throw new JSONException("Backup contains an invalid semester");
            String id = requiredString(semester, "id", "semester");
            if (!semesterIds.add(id)) throw new JSONException("Duplicate semester id: " + id);
            validateSemesterFields(semester);
        }
        Set<String> courseIds = new HashSet<>();
        for (int i = 0; i < data.courses.length(); i++) {
            JSONObject course = data.courses.optJSONObject(i);
            if (course == null) throw new JSONException("Backup contains an invalid course");
            String id = requiredString(course, "id", "course");
            if (!courseIds.add(id)) throw new JSONException("Duplicate course id: " + id);
            String semesterId = requiredString(course, "semesterId", "course");
            if (!semesterIds.contains(semesterId)) {
                throw new JSONException("Course references missing semester: " + semesterId);
            }
            validateCourseFields(course);
            validateEnum(course, "assessmentMethod", "course", ASSESSMENT_METHOD_VALUES);
            JSONArray timeSlots = course.optJSONArray("timeSlots");
            if (course.has("timeSlots") && !course.isNull("timeSlots") && timeSlots == null) {
                throw new JSONException("Course timeSlots must be an array");
            }
            if (timeSlots != null) {
                for (int j = 0; j < timeSlots.length(); j++) {
                    JSONObject slot = timeSlots.optJSONObject(j);
                    if (slot == null) throw new JSONException("Backup contains an invalid time slot");
                    validateTimeSlotFields(slot);
                    validateEnum(slot, "repeatRule", "time slot", REPEAT_RULE_VALUES);
                }
            }
        }
        if (!data.selectedSemesterId.isEmpty() && !semesterIds.contains(data.selectedSemesterId)) {
            throw new JSONException("Selected semester does not exist: " + data.selectedSemesterId);
        }
    }

    private static String requiredString(JSONObject object, String key, String kind) throws JSONException {
        if (!object.has(key) || object.isNull(key)) {
            throw new JSONException("Missing " + kind + " " + key);
        }
        Object raw = object.opt(key);
        if (!(raw instanceof String)) {
            throw new JSONException("Non-string " + kind + " " + key);
        }
        String value = ((String) raw).trim();
        if (value.isEmpty()) throw new JSONException("Empty " + kind + " " + key);
        return value;
    }

    private static void validateOptionalString(JSONObject object, String key, String kind)
            throws JSONException {
        if (!object.has(key) || object.isNull(key)) return;
        if (!(object.opt(key) instanceof String)) {
            throw new JSONException("Non-string " + kind + " " + key);
        }
    }

    private static void validateSemesterFields(JSONObject semester) throws JSONException {
        validateOptionalString(semester, "name", "semester");
        validateOptionalString(semester, "startDate", "semester");
        validateOptionalString(semester, "endDate", "semester");
        validateOptionalDate(semester, "startDate", "semester");
        validateOptionalDate(semester, "endDate", "semester");
        validateOptionalInteger(semester, "weekCount", "semester", 1);
        validateOptionalInteger(semester, "sectionCount", "semester", 1);
        if (semester.has("sectionTimes") && semester.isNull("sectionTimes")) {
            throw new JSONException("Semester sectionTimes must be an array");
        }
        JSONArray sectionTimes = semester.optJSONArray("sectionTimes");
        if (semester.has("sectionTimes") && sectionTimes == null) {
            throw new JSONException("Semester sectionTimes must be an array");
        }
        if (sectionTimes == null) return;
        for (int i = 0; i < sectionTimes.length(); i++) {
            JSONObject time = sectionTimes.optJSONObject(i);
            if (time == null) throw new JSONException("Backup contains an invalid section time");
            validateRequiredTime(time, "start", "section time");
            validateRequiredTime(time, "end", "section time");
        }
    }

    private static void validateCourseFields(JSONObject course) throws JSONException {
        validateOptionalString(course, "name", "course");
        validateOptionalString(course, "code", "course");
        validateOptionalString(course, "location", "course");
        validateOptionalString(course, "teacher", "course");
        validateOptionalString(course, "notes", "course");
        validateOptionalString(course, "color", "course");
        validateOptionalNumber(course, "credits", "course");
    }

    private static void validateTimeSlotFields(JSONObject slot) throws JSONException {
        validateOptionalString(slot, "weekRange", "time slot");
        validateOptionalString(slot, "teacher", "time slot");
        validateOptionalString(slot, "location", "time slot");
        if (slot.has("dayOfWeek") && !slot.isNull("dayOfWeek")) {
            int day = integerValue(slot, "dayOfWeek", 0);
            if (day < 1 || day > 7) {
                throw new JSONException("Time slot dayOfWeek is out of range: " + day);
            }
        }
        if (slot.has("classSections") && slot.isNull("classSections")) {
            throw new JSONException("Time slot classSections must be an array");
        }
        JSONArray sections = slot.optJSONArray("classSections");
        if (slot.has("classSections") && sections == null) {
            throw new JSONException("Time slot classSections must be an array");
        }
        if (sections == null) return;
        for (int i = 0; i < sections.length(); i++) {
            Object raw = sections.opt(i);
            if (!(raw instanceof Number)) {
                throw new JSONException("Time slot classSections must contain integers");
            }
            double value = ((Number) raw).doubleValue();
            if (Double.isNaN(value) || Double.isInfinite(value)
                    || value != Math.rint(value) || value < 1 || value > Integer.MAX_VALUE) {
                throw new JSONException("Invalid time slot class section");
            }
        }
    }

    private static void validateOptionalDate(JSONObject object, String key, String kind)
            throws JSONException {
        if (!object.has(key) || object.isNull(key)) return;
        String value = object.optString(key, null);
        if (value == null || !value.matches("\\d{4}-\\d{2}-\\d{2}")) {
            throw new JSONException("Invalid " + kind + " " + key + ": " + value);
        }
        try {
            LocalDate.parse(value);
        } catch (Exception ignored) {
            throw new JSONException("Invalid " + kind + " " + key + ": " + value);
        }
    }

    private static void validateRequiredTime(JSONObject object, String key, String kind)
            throws JSONException {
        if (!object.has(key) || object.isNull(key) || !(object.opt(key) instanceof String)) {
            throw new JSONException("Missing or invalid " + kind + " " + key);
        }
        String value = (String) object.opt(key);
        if (!value.matches("\\d{2}:\\d{2}")) {
            throw new JSONException("Invalid " + kind + " " + key + ": " + value);
        }
        try {
            int hour = Integer.parseInt(value.substring(0, 2));
            int minute = Integer.parseInt(value.substring(3, 5));
            if (hour > 23 || minute > 59) throw new NumberFormatException();
        } catch (Exception ignored) {
            throw new JSONException("Invalid " + kind + " " + key + ": " + value);
        }
    }

    private static void validateOptionalInteger(JSONObject object, String key, String kind,
                                                int minimum) throws JSONException {
        if (!object.has(key) || object.isNull(key)) return;
        int value = integerValue(object, key, Integer.MIN_VALUE);
        if (value < minimum) throw new JSONException("Invalid " + kind + " " + key + ": " + value);
    }

    private static void validateOptionalNumber(JSONObject object, String key, String kind)
            throws JSONException {
        if (!object.has(key) || object.isNull(key)) return;
        Object raw = object.opt(key);
        if (!(raw instanceof Number)) throw new JSONException("Non-number " + kind + " " + key);
        double value = ((Number) raw).doubleValue();
        if (Double.isNaN(value) || Double.isInfinite(value) || value < 0) {
            throw new JSONException("Invalid " + kind + " " + key + ": " + value);
        }
    }

    private static void validateEnum(JSONObject object, String key, String kind,
                                     Set<String> allowed) throws JSONException {
        validateOptionalString(object, key, kind);
        if (!object.has(key) || object.isNull(key)) return;
        String value = object.optString(key, null);
        if (value == null || !allowed.contains(value)) {
            throw new JSONException("Unsupported " + kind + " " + key + ": " + value);
        }
    }

    private static String stringValue(JSONObject object, String key, String fallback)
            throws JSONException {
        if (!object.has(key) || object.isNull(key)) return fallback;
        Object raw = object.opt(key);
        if (!(raw instanceof String)) throw new JSONException("Non-string backup field: " + key);
        return (String) raw;
    }

    private static int integerValue(JSONObject object, String key, int fallback)
            throws JSONException {
        if (!object.has(key) || object.isNull(key)) return fallback;
        Object raw = object.opt(key);
        if (!(raw instanceof Number)) throw new JSONException("Non-integer backup field: " + key);
        double value = ((Number) raw).doubleValue();
        if (Double.isNaN(value) || Double.isInfinite(value) || value != Math.rint(value)
                || value < Integer.MIN_VALUE || value > Integer.MAX_VALUE) {
            throw new JSONException("Invalid integer backup field: " + key);
        }
        return ((Number) raw).intValue();
    }

    private static boolean booleanValue(JSONObject object, String key, boolean fallback)
            throws JSONException {
        if (!object.has(key) || object.isNull(key)) return fallback;
        Object raw = object.opt(key);
        if (!(raw instanceof Boolean)) throw new JSONException("Non-boolean backup field: " + key);
        return (Boolean) raw;
    }

    /** Convert legacy v2.0 documents and current documents to one canonical shape. */
    public static JSONObject migrateToCurrent(JSONObject source) throws JSONException {
        BackupData data = readDocument(source);
        validateForImport(data);
        return createDocument(data.courses, data.semesters, data.selectedSemesterId,
                data.themeColor, data.darkMode, parseDateOrToday(data.exportDate));
    }

    private static LocalDate parseDateOrToday(String value) throws JSONException {
        try {
            return value == null || value.isEmpty() ? today() : LocalDate.parse(value);
        } catch (Exception ignored) {
            throw new JSONException("Invalid backup exportDate: " + value);
        }
    }

    private static void validateExportDate(String value) throws JSONException {
        if (value == null || value.isEmpty()) return;
        parseDateOrToday(value);
    }

    private static void rejectUnknownKeys(JSONObject object, Set<String> allowed, String context)
            throws JSONException {
        Iterator<String> keys = object.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            if (!allowed.contains(key)) {
                throw new JSONException("Unsupported " + context + " field: " + key);
            }
        }
    }

    private static void rejectSensitiveKeys(Object value) throws JSONException {
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            Iterator<String> keys = object.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                if (isSensitiveKey(key)) {
                    throw new JSONException("Sensitive backup field is not portable: " + key);
                }
                Object child = object.opt(key);
                if (child instanceof JSONObject || child instanceof JSONArray) {
                    rejectSensitiveKeys(child);
                }
            }
        } else if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            for (int i = 0; i < array.length(); i++) {
                Object child = array.opt(i);
                if (child instanceof JSONObject || child instanceof JSONArray) {
                    rejectSensitiveKeys(child);
                }
            }
        }
    }

    private static boolean isSensitiveKey(String key) {
        String normalized = key.toLowerCase(Locale.ROOT).replace("_", "").replace("-", "");
        for (String fragment : SENSITIVE_KEY_FRAGMENTS) {
            if (normalized.contains(fragment)) return true;
        }
        return false;
    }

    public static LocalDate today() {
        return today(Clock.system(BUSINESS_ZONE));
    }

    static LocalDate today(Clock clock) {
        return LocalDate.now(clock.withZone(BUSINESS_ZONE));
    }

    private static JSONArray copy(JSONArray value) throws JSONException {
        return new JSONArray(value.toString());
    }

    public static final class BackupData {
        public final int schemaVersion;
        public final boolean legacy;
        public final String exportDate;
        public final JSONArray courses;
        public final JSONArray semesters;
        public final String selectedSemesterId;
        public final String themeColor;
        public final boolean darkMode;

        private BackupData(int schemaVersion, boolean legacy, String exportDate, JSONArray courses,
                           JSONArray semesters, String selectedSemesterId,
                           String themeColor, boolean darkMode) {
            this.schemaVersion = schemaVersion;
            this.legacy = legacy;
            this.exportDate = exportDate;
            this.courses = courses;
            this.semesters = semesters;
            this.selectedSemesterId = selectedSemesterId;
            this.themeColor = themeColor;
            this.darkMode = darkMode;
        }

    }
}
