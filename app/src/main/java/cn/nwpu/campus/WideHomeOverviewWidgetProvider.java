package cn.nwpu.campus;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;

public class WideHomeOverviewWidgetProvider extends AppWidgetProvider {
    @Override public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) HomeWidgetSupport.updateHomeOverview(context, manager, id, true);
    }
}
