package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Versioned JSON primitives used by local storage.
 *
 * <p>The first released storage shape was a bare JSON array. It remains a
 * supported legacy input (schema 0); new writes use an object envelope so a
 * future migration can be explicit instead of inferred from application code.
 */
public final class LocalDataContract {
    public static final int LEGACY_SCHEMA_VERSION = 0;
    public static final int CURRENT_SCHEMA_VERSION = 1;
    public static final String KEY_SCHEMA_VERSION = "schemaVersion";
    public static final String KEY_ITEMS = "items";

    private LocalDataContract() {}

    public static String encodeArray(JSONArray items) {
        JSONObject envelope = new JSONObject();
        try {
            envelope.put(KEY_SCHEMA_VERSION, CURRENT_SCHEMA_VERSION);
            envelope.put(KEY_ITEMS, items == null ? new JSONArray() : items);
        } catch (JSONException impossible) {
            throw new IllegalStateException("Unable to encode local data", impossible);
        }
        return envelope.toString();
    }

    public static DecodedArray decodeArray(String raw) throws JSONException {
        if (raw == null || raw.trim().isEmpty()) {
            return new DecodedArray(LEGACY_SCHEMA_VERSION, new JSONArray(), true);
        }
        String value = raw.trim();
        if (value.startsWith("[")) {
            return new DecodedArray(LEGACY_SCHEMA_VERSION, new JSONArray(value), true);
        }

        JSONObject envelope = new JSONObject(value);
        int version = envelope.optInt(KEY_SCHEMA_VERSION, -1);
        if (version < CURRENT_SCHEMA_VERSION) {
            throw new JSONException("Missing or invalid local data schemaVersion");
        }
        if (version > CURRENT_SCHEMA_VERSION) {
            throw new JSONException("Unsupported local data schemaVersion: " + version);
        }
        JSONArray items = envelope.optJSONArray(KEY_ITEMS);
        if (items == null) {
            throw new JSONException("Local data envelope is missing items");
        }
        return new DecodedArray(version, items, false);
    }

    /** True only when writing a current value cannot erase an unknown local shape. */
    public static boolean canSafelyReplace(String raw) {
        if (raw == null || raw.trim().isEmpty()) return true;
        try {
            decodeArray(raw);
            return true;
        } catch (JSONException ignored) {
            return false;
        }
    }

    public static final class DecodedArray {
        public final int sourceVersion;
        public final JSONArray items;
        public final boolean legacy;

        private DecodedArray(int sourceVersion, JSONArray items, boolean legacy) {
            this.sourceVersion = sourceVersion;
            this.items = items;
            this.legacy = legacy;
        }
    }
}
