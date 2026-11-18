package cn.nwpu.campus;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import java.util.List;

/** Posts the actual system notification for a checklist reminder. */
public class ChecklistReminderReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String id = intent.getStringExtra(ChecklistReminderScheduler.EXTRA_CHECKLIST_ID);
        if (id == null || id.isEmpty()) return;
        List<Checklist> values = ChecklistStore.load(
                context.getSharedPreferences("campus_private", Context.MODE_PRIVATE));
        Checklist checklist = ChecklistStore.find(values, id);
        if (checklist == null || checklist.allDone()) return;
        NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null || !manager.areNotificationsEnabled()) return;
        ChecklistReminderScheduler.ensureChannel(context);
        if (Build.VERSION.SDK_INT >= 26) {
            android.app.NotificationChannel channel = manager.getNotificationChannel(ChecklistReminderScheduler.CHANNEL_ID);
            if (channel != null && channel.getImportance() == NotificationManager.IMPORTANCE_NONE) return;
        }

        Intent open = new Intent(context, ChecklistActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        open.putExtra(ChecklistActivity.EXTRA_CHECKLIST_ID, checklist.id);
        PendingIntent pending = PendingIntent.getActivity(context,
                3200 + Math.abs(checklist.id.hashCode() % 10000), open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        String text = checklist.pendingCount() + " 项未完成 · 截止 " + checklist.deadlineDisplay();
        Notification.Builder builder = new Notification.Builder(context, ChecklistReminderScheduler.CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle("清单提醒 · " + checklist.title)
                .setContentText(text)
                .setStyle(new Notification.BigTextStyle().bigText(text + "\n点击查看并勾选事项"))
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_REMINDER)
                .setVisibility(Notification.VISIBILITY_PUBLIC);
        if (Build.VERSION.SDK_INT >= 26) builder.setChannelId(ChecklistReminderScheduler.CHANNEL_ID);
        manager.notify(3300 + Math.abs(checklist.id.hashCode() % 10000), builder.build());
        ChecklistStore.markReminded(context.getSharedPreferences("campus_private", Context.MODE_PRIVATE), checklist);
    }
}
