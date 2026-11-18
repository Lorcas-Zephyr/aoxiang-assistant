package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/** A checklist with a deadline, optional reminder, and editable items. */
public final class Checklist {
    public static final int REMINDER_NONE = -1;
    public static final String DEFAULT_COLOR = "#2F80ED";

    private static final DateTimeFormatter DEADLINE_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm", Locale.CHINA);
    private static final DateTimeFormatter DISPLAY_FORMAT = DateTimeFormatter.ofPattern("M月d日 E HH:mm", Locale.CHINA);

    public String id;
    public String title;
    public String color;
    public String deadline;
    public int reminderMinutes;
    public long createdAt;
    public long updatedAt;
    public List<Item> items = new ArrayList<>();

    private String cachedDeadlineValue;
    private ZoneId cachedDeadlineZone;
    private long cachedDeadlineMillis = Long.MIN_VALUE;

    public Checklist(String id, String title, String deadline, int reminderMinutes) {
        this.id = id;
        this.title = title;
        this.deadline = deadline;
        this.reminderMinutes = reminderMinutes;
        this.color = DEFAULT_COLOR;
        this.createdAt = System.currentTimeMillis();
        this.updatedAt = this.createdAt;
    }

    public static class Item {
        public String id;
        public String text;
        public boolean done;

        public Item(String id, String text) {
            this.id = id;
            this.text = text;
        }
    }

    public int doneCount() {
        int count = 0;
        for (Item item : items) if (item != null && item.done) count++;
        return count;
    }

    public int pendingCount() {
        return Math.max(0, items.size() - doneCount());
    }

    public boolean allDone() {
        if (items.isEmpty()) return false;
        for (Item item : items) {
            if (item != null && !item.done) return false;
        }
        return true;
    }

    public float progress() {
        if (items.isEmpty()) return 0f;
        return Math.max(0f, Math.min(1f, doneCount() / (float) items.size()));
    }

    public LocalDateTime deadlineTime() {
        try {
            return LocalDateTime.parse(deadline, DEADLINE_FORMAT);
        } catch (Exception ignored) {
            try {
                return LocalDateTime.parse(deadline);
            } catch (Exception ignoredAgain) {
                return LocalDateTime.now().plusDays(1).withHour(23).withMinute(59);
            }
        }
    }

    public long deadlineMillis() {
        ZoneId zone = ZoneId.systemDefault();
        String value = deadline == null ? "" : deadline;
        if (cachedDeadlineMillis != Long.MIN_VALUE && value.equals(cachedDeadlineValue)
                && zone.equals(cachedDeadlineZone)) {
            return cachedDeadlineMillis;
        }
        cachedDeadlineValue = value;
        cachedDeadlineZone = zone;
        cachedDeadlineMillis = deadlineTime().atZone(zone).toInstant().toEpochMilli();
        return cachedDeadlineMillis;
    }

    public long reminderAtMillis() {
        return deadlineMillis() - Math.max(0, reminderMinutes) * 60_000L;
    }

    public String deadlineDisplay() {
        return DISPLAY_FORMAT.format(deadlineTime());
    }

    public String reminderLabel() {
        if (reminderMinutes < 0) return "不提醒";
        if (reminderMinutes == 0) return "截止时提醒";
        if (reminderMinutes % 1440 == 0) return "提前" + (reminderMinutes / 1440) + "天";
        if (reminderMinutes % 60 == 0) return "提前" + (reminderMinutes / 60) + "小时";
        return "提前" + reminderMinutes + "分钟";
    }

    public String countdownText(long now) {
        if (allDone()) return "已完成";
        long deadlineAt = deadlineMillis();
        long diff = deadlineAt - now;
        if (diff <= 0) {
            return "已截止 " + formatDuration(-diff);
        }
        return "剩余 " + formatDuration(diff);
    }

    public String compactCountdownText(long now) {
        if (allDone()) return "已完成";
        long diff = deadlineMillis() - now;
        if (diff <= 0) return "已截止";
        return formatDuration(diff);
    }

    public static String formatDuration(long millis) {
        long totalSeconds = Math.max(0, millis / 1000L);
        long days = totalSeconds / 86400L;
        long hours = (totalSeconds % 86400L) / 3600L;
        long minutes = (totalSeconds % 3600L) / 60L;
        long seconds = totalSeconds % 60L;
        if (days > 0) {
            return days + "天 " + String.format(Locale.CHINA, "%02d:%02d:%02d", hours, minutes, seconds);
        }
        return String.format(Locale.CHINA, "%02d:%02d:%02d", hours, minutes, seconds);
    }

    public JSONObject json() {
        JSONObject object = new JSONObject();
        try {
            object.put("id", id);
            object.put("title", title);
            object.put("color", color == null ? DEFAULT_COLOR : color);
            object.put("deadline", deadline);
            object.put("reminderMinutes", reminderMinutes);
            object.put("createdAt", createdAt);
            object.put("updatedAt", updatedAt);
            JSONArray array = new JSONArray();
            for (Item item : items) {
                if (item == null) continue;
                JSONObject row = new JSONObject();
                row.put("id", item.id);
                row.put("text", item.text);
                row.put("done", item.done);
                array.put(row);
            }
            object.put("items", array);
        } catch (Exception ignored) {}
        return object;
    }

    public static Checklist from(JSONObject object) {
        if (object == null) return null;
        String id = object.optString("id", "");
        String title = object.optString("title", "").trim();
        if (id.isEmpty() || title.isEmpty()) return null;
        Checklist checklist = new Checklist(
                id,
                title,
                object.optString("deadline", ""),
                object.optInt("reminderMinutes", 30)
        );
        checklist.color = object.optString("color", DEFAULT_COLOR);
        checklist.createdAt = object.optLong("createdAt", System.currentTimeMillis());
        checklist.updatedAt = object.optLong("updatedAt", checklist.createdAt);
        JSONArray array = object.optJSONArray("items");
        if (array != null) {
            for (int i = 0; i < array.length(); i++) {
                JSONObject row = array.optJSONObject(i);
                if (row == null) continue;
                String text = row.optString("text", "").trim();
                if (text.isEmpty()) continue;
                Item item = new Item(row.optString("id", "item-" + i), text);
                item.done = row.optBoolean("done", false);
                checklist.items.add(item);
            }
        }
        return checklist;
    }

    public static String defaultDeadline() {
        return DEADLINE_FORMAT.format(LocalDateTime.now().plusDays(1).withHour(23).withMinute(59).withSecond(0).withNano(0));
    }

    public static String formatDeadline(LocalDate date, LocalTime time) {
        return DEADLINE_FORMAT.format(LocalDateTime.of(date, time));
    }
}
