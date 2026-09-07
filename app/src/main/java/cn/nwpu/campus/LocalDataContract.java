package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;

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
    private static final Set<String> ENVELOPE_KEYS = new HashSet<>(Arrays.asList(
            KEY_SCHEMA_VERSION, KEY_ITEMS
    ));

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
        rejectUnknownKeys(envelope);
        Object rawVersion = envelope.opt(KEY_SCHEMA_VERSION);
        if (!(rawVersion instanceof Number)) {
            throw new JSONException("Missing or invalid local data schemaVersion");
        }
        double numericVersion = ((Number) rawVersion).doubleValue();
        if (Double.isNaN(numericVersion) || Double.isInfinite(numericVersion)
                || numericVersion != Math.rint(numericVersion)
                || numericVersion < Integer.MIN_VALUE || numericVersion > Integer.MAX_VALUE) {
            throw new JSONException("Invalid local data schemaVersion");
        }
        int version = ((Number) rawVersion).intValue();
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

    private static void rejectUnknownKeys(JSONObject envelope) throws JSONException {
        Iterator<String> keys = envelope.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            if (!ENVELOPE_KEYS.contains(key)) {
                throw new JSONException("Unsupported local data envelope field: " + key);
            }
        }
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
