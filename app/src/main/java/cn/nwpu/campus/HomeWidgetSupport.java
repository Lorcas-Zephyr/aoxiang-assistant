package cn.nwpu.campus;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.TypedValue;
import android.widget.RemoteViews;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.List;

final class HomeWidgetSupport {
    private static final String ELECTRICITY_HOME =
            "https://yktapp.nwpu.edu.cn/plat/shouyeUser";
    private HomeWidgetSupport() {}

    static void updateGpa(Context context, AppWidgetManager manager, int id) {
        Summary summary = readSummary(context);
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_gpa);
        views.setTextViewText(R.id.widget_single_value, summary.gpa);
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 2, 2201));
        applySingleTheme(context, views);
        manager.updateAppWidget(id, views);
    }

    static void updateElectricity(Context context, AppWidgetManager manager, int id) {
        Summary summary = readSummary(context);
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_electricity);
        views.setTextViewText(R.id.widget_single_value, summary.electricity);
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 0, 2202));
        applySingleTheme(context, views);
        manager.updateAppWidget(id, views);
    }

    static void updateGpaElectricity(Context context, AppWidgetManager manager, int id,
                                     boolean wide) {
        int layout = wide ? R.layout.widget_gpa_electricity_wide
                : R.layout.widget_gpa_electricity_compact;
        Summary summary = readSummary(context);
        RemoteViews views = new RemoteViews(context.getPackageName(), layout);
        views.setTextViewText(R.id.widget_gpa_value, summary.gpa);
        views.setTextViewText(R.id.widget_electricity_value, summary.electricity);
        views.setOnClickPendingIntent(R.id.widget_gpa_area, openTab(context, 2, 2203));
        views.setOnClickPendingIntent(R.id.widget_electricity_area, openTab(context, 0, 2204));
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 0, 2205));
        applyCombinedTheme(context, views, wide);
        manager.updateAppWidget(id, views);
    }

    static void updateHomeOverview(Context context, AppWidgetManager manager, int id,
                                   boolean wide) {
        int layout = wide ? R.layout.widget_home_overview_wide
                : R.layout.widget_home_overview_compact;
        Summary summary = readSummary(context);
        RemoteViews views = new RemoteViews(context.getPackageName(), layout);
        views.setTextViewText(R.id.widget_gpa_value, summary.gpa);
        views.setTextViewText(R.id.widget_weighted_value, summary.weightedScore);
        views.setTextViewText(R.id.widget_course_value, summary.courseCount);
        views.setTextViewText(R.id.widget_electricity_value, summary.electricity);
        PendingIntent grades = openTab(context, 2, 2206);
        views.setOnClickPendingIntent(R.id.widget_gpa_area, grades);
        views.setOnClickPendingIntent(R.id.widget_weighted_area, grades);
        views.setOnClickPendingIntent(R.id.widget_course_area, grades);
        views.setOnClickPendingIntent(R.id.widget_electricity_area, openTab(context, 0, 2207));
        views.setOnClickPendingIntent(R.id.widget_root, openTab(context, 0, 2208));
        applyOverviewTheme(context, views, wide);
        manager.updateAppWidget(id, views);
    }

    private static PendingIntent openTab(Context context, int tab, int requestCode) {
        Intent intent = new Intent(context, MainActivity.class)
                .putExtra("start_tab", tab)
                .setAction("cn.nwpu.campus.action.OPEN_WIDGET_TAB_" + tab);
        return PendingIntent.getActivity(context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static Summary readSummary(Context context) {
        SharedPreferences store = context.getSharedPreferences("campus_private", Context.MODE_PRIVATE);
        DecimalFormat scoreFormat = new DecimalFormat("0.00");
        DecimalFormat gpaFormat = new DecimalFormat("0.000");

        double gpa = parseStoredDouble(store, "portrait_gpa");
        String gpaText = Double.isNaN(gpa) ? "--" : gpaFormat.format(gpa);

        List<GradeRecord> grades = new ArrayList<>();
        try {
            JSONArray array = new JSONArray(store.getString("grades", ""));
            for (int i = 0; i < array.length(); i++) {
                JSONObject item = array.optJSONObject(i);
                if (item != null) grades.add(GradeRecord.from(item));
            }
            grades = GradeRecord.keepHighest(grades);
        } catch (Exception ignored) {
            grades.clear();
        }

        double[] credits = new double[grades.size()];
        double[] scores = new double[grades.size()];
        for (int i = 0; i < grades.size(); i++) {
            GradeRecord grade = grades.get(i);
            credits[i] = grade.credits;
            scores[i] = grade.score == null ? Double.NaN : grade.score;
        }
        double weightedScore = GradeMath.weightedAverage(credits, scores);

        double electricity = ELECTRICITY_HOME.equals(
                store.getString("electricity_balance_source", ""))
                ? parseStoredDouble(store, "electricity_balance") : Double.NaN;
        return new Summary(
                gpaText,
                Double.isNaN(weightedScore) ? "--" : scoreFormat.format(weightedScore),
                Integer.toString(grades.size()),
                Double.isNaN(electricity) ? "--" : scoreFormat.format(electricity));
    }

    private static double parseStoredDouble(SharedPreferences store, String key) {
        try {
            return Double.parseDouble(store.getString(key, ""));
        } catch (Exception ignored) {
            return Double.NaN;
        }
    }

    private static void applySingleTheme(Context context, RemoteViews views) {
        Theme theme = theme(context);
        views.setInt(R.id.widget_root, "setBackgroundResource", theme.background);
        views.setTextColor(R.id.widget_single_title, theme.muted);
        views.setTextColor(R.id.widget_single_value, theme.text);
        views.setTextColor(R.id.widget_single_unit, theme.muted);
    }

    private static void applyCombinedTheme(Context context, RemoteViews views, boolean wide) {
        Theme theme = theme(context);
        views.setInt(R.id.widget_root, "setBackgroundResource", theme.background);
        views.setInt(R.id.widget_primary_divider, "setBackgroundColor", theme.divider);
        int[] labels = {R.id.widget_gpa_label, R.id.widget_electricity_label};
        int[] values = {R.id.widget_gpa_value, R.id.widget_electricity_value};
        int[] units = {R.id.widget_gpa_unit, R.id.widget_electricity_unit};
        for (int label : labels) views.setTextColor(label, theme.muted);
        for (int value : values) {
            views.setTextColor(value, theme.text);
            views.setTextViewTextSize(value, TypedValue.COMPLEX_UNIT_SP, wide ? 18 : 15);
        }
        for (int unit : units) views.setTextColor(unit, theme.muted);
    }

    private static void applyOverviewTheme(Context context, RemoteViews views, boolean wide) {
        Theme theme = theme(context);
        views.setInt(R.id.widget_root, "setBackgroundResource", theme.background);
        views.setInt(R.id.widget_primary_divider, "setBackgroundColor", theme.divider);
        views.setInt(R.id.widget_secondary_divider, "setBackgroundColor", theme.divider);
        views.setInt(R.id.widget_tertiary_divider, "setBackgroundColor", theme.divider);
        int[] labels = {R.id.widget_gpa_label, R.id.widget_weighted_label,
                R.id.widget_course_label, R.id.widget_electricity_label};
        int[] values = {R.id.widget_gpa_value, R.id.widget_weighted_value,
                R.id.widget_course_value, R.id.widget_electricity_value};
        int[] units = {R.id.widget_gpa_unit, R.id.widget_weighted_unit,
                R.id.widget_course_unit, R.id.widget_electricity_unit};
        for (int label : labels) views.setTextColor(label, theme.muted);
        for (int value : values) {
            views.setTextColor(value, theme.text);
            views.setTextViewTextSize(value, TypedValue.COMPLEX_UNIT_SP, wide ? 22 : 17);
        }
        for (int unit : units) views.setTextColor(unit, theme.muted);
    }

    private static Theme theme(Context context) {
        SharedPreferences store = context.getSharedPreferences("campus_private", Context.MODE_PRIVATE);
        boolean dark = ScheduleStorage.loadDarkMode(store);
        return dark
                ? new Theme(R.drawable.widget_background_dark, 0xFFF5F8FC, 0xFF9CB0C7, 0xFF3B4654)
                : new Theme(R.drawable.widget_background, 0xFF19324D, 0xFF5E7185, 0xFFE5EDF5);
    }

    static final class Summary {
        final String gpa;
        final String weightedScore;
        final String courseCount;
        final String electricity;

        Summary(String gpa, String weightedScore, String courseCount, String electricity) {
            this.gpa = gpa;
            this.weightedScore = weightedScore;
            this.courseCount = courseCount;
            this.electricity = electricity;
        }
    }

    private static final class Theme {
        final int background;
        final int text;
        final int muted;
        final int divider;

        Theme(int background, int text, int muted, int divider) {
            this.background = background;
            this.text = text;
            this.muted = muted;
            this.divider = divider;
        }
    }
}
