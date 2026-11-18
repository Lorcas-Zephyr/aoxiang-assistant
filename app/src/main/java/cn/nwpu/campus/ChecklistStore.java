package cn.nwpu.campus;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** 清单的本地存取和提醒标记。清单存一个 JSON 数组，已提醒标记单独存 key。 */
public final class ChecklistStore {
    public static final String KEY_CHECKLISTS = "checklists_v1";
    private static final String REMINDER_PREFIX = "checklist_reminded_";

    private ChecklistStore() {}

    /** 读取全部清单；没有数据或 JSON 损坏时返回空列表。 */
    public static List<Checklist> load(SharedPreferences store) {
        List<Checklist> values = new ArrayList<>();
        try {
            String raw = store.getString(KEY_CHECKLISTS, "");
            if (raw == null || raw.isEmpty()) return values;
            JSONArray array = new JSONArray(raw);
            for (int i = 0; i < array.length(); i++) {
                Checklist checklist = Checklist.from(array.optJSONObject(i));
                if (checklist != null) values.add(checklist);
            }
        } catch (Exception ignored) {}
        sortForDisplay(values, System.currentTimeMillis());
        return values;
    }

    /** 覆盖保存全部清单。 */
    public static void save(SharedPreferences store, List<Checklist> values) {
        try {
            store.edit().putString(KEY_CHECKLISTS, toJson(values).toString()).apply();
        } catch (Exception ignored) {}
    }

    public static JSONArray toJson(List<Checklist> values) {
        JSONArray array = new JSONArray();
        if (values != null) {
            for (Checklist checklist : values) {
                if (checklist != null) array.put(checklist.json());
            }
        }
        return array;
    }

    public static List<Checklist> fromJson(JSONArray array) {
        List<Checklist> values = new ArrayList<>();
        if (array != null) {
            for (int i = 0; i < array.length(); i++) {
                Checklist checklist = Checklist.from(array.optJSONObject(i));
                if (checklist != null) values.add(checklist);
            }
        }
        return values;
    }

    /** 按 id 找清单，找不到返回 null。 */
    public static Checklist find(List<Checklist> values, String id) {
        if (values == null || id == null) return null;
        for (Checklist value : values) {
            if (id.equals(value.id)) return value;
        }
        return null;
    }

    /** 新增或更新一张清单，其它清单不动。 */
    public static void upsert(SharedPreferences store, Checklist checklist) {
        if (checklist == null) return;
        List<Checklist> values = load(store);
        checklist.updatedAt = System.currentTimeMillis();
        boolean replaced = false;
        for (int i = 0; i < values.size(); i++) {
            if (checklist.id.equals(values.get(i).id)) {
                values.set(i, checklist);
                replaced = true;
                break;
            }
        }
        if (!replaced) values.add(checklist);
        save(store, values);
    }

    /** 删除清单，同时清掉提醒标记。 */
    public static void delete(SharedPreferences store, String id) {
        List<Checklist> values = load(store);
        for (int i = values.size() - 1; i >= 0; i--) {
            if (values.get(i).id.equals(id)) values.remove(i);
        }
        save(store, values);
        SharedPreferences.Editor editor = store.edit();
        for (String key : store.getAll().keySet()) {
            if (key.startsWith(REMINDER_PREFIX + id + "_")) editor.remove(key);
        }
        editor.apply();
    }

    /** 未完成、快截止的排前面；全部完成的排最后。 */
    public static void sortForDisplay(List<Checklist> values, long now) {
        Collections.sort(values, new Comparator<Checklist>() {
            @Override
            public int compare(Checklist first, Checklist second) {
                boolean firstDone = first.allDone();
                boolean secondDone = second.allDone();
                if (firstDone != secondDone) return firstDone ? 1 : -1;
                int byDeadline = Long.compare(first.deadlineMillis(), second.deadlineMillis());
                if (byDeadline != 0) return byDeadline;
                return first.title.compareToIgnoreCase(second.title);
            }
        });
    }

    public static void markReminded(SharedPreferences store, Checklist checklist) {
        if (checklist == null) return;
        store.edit().putBoolean(reminderKey(checklist), true).apply();
    }

    public static void clearReminded(SharedPreferences store, Checklist checklist) {
        if (checklist == null) return;
        store.edit().remove(reminderKey(checklist)).apply();
    }

    public static boolean wasReminded(SharedPreferences store, Checklist checklist) {
        return checklist != null && store.getBoolean(reminderKey(checklist), false);
    }

    public static List<Checklist> pendingReminders(SharedPreferences store, long now) {
        List<Checklist> result = new ArrayList<>();
        for (Checklist checklist : load(store)) {
            if (checklist.allDone() || checklist.reminderMinutes < 0) continue;
            if (now < checklist.reminderAtMillis()) continue;
            if (wasReminded(store, checklist)) continue;
            result.add(checklist);
        }
        return result;
    }

    private static String reminderKey(Checklist checklist) {
        String deadline = checklist.deadline == null ? "" : checklist.deadline.replaceAll("[^0-9]", "");
        return REMINDER_PREFIX + checklist.id + "_" + deadline;
    }
}
