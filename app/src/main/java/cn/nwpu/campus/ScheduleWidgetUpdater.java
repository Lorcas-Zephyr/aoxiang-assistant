package cn.nwpu.campus;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;

final class ScheduleWidgetUpdater {
    private ScheduleWidgetUpdater() {}

    static void updateAll(Context context) {
        Context app = context.getApplicationContext();
        AppWidgetManager manager = AppWidgetManager.getInstance(app);
        updateScheduleProvider(app, manager, new ComponentName(app, ScheduleWidgetProvider.class));
        updateScheduleProvider(app, manager, new ComponentName(app, SmallScheduleWidgetProvider.class));
        updateProvider(app, manager, GpaWidgetProvider.class);
        updateProvider(app, manager, ElectricityWidgetProvider.class);
        updateProvider(app, manager, GpaElectricityWidgetProvider.class);
        updateProvider(app, manager, WideGpaElectricityWidgetProvider.class);
        updateProvider(app, manager, HomeOverviewWidgetProvider.class);
        updateProvider(app, manager, WideHomeOverviewWidgetProvider.class);
    }

    private static void updateScheduleProvider(Context context, AppWidgetManager manager,
                                               ComponentName component) {
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

    private static void updateProvider(Context context, AppWidgetManager manager,
                                       Class<? extends android.appwidget.AppWidgetProvider> provider) {
        ComponentName component = new ComponentName(context, provider);
        int[] ids = manager.getAppWidgetIds(component);
        if (ids.length == 0) return;
        context.sendBroadcast(new android.content.Intent(context, provider)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids));
    }
}
