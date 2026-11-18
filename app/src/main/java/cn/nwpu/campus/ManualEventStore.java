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

/** 手动日程的本地存取和日期计算。只读写 SharedPreferences，不碰网络。 */
public final class ManualEventStore {
    public static final String KEY_EVENTS = "manual_events_v1";

    private ManualEventStore() {}

    /** 读取全部日程；没有数据或 JSON 损坏时返回空列表。 */
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

    /** 覆盖保存全部日程。 */
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

    /** 取某一天会发生的日程，按开始时间排序。 */
    public static List<ManualEvent> onDate(List<ManualEvent> events, LocalDate date) {
        List<ManualEvent> result = new ArrayList<>();
        if (events == null || date == null) return result;
        for (ManualEvent event : events) {
            if (event != null && event.occursOn(date)) result.add(event);
        }
        sort(result);
        return result;
    }

    /** 取日期范围内的日程；每周重复的日程会出现多次。 */
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

    /** 按开始时间排序，编辑页和课表共用。 */
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
