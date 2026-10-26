package cn.nwpu.campus;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

/** Shared foreground/background notification handling for bus reservation changes. */
final class BusNotifications {
    static final String CHANNEL_ID = "bus_alerts";

    private BusNotifications() {}

    static void ensureChannel(Context context) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) return;
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "校车提醒", NotificationManager.IMPORTANCE_HIGH);
        channel.setDescription("校车预约状态变化与发车前提醒");
        manager.createNotificationChannel(channel);
    }

    static void notifyChanges(Context context, SharedPreferences store,
                              BusModels.Snapshot snapshot, long now) {
        if (snapshot == null) return;
        boolean statusEnabled = store.getBoolean("bus_status_reminder_enabled", true);
        boolean departureEnabled = store.getBoolean("bus_departure_reminder_enabled", true);
        for (BusModels.Reservation reservation : snapshot.reservations) {
            if (statusEnabled) {
                String before = BusStorage.previousStatus(store, reservation);
                if (BusReminderPolicy.shouldRemindStatus(before, reservation.status)) {
                    String key = BusReminderPolicy.statusKey(reservation);
                    if (!BusStorage.isReminded(store, key)
                            && post(context, key, "校车预约状态更新",
                            BusReminderPolicy.statusText(reservation))) {
                        BusStorage.markReminded(store, key);
                    }
                }
            }
            if (departureEnabled) notifyDeparture(context, store, reservation, now);
        }
    }

    static int notifyDueDepartures(Context context, SharedPreferences store,
                                   BusModels.Snapshot snapshot, long now) {
        if (snapshot == null || !store.getBoolean("bus_departure_reminder_enabled", true)) {
            return 0;
        }
        int sent = 0;
        for (BusModels.Reservation reservation : snapshot.reservations) {
            if (notifyDeparture(context, store, reservation, now)) sent++;
        }
        return sent;
    }

    private static boolean notifyDeparture(Context context, SharedPreferences store,
                                           BusModels.Reservation reservation, long now) {
        if (reservation == null || reservation.rejected()
                || !BusReminderPolicy.shouldRemindDeparture(reservation.departureAt(), now)) {
            return false;
        }
        String key = BusReminderPolicy.departureKey(reservation);
        if (BusStorage.isReminded(store, key)) return false;
        if (!post(context, key, "校车发车提醒",
                BusReminderPolicy.departureText(reservation, now))) return false;
        BusStorage.markReminded(store, key);
        return true;
    }

    private static boolean post(Context context, String key, String title, String text) {
        if (Build.VERSION.SDK_INT >= 33
                && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) return false;
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) return false;
        ensureChannel(context);
        int id = 2000 + ((key == null ? 0 : key.hashCode()) & 0x3ff);
        Intent intent = new Intent(context, MainActivity.class).putExtra("start_tab", 0);
        PendingIntent pending = PendingIntent.getActivity(context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(context, CHANNEL_ID)
                : new Notification.Builder(context);
        builder.setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .setContentIntent(pending);
        manager.notify(id, builder.build());
        return true;
    }
}
