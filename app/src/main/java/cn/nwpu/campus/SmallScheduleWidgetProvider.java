package cn.nwpu.campus;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.widget.RemoteViews;

public class SmallScheduleWidgetProvider extends AppWidgetProvider {
    @Override public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        ScheduleWidgetContext.set(context);
        for (int id : ids) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_small);
            // Keep a distinct service identity from the four-column widget.
            Intent service = new Intent(context, ScheduleWidgetService.class)
                    .setData(Uri.parse("cn.nwpu.campus://widget/small"))
                    .putExtra("small", true);
            views.setRemoteAdapter(R.id.widget_course_list, service);
            views.setPendingIntentTemplate(R.id.widget_course_list, ScheduleWidgetProvider.openSchedule(context));
            views.setOnClickPendingIntent(R.id.widget_root, ScheduleWidgetProvider.openSchedule(context));
            manager.updateAppWidget(id, views);
        }
        ScheduleWidgetProvider.scheduleNextHour(context);
    }

    @Override public void onReceive(Context context, Intent intent) {
        if (ScheduleWidgetProvider.ACTION_HOURLY.equals(intent.getAction())) {
            ScheduleWidgetUpdater.updateAll(context);
            ScheduleWidgetProvider.scheduleNextHour(context);
            return;
        }
        super.onReceive(context, intent);
    }

    @Override public void onDeleted(Context context, int[] ids) {
        if (!ScheduleWidgetProvider.hasAnyWidgets(context)) {
            ScheduleWidgetProvider.cancelHour(context);
        }
    }
}
