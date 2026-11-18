package cn.nwpu.campus;

import android.app.Activity;
import android.app.DatePickerDialog;
import android.app.TimePickerDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.Locale;
import java.util.function.Consumer;

/** 手动日程页的 UI 辅助。只放样式和控件，不碰数据。 */
final class ManualEventUi {
    private final Activity activity;
    private final boolean darkMode;
    private final String themeColor;

    ManualEventUi(Activity activity, boolean darkMode, String themeColor) {
        this.activity = activity;
        this.darkMode = darkMode;
        this.themeColor = themeColor;
    }

    int dp(int value) {
        return (int) (value * activity.getResources().getDisplayMetrics().density + 0.5f);
    }

    TextView label(String text, float size, int color) {
        TextView view = new TextView(activity);
        view.setText(text);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setGravity(Gravity.CENTER_VERTICAL);
        return view;
    }

    LinearLayout card(int color) {
        LinearLayout layout = new LinearLayout(activity);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setBackground(border(color, lineColor(), 5));
        layout.setPadding(dp(14), dp(12), dp(14), dp(12));
        return layout;
    }

    LinearLayout sectionHeader(String heading, String trailing) {
        LinearLayout row = new LinearLayout(activity);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(section(heading), new LinearLayout.LayoutParams(0, dp(54), 1f));
        if (trailing != null && !trailing.isEmpty()) {
            TextView count = label(trailing, 11, mutedColor());
            count.setGravity(Gravity.CENTER_VERTICAL | Gravity.END);
            row.addView(count, new LinearLayout.LayoutParams(-2, dp(54)));
        }
        return row;
    }

    TextView section(String text) {
        TextView view = label(text, 13, mutedColor());
        view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    Button action(String text, boolean filled) {
        Button button = new Button(activity);
        button.setText(text);
        button.setTextSize(12);
        button.setAllCaps(false);
        button.setTextColor(filled ? Color.WHITE : primaryColor());
        button.setMinHeight(0);
        button.setMinWidth(0);
        button.setPadding(dp(12), 0, dp(12), 0);
        button.setBackground(border(filled ? primaryColor() : panelColor(),
                filled ? primaryColor() : lineColor(), 5));
        button.setStateListAnimator(null);
        return button;
    }

    EditText field(LinearLayout parent, String hint, String value) {
        EditText input = new EditText(activity);
        input.setHint(hint);
        if (value != null) input.setText(value);
        parent.addView(input, new LinearLayout.LayoutParams(-1, dp(58)));
        return input;
    }

    EditText multilineField(LinearLayout parent, String hint, String value) {
        EditText input = new EditText(activity);
        input.setHint(hint);
        if (value != null) input.setText(value);
        input.setTextColor(textColor());
        input.setHintTextColor(mutedColor());
        input.setPadding(dp(14), dp(10), dp(14), dp(10));
        input.setBackground(border(surfaceColor(), lineColor(), 8));
        input.setSingleLine(false);
        input.setMinLines(2);
        input.setMaxLines(4);
        input.setGravity(Gravity.TOP | Gravity.START);
        parent.addView(input, new LinearLayout.LayoutParams(-1, dp(96)));
        return input;
    }

    TextView inputLike(String value) {
        TextView view = label(value, 13, textColor());
        view.setGravity(Gravity.CENTER_VERTICAL);
        view.setPadding(dp(14), 0, dp(14), 0);
        view.setBackground(border(surfaceColor(), lineColor(), 8));
        view.setClickable(true);
        return view;
    }

    void addFormLabel(LinearLayout parent, String text) {
        TextView view = label(text, 11, mutedColor());
        view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(0, dp(9), 0, dp(4));
        parent.addView(view);
    }

    void styleDialogInput(EditText input) {
        input.setTextColor(textColor());
        input.setHintTextColor(mutedColor());
        input.setPadding(dp(14), 0, dp(14), 0);
        input.setBackground(border(surfaceColor(), lineColor(), 8));
    }

    void refreshSwatches(LinearLayout container, String chosen, Consumer<String> onChoose) {
        container.removeAllViews();
        for (String value : ScheduleModels.PRESET_COLORS) {
            View swatch = colorSwatch(value, value.equals(chosen));
            swatch.setOnClickListener(v -> onChoose.accept(value));
            container.addView(swatch);
            addHorizontalGap(container, 8);
        }
    }

    private View colorSwatch(String value, boolean selected) {
        View swatch = new View(activity);
        GradientDrawable drawable = bg(parseColorSafe(value, primaryColor()), 10);
        drawable.setStroke(dp(selected ? 3 : 1), selected ? textColor() : lineColor());
        swatch.setBackground(drawable);
        swatch.setLayoutParams(new LinearLayout.LayoutParams(dp(28), dp(28)));
        return swatch;
    }

    TextView emptyHint(String text) {
        TextView view = label(text, 13, mutedColor());
        view.setGravity(Gravity.CENTER);
        view.setBackground(border(panelColor(), lineColor(), 5));
        view.setPadding(dp(14), dp(18), dp(14), dp(18));
        return view;
    }

    void showDatePicker(String currentValue, Consumer<String> consumer) {
        LocalDate base = parseDate(currentValue);
        new DatePickerDialog(activity, (view, year, month, day) ->
                consumer.accept(LocalDate.of(year, month + 1, day).toString()),
                base.getYear(), base.getMonthValue() - 1, base.getDayOfMonth()).show();
    }

    void showTimePicker(String current, Consumer<String> consumer) {
        LocalTime base;
        try {
            base = LocalTime.parse(current);
        } catch (Exception ignored) {
            base = LocalTime.of(8, 0);
        }
        new TimePickerDialog(activity, (view, hour, minute) ->
                consumer.accept(String.format(Locale.CHINA, "%02d:%02d", hour, minute)),
                base.getHour(), base.getMinute(), true).show();
    }

    String eventDateLabel(String value) {
        try {
            ManualEvent helper = new ManualEvent("", "", value, "08:00", "09:00");
            return helper.fullDateLabel();
        } catch (Exception ignored) {
            return value;
        }
    }

    private LocalDate parseDate(String value) {
        try {
            return value == null || value.isEmpty() ? LocalDate.now() : LocalDate.parse(value);
        } catch (Exception ignored) {
            return LocalDate.now();
        }
    }

    GradientDrawable bg(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    GradientDrawable border(int fill, int stroke, int radiusDp) {
        GradientDrawable drawable = bg(fill, radiusDp);
        drawable.setStroke(dp(1), stroke);
        return drawable;
    }

    void addHorizontalGap(LinearLayout layout, int widthDp) {
        View gap = new View(activity);
        layout.addView(gap, new LinearLayout.LayoutParams(dp(widthDp), 1));
    }

    int backgroundColor() {
        return darkMode ? Color.rgb(17, 21, 28) : Color.rgb(247, 249, 252);
    }

    int surfaceColor() {
        return darkMode ? Color.rgb(28, 34, 43) : Color.rgb(239, 244, 249);
    }

    int panelColor() {
        return darkMode ? Color.rgb(24, 29, 37) : Color.WHITE;
    }

    int textColor() {
        return darkMode ? Color.rgb(245, 248, 252) : Color.rgb(25, 50, 77);
    }

    int mutedColor() {
        return darkMode ? Color.rgb(156, 176, 199) : Color.rgb(94, 113, 133);
    }

    int lineColor() {
        return darkMode ? Color.rgb(53, 62, 74) : Color.rgb(220, 227, 235);
    }

    int primaryColor() {
        return parseColorSafe(themeColor, Color.rgb(47, 128, 237));
    }

    int parseColorSafe(String value, int fallback) {
        try {
            return value == null ? fallback : Color.parseColor(value);
        } catch (Exception ignored) {
            return fallback;
        }
    }
}
