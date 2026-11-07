package cn.nwpu.campus;

import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * 考试安排存储与展示辅助。
 *
 * 考试数据随课表采集一并读取（getExamInfos），按归一化行保存。展示时把考试
 * 转换为 id 以 {@link #EXAM_ID_PREFIX} 开头的虚拟课程对象，复用现有课表渲染
 * 管线；虚拟课程不进入本地课程存储，仅在各读取点临时注入。
 */
public final class ExamStorage {
    public static final String KEY_EXAMS = "schedule_exams";
    public static final String SHOW_EXAMS_KEY = "schedule_show_exams";
    public static final String EXAM_ID_PREFIX = "exam-";
    /** 考试块的固定强调色，与课程预设色板中的红色一致。 */
    public static final String EXAM_COLOR = "#E53935";

    private ExamStorage() {}

    public static boolean showExams(SharedPreferences store) {
        return store.getBoolean(SHOW_EXAMS_KEY, true);
    }

    public static List<ScheduleModels.Exam> load(SharedPreferences store) {
        List<ScheduleModels.Exam> exams = new ArrayList<>();
        try {
            String raw = store.getString(KEY_EXAMS, "");
            if (raw == null || raw.isEmpty()) return exams;
            JSONArray array = new JSONArray(raw);
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONObject(i);
                if (item != null) exams.add(ScheduleModels.Exam.from(item));
            }
        } catch (Exception ignored) {}
        return exams;
    }

    public static void save(SharedPreferences store, List<ScheduleModels.Exam> exams) {
        try {
            JSONArray array = new JSONArray();
            for (ScheduleModels.Exam exam : exams) array.put(exam.json());
            store.edit().putString(KEY_EXAMS, array.toString()).apply();
        } catch (Exception ignored) {}
    }

    /**
     * 把采集解析得到的归一化考试行写入存储。行结构与 {@code PortalApiParsers.examRows}
     * 的输出一致；semesterId 由调用方按采集学期补齐。
     */
    public static void saveRows(SharedPreferences store, JSONArray rows, String semesterId) {
        if (rows == null) return;
        List<ScheduleModels.Exam> exams = new ArrayList<>();
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.optJSONObject(i);
            if (row == null) continue;
            ScheduleModels.Exam exam = ScheduleModels.Exam.from(row);
            if (exam.name.isEmpty() || exam.date.isEmpty()) continue;
            exam.semesterId = semesterId == null ? "" : semesterId;
            exams.add(exam);
        }
        save(store, exams);
    }

    /** 按日期与开始时间升序排列考试，供列表展示。 */
    public static List<ScheduleModels.Exam> sorted(List<ScheduleModels.Exam> exams) {
        List<ScheduleModels.Exam> out = new ArrayList<>(exams);
        out.sort(java.util.Comparator.comparing((ScheduleModels.Exam exam) -> exam.date)
                .thenComparing(exam -> exam.startTime));
        return out;
    }

    /**
     * 考试覆盖的最大教学周号（对学期开始日推算，可能超过学期 weekCount，
     * 因为课表导入的学期结束日期取最后一门课）。无考试或无法推算时返回 0。
     */
    public static int maxExamWeek(List<ScheduleModels.Exam> exams,
                                  ScheduleModels.Semester semester) {
        if (semester == null) return 0;
        int max = 0;
        for (ScheduleModels.Exam exam : exams) {
            LocalDate date = parseDate(exam.date);
            if (date == null) continue;
            max = Math.max(max, ScheduleUtils.weekNumberForDate(date, semester));
        }
        return max;
    }

    /** 最晚一场考试的日期，供月历放宽翻页范围；无考试时返回 null。 */
    public static LocalDate lastExamDate(List<ScheduleModels.Exam> exams) {
        LocalDate last = null;
        for (ScheduleModels.Exam exam : exams) {
            LocalDate date = parseDate(exam.date);
            if (date != null && (last == null || date.isAfter(last))) last = date;
        }
        return last;
    }

    public static List<ScheduleModels.Exam> examsOnDate(List<ScheduleModels.Exam> exams,
                                                        LocalDate date) {
        List<ScheduleModels.Exam> out = new ArrayList<>();
        if (date == null) return out;
        for (ScheduleModels.Exam exam : exams) {
            LocalDate examDate = parseDate(exam.date);
            if (date.equals(examDate)) out.add(exam);
        }
        return out;
    }

    /** 把指定日期的考试转换为虚拟课程，供课表周视图、月历、今日卡片与小组件注入。 */
    public static List<ScheduleModels.Course> examCoursesOnDate(List<ScheduleModels.Exam> exams,
                                                                LocalDate date,
                                                                ScheduleModels.Semester semester) {
        List<ScheduleModels.Course> out = new ArrayList<>();
        for (ScheduleModels.Exam exam : examsOnDate(exams, date)) {
            ScheduleModels.Course course = examAsCourse(exam, semester);
            if (course != null) out.add(course);
        }
        return out;
    }

    /**
     * 考试虚拟课程：单时间槽、考试周次、固定考试色。semesterId 取展示学期，
     * 保证各消费点按 semesterId 过滤时能命中；周次超出学期范围时返回 null，
     * 避免跨学期显示。考试详情经 notes 中的 JSON 还原。
     */
    public static ScheduleModels.Course examAsCourse(ScheduleModels.Exam exam,
                                                     ScheduleModels.Semester semester) {
        if (exam == null || semester == null) return null;
        LocalDate date = parseDate(exam.date);
        if (date == null) return null;
        int week = ScheduleUtils.weekNumberForDate(date, semester);
        if (week < 1) return null;
        List<Integer> sections = examSections(semester, exam, date);
        if (sections.isEmpty()) sections.add(1);
        ScheduleModels.TimeSlot slot = new ScheduleModels.TimeSlot(
                String.valueOf(week), ScheduleModels.RepeatRule.ALL,
                date.getDayOfWeek().getValue(), sections, null, exam.location);
        ScheduleModels.Course course = new ScheduleModels.Course(
                EXAM_ID_PREFIX + exam.date + "-" + exam.name,
                "考试·" + exam.name, semester.id,
                java.util.Collections.singletonList(slot));
        course.location = exam.location;
        course.color = EXAM_COLOR;
        course.notes = exam.json().toString();
        return course;
    }

    public static boolean isExamCourse(ScheduleModels.Course course) {
        return course != null && course.id != null && course.id.startsWith(EXAM_ID_PREFIX);
    }

    /** 从虚拟课程还原考试详情；notes 缺失或损坏时返回 null。 */
    public static ScheduleModels.Exam examFromCourse(ScheduleModels.Course course) {
        if (!isExamCourse(course) || course.notes == null || course.notes.isEmpty()) return null;
        try {
            return ScheduleModels.Exam.from(new JSONObject(course.notes));
        } catch (Exception ignored) {
            return null;
        }
    }

    /**
     * 把考试时间映射到节次区间：开始时间落在 [start, end) 的节次为起点，
     * 结束时间按同样的规则取终点，起点大于终点时以起点为准；无法精确命中时
     * 取时间距离最近的节次。考试未给出时间时返回空列表，由调用方兜底。
     */
    static List<Integer> examSections(ScheduleModels.Semester semester, ScheduleModels.Exam exam,
                                      LocalDate date) {
        List<Integer> out = new ArrayList<>();
        LocalTime start = parseTime(exam.startTime);
        if (start == null) return out;
        LocalTime end = parseTime(exam.endTime);
        int sectionCount = semester.sectionTimes.size();
        int startSection = 0;
        int endSection = 0;
        int nearestStart = 1;
        long nearestStartGap = Long.MAX_VALUE;
        for (int section = 1; section <= sectionCount; section++) {
            ScheduleModels.SectionTime time = ScheduleModels.sectionTimeFor(
                    semester, exam.location, date, section);
            if (time == null) continue;
            LocalTime from = parseTime(time.start);
            LocalTime to = parseTime(time.end);
            if (from == null || to == null) continue;
            if (startSection == 0 && !start.isBefore(from) && start.isBefore(to)) startSection = section;
            if (startSection == 0) {
                long gap = gapMinutes(start, from, to);
                if (gap < nearestStartGap) {
                    nearestStartGap = gap;
                    nearestStart = section;
                }
            }
            if (end != null && endSection == 0 && !end.isBefore(to) && end.isAfter(from)) {
                endSection = section;
            }
        }
        out.add(startSection > 0 ? startSection : nearestStart);
        if (end != null && endSection > 0 && endSection > out.get(0)) out.add(endSection);
        if (out.size() == 2) {
            List<Integer> span = new ArrayList<>();
            for (int section = out.get(0); section <= out.get(1); section++) span.add(section);
            return span;
        }
        return out;
    }

    /** 时间在节次之前取与节次开始的距离，之后取与节次结束的距离，中间取 0。 */
    private static long gapMinutes(LocalTime time, LocalTime from, LocalTime to) {
        if (!time.isBefore(from) && !time.isAfter(to)) return 0;
        return time.isBefore(from)
                ? java.time.Duration.between(time, from).toMinutes()
                : java.time.Duration.between(to, time).toMinutes();
    }

    private static LocalDate parseDate(String value) {
        try {
            return LocalDate.parse(value, DateTimeFormatter.ofPattern("uuuu-MM-dd"));
        } catch (Exception ignored) {
            return null;
        }
    }

    private static LocalTime parseTime(String value) {
        try {
            String cleaned = value == null ? "" : value.trim();
            if (cleaned.isEmpty()) return null;
            if (cleaned.length() >= 8) cleaned = cleaned.substring(0, 5);
            return LocalTime.parse(cleaned, DateTimeFormatter.ofPattern("HH:mm"));
        } catch (Exception ignored) {
            return null;
        }
    }
}
