package cn.nwpu.campus;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;

final class ScheduleWidgetUpdater {
    private ScheduleWidgetUpdater() {}

    static void updateAll(Context context) {
        Context app = context.getApplicationContext();
        AppWidgetManager manager = AppWidgetManager.getInstance(app);
        updateProvider(app, manager, new ComponentName(app, ScheduleWidgetProvider.class));
        updateProvider(app, manager, new ComponentName(app, SmallScheduleWidgetProvider.class));
    }

    private static void updateProvider(Context context, AppWidgetManager manager, ComponentName component) {
        int[] ids = manager.getAppWidgetIds(component);
        if (ids.length == 0) return;
        manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_course_list);
        android.content.Intent intent;
        if (component.getClassName().equals(SmallScheduleWidgetProvider.class.getName())) {
            intent = new android.content.Intent(context, SmallScheduleWidgetProvider.class);
        } else {
            intent = new android.content.Intent(context, ScheduleWidgetProvider.class);
        }
        context.sendBroadcast(intent.setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids));
    }
}
