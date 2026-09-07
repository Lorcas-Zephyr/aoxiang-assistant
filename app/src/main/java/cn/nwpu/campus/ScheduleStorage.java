package cn.nwpu.campus;

import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

public final class ScheduleStorage {
    private ScheduleStorage() {}

    public static final String KEY_SEMESTERS = "schedule_semesters";
    public static final String KEY_COURSES = "schedule_courses";
    public static final String KEY_SELECTED_SEMESTER = "schedule_selected_semester";
    public static final String KEY_THEME_COLOR = "schedule_theme_color";
    public static final String KEY_DARK_MODE = "schedule_dark_mode";

    public static List<ScheduleModels.Semester> loadSemesters(SharedPreferences store) {
        return loadSemestersResult(store).items;
    }

    public static LoadResult<ScheduleModels.Semester> loadSemestersResult(
            SharedPreferences store) {
        LocalDataStore.ReadResult raw = LocalDataStore.readArrayResult(store, KEY_SEMESTERS);
        if (!raw.success) return LoadResult.failure();
        List<ScheduleModels.Semester> semesters = new ArrayList<>();
        try {
            for (int i = 0; i < raw.items.length(); i++) {
                JSONObject item = raw.items.optJSONObject(i);
                if (item == null) return LoadResult.failure();
                semesters.add(ScheduleModels.Semester.from(item));
            }
            LocalDataStore.migrateIfLegacy(store, KEY_SEMESTERS, raw);
            return LoadResult.success(semesters);
        } catch (Exception ignored) {
            return LoadResult.failure();
        }
    }

    public static boolean saveSemesters(SharedPreferences store, List<ScheduleModels.Semester> semesters) {
        try {
            JSONArray array = new JSONArray();
            for (ScheduleModels.Semester semester : semesters) array.put(semester.json());
            return LocalDataStore.writeArray(store, KEY_SEMESTERS, array);
        } catch (Exception ignored) {
            return false;
        }
    }

    public static List<ScheduleModels.Course> loadCourses(SharedPreferences store) {
        return loadCoursesResult(store).items;
    }

    public static LoadResult<ScheduleModels.Course> loadCoursesResult(
            SharedPreferences store) {
        LocalDataStore.ReadResult raw = LocalDataStore.readArrayResult(store, KEY_COURSES);
        if (!raw.success) return LoadResult.failure();
        List<ScheduleModels.Course> courses = new ArrayList<>();
        try {
            for (int i = 0; i < raw.items.length(); i++) {
                JSONObject item = raw.items.optJSONObject(i);
                if (item == null) return LoadResult.failure();
                courses.add(ScheduleModels.Course.from(item));
            }
            LocalDataStore.migrateIfLegacy(store, KEY_COURSES, raw);
            return LoadResult.success(courses);
        } catch (Exception ignored) {
            return LoadResult.failure();
        }
    }

    public static boolean saveCourses(SharedPreferences store, List<ScheduleModels.Course> courses) {
        try {
            JSONArray array = new JSONArray();
            for (ScheduleModels.Course course : courses) array.put(course.json());
            return LocalDataStore.writeArray(store, KEY_COURSES, array);
        } catch (Exception ignored) {
            return false;
        }
    }

    /** Save the two related collections together after both current values are verified. */
    public static boolean saveSchedule(SharedPreferences store,
                                       List<ScheduleModels.Semester> semesters,
                                       List<ScheduleModels.Course> courses) {
        try {
            JSONArray semesterArray = new JSONArray();
            JSONArray courseArray = new JSONArray();
            for (ScheduleModels.Semester semester : semesters) semesterArray.put(semester.json());
            for (ScheduleModels.Course course : courses) courseArray.put(course.json());
            return LocalDataStore.writeArrays(store, KEY_SEMESTERS, semesterArray,
                    KEY_COURSES, courseArray);
        } catch (Exception ignored) {
            return false;
        }
    }

    /** Persist all schedule fields that form one user-visible edit as one commit. */
    public static boolean saveScheduleAndSettings(SharedPreferences store,
                                                  List<ScheduleModels.Semester> semesters,
                                                  List<ScheduleModels.Course> courses,
                                                  String selectedSemesterId,
                                                  String themeColor,
                                                  boolean darkMode) {
        try {
            JSONArray semesterArray = new JSONArray();
            JSONArray courseArray = new JSONArray();
            for (ScheduleModels.Semester semester : semesters) semesterArray.put(semester.json());
            for (ScheduleModels.Course course : courses) courseArray.put(course.json());
            return LocalDataStore.writeScheduleState(store,
                    KEY_SEMESTERS, semesterArray,
                    KEY_COURSES, courseArray,
                    KEY_SELECTED_SEMESTER, selectedSemesterId,
                    KEY_THEME_COLOR, themeColor,
                    KEY_DARK_MODE, darkMode);
        } catch (Exception ignored) {
            return false;
        }
    }

    /** Check that a paired schedule write cannot overwrite an unknown schema. */
    public static boolean canSaveSchedule(SharedPreferences store) {
        return LocalDataStore.canWriteArray(store, KEY_SEMESTERS)
                && LocalDataStore.canWriteArray(store, KEY_COURSES);
    }

    public static String loadSelectedSemester(SharedPreferences store) {
        return store.getString(KEY_SELECTED_SEMESTER, "");
    }

    public static boolean saveSelectedSemester(SharedPreferences store, String semesterId) {
        try {
            return store.edit()
                    .putString(KEY_SELECTED_SEMESTER, semesterId == null ? "" : semesterId)
                    .commit();
        } catch (Exception ignored) {
            return false;
        }
    }

    public static String loadThemeColor(SharedPreferences store) {
        return store.getString(KEY_THEME_COLOR, ScheduleModels.DEFAULT_THEME_COLOR);
    }

    public static boolean loadDarkMode(SharedPreferences store) {
        return store.getBoolean(KEY_DARK_MODE, false);
    }

    public static boolean saveTheme(SharedPreferences store, String color, boolean darkMode) {
        try {
            return store.edit()
                    .putString(KEY_THEME_COLOR, color)
                    .putBoolean(KEY_DARK_MODE, darkMode)
                    .commit();
        } catch (Exception ignored) {
            return false;
        }
    }

    public static final class LoadResult<T> {
        public final List<T> items;
        public final boolean success;

        private LoadResult(List<T> items, boolean success) {
            this.items = items;
            this.success = success;
        }

        private static <T> LoadResult<T> success(List<T> items) {
            return new LoadResult<>(items, true);
        }

        private static <T> LoadResult<T> failure() {
            return new LoadResult<>(new ArrayList<>(), false);
        }
    }
}
