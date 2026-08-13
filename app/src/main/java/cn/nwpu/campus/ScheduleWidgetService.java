package cn.nwpu.campus;

import android.content.Intent;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public class ScheduleWidgetService extends RemoteViewsService {
    @Override public RemoteViewsFactory onGetViewFactory(Intent intent) {
        return new Factory(getApplicationContext(), intent.getBooleanExtra("small", false));
    }

    private static final class Factory implements RemoteViewsFactory {
        private final android.content.Context context;
        private final boolean small;
        private final List<Row> rows = new ArrayList<>();
        private boolean dark;

        Factory(android.content.Context context, boolean small) {
            this.context = context;
            this.small = small;
        }

        @Override public void onCreate() { reload(); }
        @Override public void onDataSetChanged() { reload(); }
        @Override public void onDestroy() { rows.clear(); }
        @Override public int getCount() { return rows.size(); }
        @Override public RemoteViews getViewAt(int position) {
            Row row = rows.get(position);
            return small ? smallView(row) : largeView(row);
        }
        @Override public RemoteViews getLoadingView() { return null; }
        @Override public int getViewTypeCount() { return 1; }
        @Override public long getItemId(int position) { return position; }
        @Override public boolean hasStableIds() { return false; }

        private void reload() {
            ScheduleWidgetContext.set(context);
            android.content.SharedPreferences store = context.getSharedPreferences("campus_private", android.content.Context.MODE_PRIVATE);
            dark = ScheduleStorage.loadDarkMode(store);
            rows.clear();
            ScheduleWidgetData.DayData today = ScheduleWidgetData.forDate(LocalDate.now(), small);
            if (small) {
                int count = Math.min(3, today.items.size());
                for (int i = 0; i < count; i++) rows.add(new Row(today.items.get(i), (ScheduleWidgetData.Item) null));
                if (today.items.isEmpty()) rows.add(new Row(null, "今天没有课了"));
                else if (today.items.size() > count) rows.add(new Row(null, "+" + (today.items.size() - count)));
                else rows.add(Row.spacer());
            } else {
                ScheduleWidgetData.DayData tomorrow = ScheduleWidgetData.forDate(LocalDate.now().plusDays(1), false);
                int count = Math.max(today.items.size(), tomorrow.items.size());
                if (count == 0) count = 1;
                for (int i = 0; i < count; i++) rows.add(new Row(i < today.items.size() ? today.items.get(i) : null,
                        i < tomorrow.items.size() ? tomorrow.items.get(i) : null));
                rows.add(Row.spacer());
            }
        }

        private RemoteViews smallView(Row row) {
            RemoteViews view = new RemoteViews(context.getPackageName(), R.layout.widget_small_row);
            view.setOnClickFillInIntent(R.id.widget_small_row_root, new Intent());
            if (row.spacer) {
                view.setInt(R.id.widget_small_row_root, "setBackgroundColor", android.graphics.Color.TRANSPARENT);
                view.setViewVisibility(R.id.widget_spacer, android.view.View.VISIBLE);
                view.setTextViewText(R.id.widget_name, "");
                view.setTextViewText(R.id.widget_time, "");
                view.setTextViewText(R.id.widget_location, "");
                view.setViewVisibility(R.id.widget_dot, android.view.View.GONE);
                return view;
            }
            applyBackground(view, R.id.widget_small_row_root);
            if (row.message != null) {
                view.setTextViewText(R.id.widget_name, row.message);
                view.setTextViewText(R.id.widget_time, "");
                view.setTextViewText(R.id.widget_location, "");
                view.setViewVisibility(R.id.widget_dot, android.view.View.GONE);
            } else {
                fill(view, row.today, R.id.widget_dot, R.id.widget_name, R.id.widget_time, R.id.widget_location);
            }
            applyColors(view, R.id.widget_name, R.id.widget_time, R.id.widget_location);
            return view;
        }

        private RemoteViews largeView(Row row) {
            RemoteViews view = new RemoteViews(context.getPackageName(), R.layout.widget_large_row);
            // Keep the two day columns independent collection items.
            view.setOnClickFillInIntent(R.id.widget_today_column, new Intent().putExtra("widget_column", "today"));
            view.setOnClickFillInIntent(R.id.widget_tomorrow_column, new Intent().putExtra("widget_column", "tomorrow"));
            view.setInt(R.id.widget_column_divider, "setBackgroundColor", dark ? 0xFF3B4654 : 0xFFE5EDF5);
            if (row.spacer) {
                view.setOnClickFillInIntent(R.id.widget_large_row_root, new Intent());
                view.setInt(R.id.widget_today_column, "setBackgroundColor", android.graphics.Color.TRANSPARENT);
                view.setInt(R.id.widget_tomorrow_column, "setBackgroundColor", android.graphics.Color.TRANSPARENT);
                view.setViewVisibility(R.id.widget_spacer, android.view.View.VISIBLE);
                view.setViewVisibility(R.id.widget_today_dot, android.view.View.GONE);
                view.setViewVisibility(R.id.widget_tomorrow_dot, android.view.View.GONE);
                view.setTextViewText(R.id.widget_today_name, "");
                view.setTextViewText(R.id.widget_tomorrow_name, "");
                view.setTextViewText(R.id.widget_today_time, "");
                view.setTextViewText(R.id.widget_tomorrow_time, "");
                view.setTextViewText(R.id.widget_today_location, "");
                view.setTextViewText(R.id.widget_tomorrow_location, "");
                return view;
            }
            applyBackground(view, R.id.widget_today_column);
            applyBackground(view, R.id.widget_tomorrow_column);
            if (row.today == null) clearColumn(view, R.id.widget_today_column, R.id.widget_today_dot,
                    R.id.widget_today_name, R.id.widget_today_time, R.id.widget_today_location, "今天没有课了");
            else fill(view, row.today, R.id.widget_today_dot, R.id.widget_today_name, R.id.widget_today_time, R.id.widget_today_location);
            if (row.tomorrow == null) clearColumn(view, R.id.widget_tomorrow_column, R.id.widget_tomorrow_dot,
                    R.id.widget_tomorrow_name, R.id.widget_tomorrow_time, R.id.widget_tomorrow_location, "明天没有课了");
            else fill(view, row.tomorrow, R.id.widget_tomorrow_dot, R.id.widget_tomorrow_name, R.id.widget_tomorrow_time, R.id.widget_tomorrow_location);
            applyColors(view, R.id.widget_today_name, R.id.widget_today_time, R.id.widget_today_location);
            applyColors(view, R.id.widget_tomorrow_name, R.id.widget_tomorrow_time, R.id.widget_tomorrow_location);
            return view;
        }

        private void fill(RemoteViews view, ScheduleWidgetData.Item item, int dot, int name, int time, int location) {
            view.setViewVisibility(dot, android.view.View.VISIBLE);
            view.setTextViewText(name, item.name);
            view.setTextViewText(time, item.timeText());
            view.setTextViewText(location, item.location);
            view.setViewVisibility(location, item.location.isEmpty() ? android.view.View.GONE : android.view.View.VISIBLE);
            int color = parseColor(item.color, ScheduleModels.DEFAULT_THEME_COLOR);
            view.setTextColor(dot, color);
        }

        private void clearColumn(RemoteViews view, int column, int dot, int name, int time, int location, String message) {
            view.setViewVisibility(column, android.view.View.VISIBLE);
            view.setViewVisibility(dot, android.view.View.GONE);
            view.setTextViewText(name, message);
            view.setTextViewText(time, "");
            view.setTextViewText(location, "");
            view.setViewVisibility(location, android.view.View.GONE);
        }

        private void applyColors(RemoteViews view, int name, int time, int location) {
            view.setTextColor(name, dark ? 0xFFF5F8FC : 0xFF19324D);
            view.setTextColor(time, dark ? 0xFF9CB0C7 : 0xFF5E7185);
            view.setTextColor(location, dark ? 0xFF9CB0C7 : 0xFF5E7185);
        }

        private void applyBackground(RemoteViews view, int id) {
            view.setInt(id, "setBackgroundColor", dark ? 0xFF1C222B : 0xFFF6FAFF);
        }

        private int parseColor(String value, String fallback) {
            try { return android.graphics.Color.parseColor(value == null || value.isEmpty() ? fallback : value); }
            catch (Exception ignored) { return android.graphics.Color.parseColor(fallback); }
        }

        private static final class Row {
            final ScheduleWidgetData.Item today;
            final ScheduleWidgetData.Item tomorrow;
            final String message;
            final boolean spacer;
            Row(ScheduleWidgetData.Item today, ScheduleWidgetData.Item tomorrow) { this.today = today; this.tomorrow = tomorrow; this.message = null; this.spacer = false; }
            Row(ScheduleWidgetData.Item item, String message) { this.today = item; this.tomorrow = null; this.message = message; this.spacer = false; }
            private Row() { this.today = null; this.tomorrow = null; this.message = null; this.spacer = true; }
            static Row spacer() { return new Row(); }
        }
    }
}
