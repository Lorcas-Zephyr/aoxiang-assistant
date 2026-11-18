package cn.nwpu.campus;

import org.json.JSONObject;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.Locale;

/** A user-created calendar event shown inside the timetable. */
public final class ManualEvent {
    public static final String DEFAULT_COLOR = "#FB8C00";

    private static final DateTimeFormatter TIME_FORMAT = DateTimeFormatter.ofPattern("HH:mm", Locale.CHINA);
    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ofPattern("M月d日", Locale.CHINA);
    private static final String[] WEEKDAYS = {"", "周一", "周二", "周三", "周四", "周五", "周六", "周日"};

    public String id;
    public String title;
    public String note;
    public String date;
    public String startTime;
    public String endTime;
    public String color;
    public boolean weekly;
    public int repeatWeeks = 1;

    public ManualEvent(String id, String title, String date, String startTime, String endTime) {
        this.id = id;
        this.title = title;
        this.date = date;
        this.startTime = startTime;
        this.endTime = endTime;
        this.color = DEFAULT_COLOR;
    }

    public LocalDate localDate() {
        try {
            return LocalDate.parse(date);
        } catch (Exception ignored) {
            return LocalDate.now();
        }
    }

    public LocalTime localStartTime() {
        try {
            return LocalTime.parse(startTime);
        } catch (Exception ignored) {
            return LocalTime.of(8, 0);
        }
    }

    public LocalTime localEndTime() {
        try {
            return LocalTime.parse(endTime);
        } catch (Exception ignored) {
            return localStartTime().plusHours(1);
        }
    }

    public String timeRange() {
        return startTime + "–" + endTime;
    }

    public boolean occursOn(LocalDate value) {
        if (value == null) return false;
        LocalDate start = localDate();
        if (value.isBefore(start)) return false;
        if (!weekly) return value.equals(start);
        long days = ChronoUnit.DAYS.between(start, value);
        return days >= 0 && days % 7 == 0 && (days / 7) < Math.max(1, repeatWeeks);
    }

    public String repeatLabel() {
        if (!weekly) return "仅一次";
        String weekday = WEEKDAYS[Math.max(1, Math.min(7, localDate().getDayOfWeek().getValue()))];
        return "每" + weekday + " · 连续" + Math.max(1, repeatWeeks) + "周";
    }

    public String dateLabel() {
        return formatDateLabel(localDate());
    }

    public static String formatDateLabel(LocalDate value) {
        if (value == null) return "";
        String weekday = WEEKDAYS[Math.max(1, Math.min(7, value.getDayOfWeek().getValue()))];
        return DATE_FORMAT.format(value) + " " + weekday;
    }

    public String fullDateLabel() {
        LocalDate value = localDate();
        return value.getYear() + "年" + DATE_FORMAT.format(value) + " "
                + WEEKDAYS[Math.max(1, Math.min(7, value.getDayOfWeek().getValue()))];
    }

    public JSONObject json() {
        JSONObject object = new JSONObject();
        try {
            object.put("id", id);
            object.put("title", title);
            object.put("note", note == null ? JSONObject.NULL : note);
            object.put("date", date);
            object.put("startTime", startTime);
            object.put("endTime", endTime);
            object.put("color", color == null ? DEFAULT_COLOR : color);
            object.put("weekly", weekly);
            object.put("repeatWeeks", Math.max(1, repeatWeeks));
        } catch (Exception ignored) {}
        return object;
    }

    public static ManualEvent from(JSONObject object) {
        if (object == null) return null;
        String id = object.optString("id", "");
        String title = object.optString("title", "").trim();
        String date = object.optString("date", "");
        if (id.isEmpty() || title.isEmpty() || date.isEmpty()) return null;
        ManualEvent event = new ManualEvent(
                id,
                title,
                date,
                object.optString("startTime", "08:00"),
                object.optString("endTime", "09:00")
        );
        event.note = object.isNull("note") ? null : object.optString("note", null);
        event.color = object.optString("color", DEFAULT_COLOR);
        event.weekly = object.optBoolean("weekly", false);
        event.repeatWeeks = Math.max(1, object.optInt("repeatWeeks", 1));
        return event;
    }
}
