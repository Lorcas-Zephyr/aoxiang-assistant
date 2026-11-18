package cn.nwpu.campus;

import android.app.AlarmManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;

import java.util.List;

/** Schedules checklist reminder alarms and owns their notification channel. */
public final class ChecklistReminderScheduler {
    public static final String CHANNEL_ID = "checklist_reminders";
    public static final String ACTION_REMIND = "cn.nwpu.campus.CHECKLIST_REMIND";
    public static final String EXTRA_CHECKLIST_ID = "checklist_id";

    private ChecklistReminderScheduler() {}

    public static void ensureChannel(Context context) {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager manager = context.getSystemService(NotificationManager.class);
            if (manager == null) return;
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "清单提醒", NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("到达清单提醒时间时通知");
            channel.enableVibration(true);
            manager.createNotificationChannel(channel);
        }
    }

    public static void rescheduleAll(Context context) {
        List<Checklist> values = ChecklistStore.load(
                context.getSharedPreferences("campus_private", Context.MODE_PRIVATE));
        for (Checklist checklist : values) {
            if (!checklist.allDone() && checklist.reminderMinutes >= 0) schedule(context, checklist);
        }
    }

    public static void schedule(Context context, Checklist checklist) {
        if (context == null || checklist == null) return;
        cancel(context, checklist.id);
        if (checklist.allDone() || checklist.reminderMinutes < 0) return;
        long triggerAt = checklist.reminderAtMillis();
        if (triggerAt <= System.currentTimeMillis() + 1000L) return;
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager == null) return;
        PendingIntent pending = pendingIntent(context, checklist.id);
        try {
            if (Build.VERSION.SDK_INT >= 31 && !manager.canScheduleExactAlarms()) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
            } else {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
            }
        } catch (SecurityException ignored) {
            try {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
            } catch (Exception ignoredAgain) {}
        } catch (Exception ignored) {
            try {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
            } catch (Exception ignoredAgain) {}
        }
    }

    public static void cancel(Context context, String checklistId) {
        if (context == null || checklistId == null) return;
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager == null) return;
        manager.cancel(pendingIntent(context, checklistId));
    }

    public static PendingIntent pendingIntent(Context context, String checklistId) {
        Intent intent = new Intent(context, ChecklistReminderReceiver.class);
        intent.setAction(ACTION_REMIND);
        intent.setData(Uri.parse("aoxiang://checklist/" + Uri.encode(checklistId)));
        intent.putExtra(EXTRA_CHECKLIST_ID, checklistId);
        int requestCode = 3100 + Math.abs((checklistId == null ? "" : checklistId).hashCode() % 10000);
        return PendingIntent.getBroadcast(context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
