package cn.nwpu.campus;

import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

/** Android adapter for the versioned local JSON contract. */
final class LocalDataStore {
    static final String PREFERENCES_NAME = "campus_private";

    private static final String[] ARRAY_KEYS = {
            "grades",
            ScheduleStorage.KEY_SEMESTERS,
            ScheduleStorage.KEY_COURSES
    };

    private LocalDataStore() {}

    static JSONArray readArray(SharedPreferences store, String key) {
        return readArrayResult(store, key).items;
    }

    static ReadResult readArrayResult(SharedPreferences store, String key) {
        try {
            LocalDataContract.DecodedArray decoded = LocalDataContract.decodeArray(
                    store.getString(key, ""));
            return ReadResult.success(decoded.items, decoded.legacy);
        } catch (Exception ignored) {
            return ReadResult.failure();
        }
    }

    static boolean writeArray(SharedPreferences store, String key, JSONArray items) {
        if (!canWriteArray(store, key)) return false;
        JSONArray value = items == null ? new JSONArray() : items;
        if (!validateItemsForKey(key, value)) return false;
        try {
            return store.edit()
                    .putString(key, LocalDataContract.encodeArray(value))
                    .commit();
        } catch (Exception ignored) {
            return false;
        }
    }

    /** Persist grades and the GPA derived from the same refresh as one state change. */
    static boolean writeGradeState(SharedPreferences store,
                                   String gradesKey, JSONArray grades,
                                   String gpaKey, double gpa) {
        if (!canWriteArray(store, gradesKey)) return false;
        JSONArray gradeValue = grades == null ? new JSONArray() : grades;
        if (!validateItemsForKey(gradesKey, gradeValue) || Double.isInfinite(gpa)) {
            return false;
        }
        try {
            SharedPreferences.Editor editor = store.edit()
                    .putString(gradesKey, LocalDataContract.encodeArray(gradeValue));
            if (Double.isNaN(gpa)) editor.remove(gpaKey);
            else editor.putString(gpaKey, Double.toString(gpa));
            return editor.commit();
        } catch (Exception ignored) {
            return false;
        }
    }

    static boolean writeArrays(SharedPreferences store, String firstKey, JSONArray firstItems,
                               String secondKey, JSONArray secondItems) {
        if (!canWriteArray(store, firstKey) || !canWriteArray(store, secondKey)) {
            return false;
        }
        JSONArray firstValue = firstItems == null ? new JSONArray() : firstItems;
        JSONArray secondValue = secondItems == null ? new JSONArray() : secondItems;
        if (!validateItemsForKey(firstKey, firstValue)
                || !validateItemsForKey(secondKey, secondValue)) return false;
        try {
            return store.edit()
                    .putString(firstKey, LocalDataContract.encodeArray(firstValue))
                    .putString(secondKey, LocalDataContract.encodeArray(secondValue))
                    .commit();
        } catch (Exception ignored) {
            return false;
        }
    }

    static boolean writeScheduleState(SharedPreferences store,
                                      String semestersKey, JSONArray semesters,
                                      String coursesKey, JSONArray courses,
                                      String selectedSemesterKey, String selectedSemesterId,
                                      String themeKey, String themeColor,
                                      String darkModeKey, boolean darkMode) {
        if (!canWriteArray(store, semestersKey) || !canWriteArray(store, coursesKey)) {
            return false;
        }
        JSONArray semesterValue = semesters == null ? new JSONArray() : semesters;
        JSONArray courseValue = courses == null ? new JSONArray() : courses;
        if (!validateItemsForKey(semestersKey, semesterValue)
                || !validateItemsForKey(coursesKey, courseValue)) return false;
        try {
            return store.edit()
                    .putString(semestersKey, LocalDataContract.encodeArray(semesterValue))
                    .putString(coursesKey, LocalDataContract.encodeArray(courseValue))
                    .putString(selectedSemesterKey, selectedSemesterId == null ? "" : selectedSemesterId)
                    .putString(themeKey, themeColor)
                    .putBoolean(darkModeKey, darkMode)
                    .commit();
        } catch (Exception ignored) {
            return false;
        }
    }

    static boolean canWriteArray(SharedPreferences store, String key) {
        try {
            String raw = store.getString(key, "");
            if (raw == null || raw.trim().isEmpty()) return true;
            ReadResult decoded = readArrayResult(store, key);
            return decoded.success
                    && (!decoded.legacy || decoded.items.length() == 0)
                    && validateItemsForKey(key, decoded.items);
        } catch (Exception ignored) {
            return false;
        }
    }

    static void ensureCurrent(SharedPreferences store) {
        for (String key : ARRAY_KEYS) migrateKey(store, key);
    }

    private static void migrateKey(SharedPreferences store, String key) {
        migrateIfLegacy(store, key, readArrayResult(store, key));
    }

    /** Migrate only after the caller has a fully decoded and domain-valid collection. */
    static boolean migrateIfLegacy(SharedPreferences store, String key, ReadResult result) {
        if (result == null || !result.success) return false;
        if (!result.legacy) return true;
        try {
            // Re-read before committing so a concurrent writer is never replaced by a
            // stale snapshot from an earlier decode.
            String raw = store.getString(key, "");
            if (raw == null || raw.trim().isEmpty()) return true;
            LocalDataContract.DecodedArray current = LocalDataContract.decodeArray(raw);
            if (!current.legacy) return true;
            if (!validateItemsForKey(key, current.items)) return false;
            return store.edit()
                    .putString(key, LocalDataContract.encodeArray(current.items))
                    .commit();
        } catch (Exception ignored) {
            // Keep malformed, future-version, or failed-commit data untouched.
            return false;
        }
    }

    private static boolean validateItemsForKey(String key, JSONArray items) {
        if (items == null) return false;
        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.optJSONObject(i);
            if (item == null) return false;
            try {
                if (ScheduleStorage.KEY_SEMESTERS.equals(key)) {
                    ScheduleModels.Semester.from(item);
                } else if (ScheduleStorage.KEY_COURSES.equals(key)) {
                    ScheduleModels.Course.from(item);
                } else if ("grades".equals(key)) {
                    if (!validGradeItem(item)) return false;
                }
            } catch (Exception ignored) {
                return false;
            }
        }
        return true;
    }

    private static boolean validGradeItem(JSONObject item) {
        if (!item.has("course") || item.isNull("course")
                || !(item.opt("course") instanceof String)
                || ((String) item.opt("course")).trim().isEmpty()) return false;
        return optionalString(item, "category")
                && optionalString(item, "detail")
                && optionalNumber(item, "credits")
                && optionalNumber(item, "point")
                && optionalNumber(item, "score");
    }

    private static boolean optionalString(JSONObject item, String key) {
        return !item.has(key) || item.isNull(key) || item.opt(key) instanceof String;
    }

    private static boolean optionalNumber(JSONObject item, String key) {
        if (!item.has(key) || item.isNull(key)) return true;
        Object value = item.opt(key);
        if (!(value instanceof Number)) return false;
        double number = ((Number) value).doubleValue();
        return !Double.isNaN(number) && !Double.isInfinite(number);
    }

    static final class ReadResult {
        final JSONArray items;
        final boolean success;
        final boolean legacy;

        private ReadResult(JSONArray items, boolean success, boolean legacy) {
            this.items = items;
            this.success = success;
            this.legacy = legacy;
        }

        static ReadResult success(JSONArray items, boolean legacy) {
            return new ReadResult(items, true, legacy);
        }

        static ReadResult failure() {
            return new ReadResult(new JSONArray(), false, false);
        }
    }
}
