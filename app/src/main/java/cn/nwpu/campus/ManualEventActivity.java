package cn.nwpu.campus;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/** 手动日程列表页。编辑弹窗和冲突检查分别放在 ManualEventEditor、ManualEventConflictChecker。 */
public class ManualEventActivity extends Activity {
    public static final String PREFS_NAME = "campus_private";
    public static final String EXTRA_DATE = "manual_event_date";

    private SharedPreferences store;
    private ManualEventUi ui;
    private List<ManualEvent> manualEvents = new ArrayList<>();
    private List<ScheduleModels.Semester> semesters = new ArrayList<>();
    private List<ScheduleModels.Course> courses = new ArrayList<>();
    private String selectedSemesterId = "";
    private LocalDate anchorDate = LocalDate.now();
    private LinearLayout contentHost;
    private LinearLayout rootView;
    private boolean darkMode;

    public static Intent createIntent(android.content.Context context) {
        return new Intent(context, ManualEventActivity.class);
    }

    public static Intent createIntent(android.content.Context context, LocalDate date) {
        Intent intent = new Intent(context, ManualEventActivity.class);
        if (date != null) intent.putExtra(EXTRA_DATE, date.toString());
        return intent;
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        store = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        darkMode = ScheduleStorage.loadDarkMode(store);
        ui = new ManualEventUi(this, darkMode, ScheduleStorage.loadThemeColor(store));
        readAnchorDate();
        setContentView(buildRoot());
        applySystemBarInsets();
        applyWindowTheme();
        reload();
        refreshList();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (contentHost == null) return;
        reload();
        refreshList();
    }

    private void readAnchorDate() {
        String extra = getIntent() == null ? null : getIntent().getStringExtra(EXTRA_DATE);
        if (extra == null || extra.trim().isEmpty()) return;
        try {
            anchorDate = LocalDate.parse(extra.trim());
        } catch (Exception ignored) {
            anchorDate = LocalDate.now();
        }
    }

    private void reload() {
        manualEvents = ManualEventStore.load(store);
        semesters = ScheduleStorage.loadSemesters(store);
        courses = ScheduleStorage.loadCourses(store);
        selectedSemesterId = ScheduleStorage.loadSelectedSemester(store);
        ensureSelectedSemester();
    }

    private View buildRoot() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(ui.backgroundColor());
        rootView = root;

        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(ui.dp(12), ui.dp(10), ui.dp(12), ui.dp(6));

        ImageView back = ui.iconButton(R.drawable.ic_arrow_back, "返回");
        back.setOnClickListener(v -> finish());
        bar.addView(back, new LinearLayout.LayoutParams(ui.dp(40), ui.dp(40)));

        TextView title = ui.label("手动日程", 20, ui.textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(0, -2, 1f);
        titleParams.leftMargin = ui.dp(12);
        bar.addView(title, titleParams);

        Button add = ui.action("＋ 事件", true);
        add.setOnClickListener(v -> openEditor(null, anchorDate));
        bar.addView(add, new LinearLayout.LayoutParams(ui.dp(92), ui.dp(40)));
        root.addView(bar);

        TextView hint = ui.label("一次性或每周重复的自定义日程，保存后可在事项页和课表查看。",
                11, ui.mutedColor());
        hint.setPadding(ui.dp(20), 0, ui.dp(20), ui.dp(4));
        root.addView(hint);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(ui.backgroundColor());
        contentHost = new LinearLayout(this);
        contentHost.setOrientation(LinearLayout.VERTICAL);
        contentHost.setPadding(ui.dp(16), ui.dp(4), ui.dp(16), ui.dp(28));
        scroll.addView(contentHost, new LinearLayout.LayoutParams(-1, -2));
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));
        return root;
    }

    private void refreshList() {
        if (contentHost == null) return;
        contentHost.removeAllViews();

        List<ManualEvent> today = ManualEventStore.onDate(manualEvents, LocalDate.now());
        contentHost.addView(ui.sectionHeader("今日日程", today.size() + " 个"));
        if (today.isEmpty()) {
            contentHost.addView(ui.emptyHint("今天没有日程，点右上角“＋ 事件”添加"));
        } else {
            for (ManualEvent event : today) contentHost.addView(eventRow(event, false));
        }

        List<ManualEvent> all = new ArrayList<>(manualEvents);
        ManualEventStore.sort(all);
        contentHost.addView(ui.sectionHeader("全部日程", all.size() + " 个"));
        if (all.isEmpty()) {
            contentHost.addView(ui.emptyHint("还没有手动日程"));
        } else {
            for (ManualEvent event : all) contentHost.addView(eventRow(event, true));
        }
    }

    private View eventRow(ManualEvent event, boolean showDate) {
        LinearLayout row = ui.card(ui.panelColor());
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(ui.dp(10), ui.dp(9), ui.dp(12), ui.dp(9));

        View stripe = new View(this);
        stripe.setBackground(ui.bg(ui.parseColorSafe(event.color, ui.primaryColor()), 2));
        row.addView(stripe, new LinearLayout.LayoutParams(ui.dp(4), ui.dp(44)));
        ui.addHorizontalGap(row, 10);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        TextView title = ui.label(event.title, 13, ui.textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        body.addView(title);

        String meta = (showDate ? event.dateLabel() + " · " : "") + event.timeRange()
                + (event.weekly ? " · " + event.repeatLabel() : "");
        TextView detail = ui.label(meta, 10, ui.mutedColor());
        detail.setMaxLines(2);
        body.addView(detail);

        String note = event.note == null ? "" : event.note.trim();
        if (!note.isEmpty()) {
            TextView noteView = ui.label("备注：" + note, 11, ui.mutedColor());
            noteView.setMaxLines(2);
            noteView.setPadding(0, ui.dp(3), 0, 0);
            body.addView(noteView);
        }
        row.addView(body, new LinearLayout.LayoutParams(0, -2, 1f));
        row.setOnClickListener(v -> openEditor(event, event.localDate()));
        return row;
    }

    private void openEditor(ManualEvent editing, LocalDate presetDate) {
        ManualEventConflictChecker checker = new ManualEventConflictChecker(
                manualEvents, semesters, courses, selectedSemesterId);
        new ManualEventEditor(this, ui, store, manualEvents, checker, editing, presetDate,
                () -> {
                    setResult(RESULT_OK);
                    reload();
                    refreshList();
                }).show();
    }

    private void ensureSelectedSemester() {
        if (selectedSemesterId != null && !selectedSemesterId.isEmpty()) {
            for (ScheduleModels.Semester semester : semesters) {
                if (semester.id.equals(selectedSemesterId)) return;
            }
        }
        selectedSemesterId = semesters.isEmpty() ? "" : semesters.get(0).id;
    }

    private void applySystemBarInsets() {
        rootView.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
            return insets;
        });
        rootView.requestApplyInsets();
    }

    private void applyWindowTheme() {
        Window window = getWindow();
        window.setStatusBarColor(ui.backgroundColor());
        View decor = window.getDecorView();
        int flags = decor.getSystemUiVisibility();
        if (darkMode) {
            flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
        } else {
            flags |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
        }
        decor.setSystemUiVisibility(flags);
    }
}
