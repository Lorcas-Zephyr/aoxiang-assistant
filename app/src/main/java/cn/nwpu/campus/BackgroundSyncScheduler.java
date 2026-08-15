package cn.nwpu.campus;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

final class BackgroundSyncScheduler {
    static final String ACTION_WAKE = "cn.nwpu.campus.action.BACKGROUND_WAKE";
    private static final int REQUEST_CODE = 1005;

    private BackgroundSyncScheduler() {}

    static void schedule(Context context) {
        schedule(context, 1500L);
    }

    static void schedule(Context context, long minimumDelayMillis) {
        Context app = context.getApplicationContext();
        SharedPreferences store = app.getSharedPreferences("campus_private", Context.MODE_PRIVATE);
        if (!hasCredentials(store)) {
            cancel(app);
            return;
        }
        NextUpdate next = nextUpdate(store, System.currentTimeMillis());
        if (next == null) {
            cancel(app);
            return;
        }
        long now = System.currentTimeMillis();
        long triggerAt = Math.max(next.dueAt, now + Math.max(1000L, minimumDelayMillis));
        AlarmManager manager = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
        if (manager != null) {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent(app));
        }
    }

    static void cancel(Context context) {
        Context app = context.getApplicationContext();
        AlarmManager manager = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
        if (manager != null) manager.cancel(pendingIntent(app));
    }

    static NextUpdate nextUpdate(SharedPreferences store, long now) {
        NextUpdate next = null;
        String[] targets = {"grades", "electricity", "schedule"};
        for (String target : targets) {
            if (!isEnabled(store, target)) continue;
            long last = store.getLong("auto_last_" + target, 0L);
            long dueAt = last == 0L ? now : last + intervalMillis(store, target);
            if (next == null || dueAt < next.dueAt) next = new NextUpdate(target, dueAt);
        }
        return next;
    }

    private static PendingIntent pendingIntent(Context context) {
        Intent intent = new Intent(context, UpdateAlarmReceiver.class).setAction(ACTION_WAKE);
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static boolean hasCredentials(SharedPreferences store) {
        String credentials = store.getString("login_credentials", "");
        return credentials != null && !credentials.isEmpty()
                && store.getBoolean("credentials_verified", true);
    }

    private static boolean isEnabled(SharedPreferences store, String target) {
        String key = "auto_" + target.replace("grades", "grade") + "_enabled";
        return store.getBoolean(key, true);
    }

    private static long intervalMillis(SharedPreferences store, String target) {
        String prefix = "grades".equals(target) ? "grade" : target;
        int fallback = "schedule".equals(target) ? 60 : 10;
        int value = Math.max(1, store.getInt(prefix + "_interval_value", fallback));
        String unit = store.getString(prefix + "_interval_unit", "分钟");
        long multiplier = "天".equals(unit) ? 86_400_000L
                : "小时".equals(unit) ? 3_600_000L : 60_000L;
        return value * multiplier;
    }

    static final class NextUpdate {
        final String target;
        final long dueAt;

        NextUpdate(String target, long dueAt) {
            this.target = target;
            this.dueAt = dueAt;
        }
    }
}
