package cn.nwpu.campus;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.function.Consumer;

/** 清单页的 UI 辅助：颜色、控件、日期格式、提醒选项。 */
final class ChecklistUi {
    static final String[] REMINDER_LABELS = {
            "不提醒", "截止时提醒", "提前 5 分钟", "提前 15 分钟",
            "提前 30 分钟", "提前 1 小时", "提前 1 天"
    };
    static final int[] REMINDER_VALUES = {-1, 0, 5, 15, 30, 60, 1440};

    private static final DateTimeFormatter DATE_LABEL = DateTimeFormatter.ofPattern("yyyy年M月d日", Locale.CHINA);

    private final Activity activity;
    private final boolean darkMode;
    private final String themeColor;

    ChecklistUi(Activity activity, boolean darkMode, String themeColor) {
        this.activity = activity;
        this.darkMode = darkMode;
        this.themeColor = themeColor;
    }

    int dp(int value) {
        return Math.round(activity.getResources().getDisplayMetrics().density * value);
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
        layout.setBackground(border(color, lineColor(), 8));
        layout.setPadding(dp(14), dp(12), dp(14), dp(12));
        return layout;
    }

    Button action(String text, boolean filled) {
        Button button = new Button(activity);
        button.setText(text);
        button.setTextSize(12);
        button.setAllCaps(false);
        button.setTextColor(filled ? Color.WHITE : primaryColor());
        button.setMinHeight(dp(42));
        button.setMinWidth(0);
        button.setPadding(dp(10), 0, dp(10), 0);
        button.setBackground(border(filled ? primaryColor() : panelColor(),
                filled ? primaryColor() : lineColor(), 8));
        button.setStateListAnimator(null);
        applyOutline(button, 8, 1);
        return button;
    }

    ImageView iconButton(int resource, String description) {
        ImageView button = new ImageView(activity);
        button.setImageResource(resource);
        button.setColorFilter(primaryColor());
        button.setContentDescription(description);
        button.setPadding(dp(9), dp(9), dp(9), dp(9));
        button.setBackground(border(panelColor(), lineColor(), 8));
        return button;
    }

    EditText field(LinearLayout parent, String hint, String value) {
        EditText input = new EditText(activity);
        input.setHint(hint);
        if (value != null) input.setText(value);
        input.setTextColor(textColor());
        input.setHintTextColor(mutedColor());
        input.setPadding(dp(14), 0, dp(14), 0);
        input.setBackground(border(surfaceColor(), lineColor(), 8));
        parent.addView(input, new LinearLayout.LayoutParams(-1, dp(52)));
        return input;
    }

    EditText input(String hint) {
        EditText input = new EditText(activity);
        input.setHint(hint);
        input.setTextColor(textColor());
        input.setHintTextColor(mutedColor());
        input.setPadding(dp(12), 0, dp(12), 0);
        input.setBackground(border(surfaceColor(), lineColor(), 8));
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

    LinearLayout progressBar(float fraction) {
        LinearLayout track = new LinearLayout(activity);
        track.setOrientation(LinearLayout.HORIZONTAL);
        track.setBackground(bg(lineColor(), 3));
        fillProgressTrack(track, fraction);
        return track;
    }

    void fillProgressTrack(LinearLayout track, float fraction) {
        if (track == null) return;
        track.removeAllViews();
        float safe = Math.max(0f, Math.min(1f, fraction));
        View fill = new View(activity);
        fill.setBackground(bg(safe >= 1f ? successColor() : primaryColor(), 3));
        track.addView(fill, new LinearLayout.LayoutParams(0, dp(4), safe));
        View rest = new View(activity);
        track.addView(rest, new LinearLayout.LayoutParams(0, dp(4), 1f - safe));
    }

    void showReminderPicker(int current, Consumer<Integer> callback) {
        int checked = 0;
        for (int i = 0; i < REMINDER_VALUES.length; i++) {
            if (REMINDER_VALUES[i] == current) {
                checked = i;
                break;
            }
        }
        new AlertDialog.Builder(activity)
                .setTitle("提前提醒")
                .setSingleChoiceItems(REMINDER_LABELS, checked, (dialog, which) -> {
                    callback.accept(REMINDER_VALUES[which]);
                    dialog.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    String reminderLabel(int value) {
        for (int i = 0; i < REMINDER_VALUES.length; i++) {
            if (REMINDER_VALUES[i] == value) return REMINDER_LABELS[i];
        }
        return REMINDER_LABELS[4];
    }

    String dateLabel(String value) {
        return DATE_LABEL.format(parseDate(value));
    }

    LocalDate parseDate(String value) {
        try {
            return LocalDate.parse(value);
        } catch (Exception ignored) {
            return LocalDate.now();
        }
    }

    LocalTime parseTime(String value) {
        try {
            return LocalTime.parse(value);
        } catch (Exception ignored) {
            return LocalTime.of(23, 59);
        }
    }

    void applyOutline(View view, int radiusDp, int elevationDp) {
        view.setElevation(dp(elevationDp));
        view.setOutlineProvider(new ViewOutlineProvider() {
            @Override
            public void getOutline(View target, Outline outline) {
                if (target.getWidth() > 0 && target.getHeight() > 0) {
                    outline.setRoundRect(0, 0, target.getWidth(), target.getHeight(), dp(radiusDp));
                }
            }
        });
        view.setClipToOutline(true);
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

    void addGap(LinearLayout parent, int heightDp) {
        View gap = new View(activity);
        parent.addView(gap, new LinearLayout.LayoutParams(-1, dp(heightDp)));
    }

    void addHorizontalGap(LinearLayout parent, int widthDp) {
        View gap = new View(activity);
        parent.addView(gap, new LinearLayout.LayoutParams(dp(widthDp), 1));
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

    int successColor() {
        return darkMode ? Color.rgb(126, 226, 168) : Color.rgb(33, 150, 83);
    }

    int warningColor() {
        return darkMode ? Color.rgb(255, 138, 128) : Color.rgb(198, 40, 40);
    }

    int parseColorSafe(String value, int fallback) {
        try {
            return Color.parseColor(value);
        } catch (Exception ignored) {
            return fallback;
        }
    }
}
