package cn.nwpu.campus;

import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** JSON storage and date-range helpers for {@link ManualEvent}. */
public final class ManualEventStore {
    public static final String KEY_EVENTS = "manual_events_v1";

    private ManualEventStore() {}

    public static List<ManualEvent> load(SharedPreferences store) {
        List<ManualEvent> events = new ArrayList<>();
        try {
            String raw = store.getString(KEY_EVENTS, "");
            if (raw == null || raw.isEmpty()) return events;
            JSONArray array = new JSONArray(raw);
            for (int i = 0; i < array.length(); i++) {
                ManualEvent event = ManualEvent.from(array.optJSONObject(i));
                if (event != null) events.add(event);
            }
        } catch (Exception ignored) {}
        sort(events);
        return events;
    }

    public static void save(SharedPreferences store, List<ManualEvent> events) {
        try {
            JSONArray array = new JSONArray();
            if (events != null) {
                for (ManualEvent event : events) {
                    if (event != null) array.put(event.json());
                }
            }
            store.edit().putString(KEY_EVENTS, array.toString()).apply();
        } catch (Exception ignored) {}
    }

    public static JSONArray toJson(List<ManualEvent> events) {
        JSONArray array = new JSONArray();
        if (events != null) {
            for (ManualEvent event : events) {
                if (event != null) array.put(event.json());
            }
        }
        return array;
    }

    public static List<ManualEvent> fromJson(JSONArray array) {
        List<ManualEvent> events = new ArrayList<>();
        if (array != null) {
            for (int i = 0; i < array.length(); i++) {
                ManualEvent event = ManualEvent.from(array.optJSONObject(i));
                if (event != null) events.add(event);
            }
        }
        sort(events);
        return events;
    }

    public static List<ManualEvent> onDate(List<ManualEvent> events, LocalDate date) {
        List<ManualEvent> result = new ArrayList<>();
        if (events == null || date == null) return result;
        for (ManualEvent event : events) {
            if (event != null && event.occursOn(date)) result.add(event);
        }
        sort(result);
        return result;
    }

    public static List<ManualEvent> between(List<ManualEvent> events, LocalDate start, LocalDate end) {
        List<ManualEvent> result = new ArrayList<>();
        if (events == null || start == null || end == null) return result;
        for (ManualEvent event : events) {
            if (event == null) continue;
            LocalDate cursor = start;
            while (!cursor.isAfter(end)) {
                if (event.occursOn(cursor)) {
                    result.add(event);
                    break;
                }
                cursor = cursor.plusDays(1);
            }
        }
        sort(result);
        return result;
    }

    public static void sort(List<ManualEvent> events) {
        if (events == null) return;
        Collections.sort(events, new Comparator<ManualEvent>() {
            @Override
            public int compare(ManualEvent first, ManualEvent second) {
                int byDate = first.date.compareTo(second.date);
                if (byDate != 0) return byDate;
                LocalTime left = first.localStartTime();
                LocalTime right = second.localStartTime();
                return left.compareTo(right);
            }
        });
    }
}
