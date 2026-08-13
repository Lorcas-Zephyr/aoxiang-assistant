package cn.nwpu.campus;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.widget.RemoteViews;

import java.util.Calendar;

public class ScheduleWidgetProvider extends AppWidgetProvider {
    static final String ACTION_HOURLY = "cn.nwpu.campus.action.WIDGET_HOURLY";
    private static final int REQUEST_CODE = 2101;

    @Override public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        ScheduleWidgetContext.set(context);
        for (int id : ids) updateOne(context, manager, id);
        scheduleNextHour(context);
    }

    @Override public void onReceive(Context context, Intent intent) {
        if (ACTION_HOURLY.equals(intent.getAction())) {
            ScheduleWidgetUpdater.updateAll(context);
            scheduleNextHour(context);
            return;
        }
        super.onReceive(context, intent);
    }

    @Override public void onDeleted(Context context, int[] ids) {
        if (!hasAnyWidgets(context)) cancelHour(context);
    }

    static void updateOne(Context context, AppWidgetManager manager, int id) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_large);
        // Distinguish the large and small collection services so Android does
        // not reuse a RemoteViewsFactory created for the other widget size.
        Intent service = new Intent(context, ScheduleWidgetService.class)
                .setData(Uri.parse("cn.nwpu.campus://widget/large"))
                .putExtra("small", false);
        views.setRemoteAdapter(R.id.widget_course_list, service);
        views.setPendingIntentTemplate(R.id.widget_course_list, openSchedule(context));
        views.setOnClickPendingIntent(R.id.widget_root, openSchedule(context));
        android.content.SharedPreferences store = context.getSharedPreferences("campus_private", Context.MODE_PRIVATE);
        boolean dark = ScheduleStorage.loadDarkMode(store);
        views.setInt(R.id.widget_header_divider, "setBackgroundColor", dark ? 0xFF3B4654 : 0xFFE5EDF5);
        views.setInt(R.id.widget_content_divider, "setBackgroundColor", dark ? 0xFF718096 : 0xFFB6C4D2);
        views.setTextColor(R.id.widget_today_title, dark ? 0xFF9CB0C7 : 0xFF5E7185);
        views.setTextColor(R.id.widget_tomorrow_title, dark ? 0xFF9CB0C7 : 0xFF5E7185);
        views.setTextViewText(R.id.widget_today_title, "今天 " + dateLabel(0));
        views.setTextViewText(R.id.widget_tomorrow_title, "明天 " + dateLabel(1));
        manager.updateAppWidget(id, views);
    }

    static PendingIntent openSchedule(Context context) {
        Intent intent = new Intent(context, MainActivity.class).putExtra("start_tab", 1);
        return PendingIntent.getActivity(context, 2102, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    static String dateLabel(int offset) {
        Calendar calendar = Calendar.getInstance();
        calendar.add(Calendar.DAY_OF_YEAR, offset);
        return (calendar.get(Calendar.MONTH) + 1) + "/" + calendar.get(Calendar.DAY_OF_MONTH);
    }

    static void scheduleNextHour(Context context) {
        AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarm == null) return;
        Intent intent = new Intent(context, ScheduleWidgetProvider.class).setAction(ACTION_HOURLY);
        PendingIntent pending = PendingIntent.getBroadcast(context, REQUEST_CODE, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Calendar next = Calendar.getInstance();
        next.set(Calendar.MINUTE, 0); next.set(Calendar.SECOND, 0); next.set(Calendar.MILLISECOND, 0); next.add(Calendar.HOUR_OF_DAY, 1);
        if (Build.VERSION.SDK_INT >= 23) alarm.setAndAllowWhileIdle(AlarmManager.RTC, next.getTimeInMillis(), pending);
        else alarm.set(AlarmManager.RTC, next.getTimeInMillis(), pending);
    }

    static void cancelHour(Context context) {
        AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarm == null) return;
        Intent intent = new Intent(context, ScheduleWidgetProvider.class).setAction(ACTION_HOURLY);
        alarm.cancel(PendingIntent.getBroadcast(context, REQUEST_CODE, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
    }

    static boolean hasAnyWidgets(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        return manager.getAppWidgetIds(new ComponentName(context, ScheduleWidgetProvider.class)).length > 0
                || manager.getAppWidgetIds(new ComponentName(context, SmallScheduleWidgetProvider.class)).length > 0;
    }
}
