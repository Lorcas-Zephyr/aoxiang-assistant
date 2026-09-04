package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.SharedPreferences;

import org.json.JSONArray;
import org.junit.Test;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

public class LocalDataStoreTest {
    @Test public void readArrayFailsClosedWithoutReplacingAnUnexpectedPreferenceType() {
        MapBackedPreferences store = new MapBackedPreferences();
        store.values.put("grades", Boolean.TRUE);

        JSONArray result = LocalDataStore.readArray(store, "grades");

        assertEquals(0, result.length());
        assertEquals(Boolean.TRUE, store.values.get("grades"));
    }

    @Test public void ensureCurrentSkipsUnexpectedTypeAndStillMigratesOtherKeys() {
        MapBackedPreferences store = new MapBackedPreferences();
        store.values.put("grades", Integer.valueOf(7));
        store.values.put(ScheduleStorage.KEY_SEMESTERS, "[]");

        LocalDataStore.ensureCurrent(store);

        assertEquals(Integer.valueOf(7), store.values.get("grades"));
        assertTrue(store.values.get(ScheduleStorage.KEY_SEMESTERS)
                .toString().contains("\"schemaVersion\":1"));
    }

    @Test public void canWriteArrayRejectsUnexpectedPreferenceType() {
        MapBackedPreferences store = new MapBackedPreferences();
        store.values.put("grades", Collections.singleton("not-a-json-string"));

        assertFalse(LocalDataStore.canWriteArray(store, "grades"));
        assertEquals(Collections.singleton("not-a-json-string"), store.values.get("grades"));
    }

    private static final class MapBackedPreferences implements SharedPreferences {
        private final Map<String, Object> values = new HashMap<>();

        @Override public Map<String, ?> getAll() {
            return new HashMap<>(values);
        }

        @Override public String getString(String key, String defValue) {
            Object value = values.get(key);
            if (value == null) return defValue;
            if (!(value instanceof String)) throw new ClassCastException(key);
            return (String) value;
        }

        @Override public Set<String> getStringSet(String key, Set<String> defValues) {
            Object value = values.get(key);
            if (value == null) return defValues;
            if (!(value instanceof Set)) throw new ClassCastException(key);
            @SuppressWarnings("unchecked")
            Set<String> result = (Set<String>) value;
            return result;
        }

        @Override public int getInt(String key, int defValue) {
            Object value = values.get(key);
            if (value == null) return defValue;
            if (!(value instanceof Integer)) throw new ClassCastException(key);
            return (Integer) value;
        }

        @Override public long getLong(String key, long defValue) {
            Object value = values.get(key);
            if (value == null) return defValue;
            if (!(value instanceof Long)) throw new ClassCastException(key);
            return (Long) value;
        }

        @Override public float getFloat(String key, float defValue) {
            Object value = values.get(key);
            if (value == null) return defValue;
            if (!(value instanceof Float)) throw new ClassCastException(key);
            return (Float) value;
        }

        @Override public boolean getBoolean(String key, boolean defValue) {
            Object value = values.get(key);
            if (value == null) return defValue;
            if (!(value instanceof Boolean)) throw new ClassCastException(key);
            return (Boolean) value;
        }

        @Override public boolean contains(String key) {
            return values.containsKey(key);
        }

        @Override public Editor edit() {
            return new Editor() {
                private final Map<String, Object> pending = new HashMap<>();
                private boolean clear;

                @Override public Editor putString(String key, String value) {
                    pending.put(key, value);
                    return this;
                }

                @Override public Editor putStringSet(String key, Set<String> value) {
                    pending.put(key, value);
                    return this;
                }

                @Override public Editor putInt(String key, int value) {
                    pending.put(key, value);
                    return this;
                }

                @Override public Editor putLong(String key, long value) {
                    pending.put(key, value);
                    return this;
                }

                @Override public Editor putFloat(String key, float value) {
                    pending.put(key, value);
                    return this;
                }

                @Override public Editor putBoolean(String key, boolean value) {
                    pending.put(key, value);
                    return this;
                }

                @Override public Editor remove(String key) {
                    pending.put(key, null);
                    return this;
                }

                @Override public Editor clear() {
                    clear = true;
                    return this;
                }

                @Override public boolean commit() {
                    applyChanges();
                    return true;
                }

                @Override public void apply() {
                    applyChanges();
                }

                private void applyChanges() {
                    if (clear) values.clear();
                    for (Map.Entry<String, Object> entry : pending.entrySet()) {
                        if (entry.getValue() == null) values.remove(entry.getKey());
                        else values.put(entry.getKey(), entry.getValue());
                    }
                }
            };
        }

        @Override public void registerOnSharedPreferenceChangeListener(
                OnSharedPreferenceChangeListener listener) {}

        @Override public void unregisterOnSharedPreferenceChangeListener(
                OnSharedPreferenceChangeListener listener) {}
    }
}
