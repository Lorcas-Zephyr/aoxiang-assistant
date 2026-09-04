package cn.nwpu.campus;

import android.content.SharedPreferences;

import org.json.JSONArray;

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
        migrateKey(store, key);
        try {
            LocalDataContract.DecodedArray decoded = LocalDataContract.decodeArray(
                    store.getString(key, ""));
            return decoded.items;
        } catch (Exception ignored) {
            return new JSONArray();
        }
    }

    static boolean writeArray(SharedPreferences store, String key, JSONArray items) {
        if (!canWriteArray(store, key)) return false;
        store.edit()
                .putString(key, LocalDataContract.encodeArray(items))
                .apply();
        return true;
    }

    static boolean writeArrays(SharedPreferences store, String firstKey, JSONArray firstItems,
                               String secondKey, JSONArray secondItems) {
        if (!canWriteArray(store, firstKey) || !canWriteArray(store, secondKey)) {
            return false;
        }
        store.edit()
                .putString(firstKey, LocalDataContract.encodeArray(firstItems))
                .putString(secondKey, LocalDataContract.encodeArray(secondItems))
                .apply();
        return true;
    }

    static boolean canWriteArray(SharedPreferences store, String key) {
        try {
            return LocalDataContract.canSafelyReplace(store.getString(key, ""));
        } catch (Exception ignored) {
            return false;
        }
    }

    static void ensureCurrent(SharedPreferences store) {
        for (String key : ARRAY_KEYS) migrateKey(store, key);
    }

    private static void migrateKey(SharedPreferences store, String key) {
        final String raw;
        try {
            // SharedPreferences throws when a legacy caller stored this key with
            // a non-String type. Treat that value as opaque and leave it intact.
            raw = store.getString(key, "");
        } catch (Exception ignored) {
            return;
        }
        if (raw == null || raw.trim().isEmpty()) return;
        try {
            LocalDataContract.DecodedArray decoded = LocalDataContract.decodeArray(raw);
            if (decoded.legacy) {
                store.edit()
                        .putString(key, LocalDataContract.encodeArray(decoded.items))
                        .apply();
            }
        } catch (Exception ignored) {
            // Keep malformed or future-version data untouched for recovery.
        }
    }
}
