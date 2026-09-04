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
        List<ScheduleModels.Semester> semesters = new ArrayList<>();
        try {
            JSONArray array = LocalDataStore.readArray(store, KEY_SEMESTERS);
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONObject(i);
                if (item != null) semesters.add(ScheduleModels.Semester.from(item));
            }
        } catch (Exception ignored) {}
        return semesters;
    }

    public static void saveSemesters(SharedPreferences store, List<ScheduleModels.Semester> semesters) {
        try {
            JSONArray array = new JSONArray();
            for (ScheduleModels.Semester semester : semesters) array.put(semester.json());
            LocalDataStore.writeArray(store, KEY_SEMESTERS, array);
        } catch (Exception ignored) {}
    }

    public static List<ScheduleModels.Course> loadCourses(SharedPreferences store) {
        List<ScheduleModels.Course> courses = new ArrayList<>();
        try {
            JSONArray array = LocalDataStore.readArray(store, KEY_COURSES);
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONObject(i);
                if (item != null) courses.add(ScheduleModels.Course.from(item));
            }
        } catch (Exception ignored) {}
        return courses;
    }

    public static void saveCourses(SharedPreferences store, List<ScheduleModels.Course> courses) {
        try {
            JSONArray array = new JSONArray();
            for (ScheduleModels.Course course : courses) array.put(course.json());
            LocalDataStore.writeArray(store, KEY_COURSES, array);
        } catch (Exception ignored) {}
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

    /** Check that a paired schedule write cannot overwrite an unknown schema. */
    public static boolean canSaveSchedule(SharedPreferences store) {
        return LocalDataStore.canWriteArray(store, KEY_SEMESTERS)
                && LocalDataStore.canWriteArray(store, KEY_COURSES);
    }

    public static String loadSelectedSemester(SharedPreferences store) {
        return store.getString(KEY_SELECTED_SEMESTER, "");
    }

    public static void saveSelectedSemester(SharedPreferences store, String semesterId) {
        store.edit().putString(KEY_SELECTED_SEMESTER, semesterId == null ? "" : semesterId).apply();
    }

    public static String loadThemeColor(SharedPreferences store) {
        return store.getString(KEY_THEME_COLOR, ScheduleModels.DEFAULT_THEME_COLOR);
    }

    public static boolean loadDarkMode(SharedPreferences store) {
        return store.getBoolean(KEY_DARK_MODE, false);
    }

    public static void saveTheme(SharedPreferences store, String color, boolean darkMode) {
        store.edit()
                .putString(KEY_THEME_COLOR, color)
                .putBoolean(KEY_DARK_MODE, darkMode)
                .apply();
    }
}
