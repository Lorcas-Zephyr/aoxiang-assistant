package cn.nwpu.campus;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.time.LocalDateTime;
import java.util.List;

/** Complete exam list, including exams that have already ended. */
public class ExamListActivity extends Activity {
    private ChecklistUi ui;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        android.content.SharedPreferences prefs =
                getSharedPreferences("campus_private", MODE_PRIVATE);
        boolean dark = ScheduleStorage.loadDarkMode(prefs);
        ui = new ChecklistUi(this, dark, ScheduleStorage.loadThemeColor(prefs));
        int background = ui.backgroundColor();
        int surface = ui.panelColor();
        int text = ui.textColor();
        int muted = ui.mutedColor();
        int line = ui.lineColor();

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(background);

        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(16), dp(16), dp(16), dp(10));
        android.widget.ImageView back = ui.iconButton(R.drawable.ic_arrow_back, "返回");
        back.setOnClickListener(v -> finish());
        toolbar.addView(back, new LinearLayout.LayoutParams(dp(40), dp(40)));

        LinearLayout heading = new LinearLayout(this);
        heading.setOrientation(LinearLayout.VERTICAL);
        heading.setPadding(dp(12), 0, 0, 0);
        TextView title = text("全部考试", 24, text);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        heading.addView(title);
        List<ScheduleModels.Exam> exams = ExamStorage.sorted(ExamStorage.load(prefs));
        heading.addView(text("共 " + exams.size() + " 场 · 包含已结束考试", 11, muted));
        toolbar.addView(heading, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(toolbar);

        ScrollView scroll = new ScrollView(this);
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setPadding(dp(16), dp(10), dp(16), dp(20));
        if (exams.isEmpty()) {
            TextView empty = text("暂无考试安排", 14, muted);
            empty.setGravity(Gravity.CENTER);
            list.addView(empty, new LinearLayout.LayoutParams(-1, dp(140)));
        } else {
            LocalDateTime now = LocalDateTime.now();
            for (ScheduleModels.Exam exam : exams) {
                list.addView(examCard(exam, ExamStorage.isFinished(exam, now),
                        surface, text, muted, line));
            }
        }
        scroll.addView(list);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        setContentView(root);
        if (Build.VERSION.SDK_INT >= 21) {
            root.setOnApplyWindowInsetsListener((view, insets) -> {
                view.setPadding(0, insets.getSystemWindowInsetTop(),
                        0, insets.getSystemWindowInsetBottom());
                return insets;
            });
            root.requestApplyInsets();
            getWindow().setStatusBarColor(background);
            getWindow().setNavigationBarColor(background);
            int flags = root.getSystemUiVisibility();
            if (dark) flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            else flags |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            root.setSystemUiVisibility(flags);
        }
    }

    private View examCard(ScheduleModels.Exam exam, boolean finished, int surface,
                          int textColor, int mutedColor, int lineColor) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(dp(10), dp(10), dp(12), dp(10));
        card.setBackground(roundRect(surface, lineColor, 12));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.bottomMargin = dp(10);
        card.setLayoutParams(params);

        View accent = new View(this);
        accent.setBackground(roundRect(Color.parseColor(ExamStorage.EXAM_COLOR),
                Color.TRANSPARENT, 3));
        card.addView(accent, new LinearLayout.LayoutParams(dp(4), dp(54)));
        View gap = new View(this);
        card.addView(gap, new LinearLayout.LayoutParams(dp(10), 1));

        LinearLayout details = new LinearLayout(this);
        details.setOrientation(LinearLayout.VERTICAL);
        TextView name = text(exam.name, 15, textColor);
        name.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        name.setMaxLines(8);
        details.addView(name);
        String time = exam.date;
        if (!exam.startTime.isEmpty()) {
            time += "  " + exam.startTime
                    + (exam.endTime.isEmpty() ? "" : "–" + exam.endTime);
        }
        details.addView(text(time, 12, finished ? mutedColor : ui.primaryColor()));
        if (!exam.type.isEmpty()) details.addView(text("类型：" + exam.type, 11, mutedColor));
        if (!exam.location.isEmpty()) details.addView(text("地点：" + exam.location, 11, mutedColor));
        if (!exam.seat.isEmpty()) details.addView(text("座位：" + exam.seat, 11, mutedColor));
        card.addView(details, new LinearLayout.LayoutParams(0, -2, 1));

        TextView status = text(finished ? "已结束" : "待考", 10,
                finished ? mutedColor : ui.primaryColor());
        status.setGravity(Gravity.CENTER);
        card.addView(status, new LinearLayout.LayoutParams(dp(44), dp(28)));
        return card;
    }

    private TextView text(String value, float size, int color) {
        TextView view = new TextView(this);
        view.setText(value == null ? "" : value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setLineSpacing(dp(2), 1f);
        return view;
    }

    private GradientDrawable roundRect(int fill, int stroke, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(fill);
        drawable.setCornerRadius(dp(radiusDp));
        if (stroke != Color.TRANSPARENT) drawable.setStroke(dp(1), stroke);
        return drawable;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
