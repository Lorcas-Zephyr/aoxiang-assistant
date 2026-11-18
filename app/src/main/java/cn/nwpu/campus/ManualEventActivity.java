package cn.nwpu.campus;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.DatePickerDialog;
import android.app.TimePickerDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.function.Consumer;

/**
 * Standalone management screen for user-created calendar events.
 *
 * <p>The screen is self-contained: it needs no layout resource, no AndroidX and no
 * call into MainActivity. Events are stored in the shared "campus_private"
 * preferences through {@link ManualEventStore}, so the home page and the timetable
 * can render them with {@link ManualEventStore#load(SharedPreferences)} and
 * {@link ManualEventStore#onDate(List, LocalDate)}.</p>
 *
 * <p>It supports one-time events and weekly events repeated for 1-52 weeks, start
 * and end time, colour, notes, and reports conflicts with other manual events and
 * with scheduled courses of the selected semester.</p>
 */
public class ManualEventActivity extends Activity {
    /** Preferences file shared with MainActivity and the schedule. */
    public static final String PREFS_NAME = "campus_private";
    /** Optional ISO-8601 date used as the initial date of a new event. */
    public static final String EXTRA_DATE = "manual_event_date";

    private SharedPreferences store;
    private boolean darkMode;
    private String themeColor = ScheduleModels.DEFAULT_THEME_COLOR;
    private List<ManualEvent> manualEvents = new ArrayList<>();
    private List<ScheduleModels.Semester> semesters = new ArrayList<>();
    private List<ScheduleModels.Course> courses = new ArrayList<>();
    private String selectedSemesterId = "";
    private LocalDate anchorDate = LocalDate.now();
    private LinearLayout contentHost;
    private LinearLayout rootView;

    /** Opens the screen with today preselected for a new event. */
    public static Intent createIntent(android.content.Context context) {
        return new Intent(context, ManualEventActivity.class);
    }

    /** Opens the screen with {@code date} preselected for a new event. */
    public static Intent createIntent(android.content.Context context, LocalDate date) {
        Intent intent = new Intent(context, ManualEventActivity.class);
        if (date != null) {
            intent.putExtra(EXTRA_DATE, date.toString());
        }
        return intent;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        store = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        themeColor = ScheduleStorage.loadThemeColor(store);
        darkMode = ScheduleStorage.loadDarkMode(store);
        String extra = getIntent() == null ? null : getIntent().getStringExtra(EXTRA_DATE);
        if (extra != null && !extra.trim().isEmpty()) {
            try {
                anchorDate = LocalDate.parse(extra.trim());
            } catch (Exception ignored) {}
        }
        setContentView(buildRoot());
        applySystemBarInsets();
        applyWindowTheme();
        reloadState();
        refreshContent();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (contentHost != null) {
            reloadState();
            refreshContent();
        }
    }

    private void reloadState() {
        manualEvents = ManualEventStore.load(store);
        semesters = ScheduleStorage.loadSemesters(store);
        courses = ScheduleStorage.loadCourses(store);
        selectedSemesterId = ScheduleStorage.loadSelectedSemester(store);
        ensureSelectedSemester();
    }

    private View buildRoot() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(backgroundColor());
        rootView = root;

        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(12), dp(10), dp(12), dp(6));

        Button back = action("←", false);
        back.setContentDescription("返回");
        back.setOnClickListener(v -> finish());
        bar.addView(back, new LinearLayout.LayoutParams(dp(46), dp(40)));

        TextView title = label("手动日程", 20, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(0, -2, 1f);
        titleParams.leftMargin = dp(12);
        bar.addView(title, titleParams);

        Button add = action("＋ 事件", true);
        add.setOnClickListener(v -> showManualEventDialog(null, anchorDate));
        bar.addView(add, new LinearLayout.LayoutParams(dp(92), dp(40)));
        root.addView(bar);

        TextView hint = label("一次性或每周重复的自定义日程，保存后可在首页和日程页查看。", 11, mutedColor());
        hint.setPadding(dp(20), 0, dp(20), dp(4));
        root.addView(hint);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(backgroundColor());
        contentHost = new LinearLayout(this);
        contentHost.setOrientation(LinearLayout.VERTICAL);
        contentHost.setPadding(dp(16), dp(4), dp(16), dp(28));
        scroll.addView(contentHost, new LinearLayout.LayoutParams(-1, -2));
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1f));
        return root;
    }

    private void refreshContent() {
        if (contentHost == null) return;
        contentHost.removeAllViews();

        List<ManualEvent> todayEvents = ManualEventStore.onDate(manualEvents, LocalDate.now());
        contentHost.addView(sectionHeader("今日日程", todayEvents.size() + " 个"));
        if (todayEvents.isEmpty()) {
            contentHost.addView(emptyHint("今天没有日程，点右上角“＋ 事件”添加"));
        } else {
            for (ManualEvent event : todayEvents) contentHost.addView(manualEventRow(event, false));
        }

        List<ManualEvent> all = new ArrayList<>(manualEvents);
        ManualEventStore.sort(all);
        contentHost.addView(sectionHeader("全部日程", all.size() + " 个"));
        if (all.isEmpty()) {
            contentHost.addView(emptyHint("还没有手动日程"));
        } else {
            for (ManualEvent event : all) contentHost.addView(manualEventRow(event, true));
        }
    }

    private View manualEventRow(ManualEvent event, boolean showDate) {
        LinearLayout row = card(panelColor());
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(10), dp(9), dp(12), dp(9));

        View stripe = new View(this);
        stripe.setBackground(bg(parseColorSafe(event.color, primaryColor()), 2));
        row.addView(stripe, new LinearLayout.LayoutParams(dp(4), dp(44)));
        addHorizontalGap(row, 10);

        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        TextView title = label(event.title, 13, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        body.addView(title);
        String meta = (showDate ? event.dateLabel() + " · " : "") + event.timeRange()
                + (event.weekly ? " · " + event.repeatLabel() : "");
        TextView detail = label(meta, 10, mutedColor());
        detail.setMaxLines(2);
        body.addView(detail);
        String note = event.note == null ? "" : event.note.trim();
        if (!note.isEmpty()) {
            TextView noteView = label("备注：" + note, 11, mutedColor());
            noteView.setMaxLines(2);
            noteView.setPadding(0, dp(3), 0, 0);
            body.addView(noteView);
        }
        row.addView(body, new LinearLayout.LayoutParams(0, -2, 1f));
        row.setOnClickListener(v -> showManualEventDialog(event, event.localDate()));
        return row;
    }

    private void showManualEventDialog(ManualEvent editing, LocalDate presetDate) {
        boolean isEdit = editing != null;
        LocalDate initialDate = isEdit ? editing.localDate()
                : (presetDate == null ? LocalDate.now() : presetDate);
        final String[] chosenDate = {initialDate.toString()};
        final String[] startTime = {isEdit ? editing.startTime : "08:00"};
        final String[] endTime = {isEdit ? editing.endTime : "09:00"};
        final String[] chosenColor = {isEdit && editing.color != null ? editing.color : ManualEvent.DEFAULT_COLOR};

        ScrollView scroll = new ScrollView(this);
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(22), dp(2), dp(22), 0);
        scroll.addView(form);

        EditText titleInput = field(form, "日程名称", isEdit ? editing.title : "");
        styleDialogInput(titleInput);
        addFormLabel(form, "备注（可选）");
        EditText noteInput = multilineField(form, "地点、要带的东西、补充说明…",
                isEdit && editing.note != null ? editing.note : "");

        addFormLabel(form, "日期");
        final TextView dateValue = inputLike(eventDateLabel(chosenDate[0]));
        dateValue.setOnClickListener(v -> showDatePicker(chosenDate[0], value -> {
            chosenDate[0] = value;
            dateValue.setText(eventDateLabel(value));
        }));
        form.addView(dateValue, new LinearLayout.LayoutParams(-1, dp(48)));

        addFormLabel(form, "时间");
        LinearLayout timeRow = new LinearLayout(this);
        timeRow.setGravity(Gravity.CENTER_VERTICAL);
        final TextView startValue = inputLike(startTime[0]);
        startValue.setOnClickListener(v -> showTimePicker(startTime[0], value -> {
            startTime[0] = value;
            startValue.setText(value);
        }));
        timeRow.addView(startValue, new LinearLayout.LayoutParams(0, dp(48), 1f));
        TextView dash = label("至", 12, mutedColor());
        dash.setGravity(Gravity.CENTER);
        timeRow.addView(dash, new LinearLayout.LayoutParams(dp(30), dp(48)));
        final TextView endValue = inputLike(endTime[0]);
        endValue.setOnClickListener(v -> showTimePicker(endTime[0], value -> {
            endTime[0] = value;
            endValue.setText(value);
        }));
        timeRow.addView(endValue, new LinearLayout.LayoutParams(0, dp(48), 1f));
        form.addView(timeRow);

        addFormLabel(form, "重复");
        final CheckBox weeklyInput = new CheckBox(this);
        weeklyInput.setText("每周重复（按开始日期的星期几）");
        weeklyInput.setTextSize(12);
        weeklyInput.setTextColor(textColor());
        weeklyInput.setChecked(isEdit && editing.weekly);
        weeklyInput.setButtonTintList(ColorStateList.valueOf(primaryColor()));
        form.addView(weeklyInput);

        final LinearLayout weeksBox = new LinearLayout(this);
        weeksBox.setOrientation(LinearLayout.VERTICAL);
        LinearLayout weeksRow = new LinearLayout(this);
        weeksRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView weeksLabel = label("持续周数", 12, textColor());
        weeksRow.addView(weeksLabel, new LinearLayout.LayoutParams(0, -2, 1f));
        final EditText weeksInput = new EditText(this);
        weeksInput.setSingleLine(true);
        weeksInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        weeksInput.setHint("例如 3");
        weeksInput.setText(String.valueOf(isEdit && editing.weekly ? Math.max(1, editing.repeatWeeks) : 3));
        weeksInput.setTextSize(13);
        weeksInput.setTextColor(textColor());
        weeksInput.setHintTextColor(mutedColor());
        weeksInput.setPadding(dp(14), 0, dp(14), 0);
        weeksInput.setBackground(border(surfaceColor(), lineColor(), 8));
        weeksRow.addView(weeksInput, new LinearLayout.LayoutParams(dp(96), dp(44)));
        weeksBox.addView(weeksRow);
        TextView weeksHint = label("填 1-52，例如 3 表示连续三周；仅一次时无需填写。", 10, mutedColor());
        weeksHint.setPadding(0, dp(3), 0, 0);
        weeksBox.addView(weeksHint);
        weeksBox.setVisibility(weeklyInput.isChecked() ? View.VISIBLE : View.GONE);
        weeklyInput.setOnCheckedChangeListener((button, checked) -> {
            weeksBox.setVisibility(checked ? View.VISIBLE : View.GONE);
            if (checked && weeksInput.getText().toString().trim().isEmpty()) weeksInput.setText("3");
        });
        form.addView(weeksBox);

        addFormLabel(form, "颜色");
        LinearLayout swatches = new LinearLayout(this);
        swatches.setGravity(Gravity.CENTER_VERTICAL);
        form.addView(swatches);
        refreshEventSwatches(swatches, chosenColor[0], value -> {
            chosenColor[0] = value;
            refreshEventSwatches(swatches, value, ignored -> {});
        });

        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setTitle(isEdit ? "编辑日程" : "新增日程")
                .setView(scroll)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", null);
        if (isEdit) builder.setNeutralButton("删除", null);
        AlertDialog dialog = builder.create();
        dialog.setOnShowListener(ignored -> {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                String title = titleInput.getText().toString().trim();
                if (title.isEmpty()) {
                    Toast.makeText(this, "请输入日程名称", Toast.LENGTH_SHORT).show();
                    return;
                }
                try {
                    LocalTime start = LocalTime.parse(startTime[0]);
                    LocalTime end = LocalTime.parse(endTime[0]);
                    if (!end.isAfter(start)) {
                        Toast.makeText(this, "结束时间需晚于开始时间", Toast.LENGTH_SHORT).show();
                        return;
                    }
                    LocalDate date = LocalDate.parse(chosenDate[0]);
                    boolean weekly = weeklyInput.isChecked();
                    int durationWeeks = 1;
                    if (weekly) {
                        try {
                            durationWeeks = Integer.parseInt(weeksInput.getText().toString().trim());
                        } catch (Exception parseError) {
                            durationWeeks = 0;
                        }
                        if (durationWeeks < 1 || durationWeeks > 52) {
                            Toast.makeText(this, "持续周数需在 1-52 之间", Toast.LENGTH_SHORT).show();
                            return;
                        }
                    }
                    ManualEvent event = new ManualEvent(
                            isEdit ? editing.id : "event-" + System.currentTimeMillis(),
                            title, date.toString(), startTime[0], endTime[0]);
                    event.note = emptyToNull(noteInput.getText().toString());
                    event.color = chosenColor[0];
                    event.weekly = weekly;
                    event.repeatWeeks = weekly ? durationWeeks : 1;

                    String conflict = findManualEventConflict(event, isEdit ? editing.id : null);
                    if (conflict != null) {
                        Toast.makeText(this, "时间冲突：" + conflict, Toast.LENGTH_LONG).show();
                        return;
                    }

                    if (isEdit) {
                        for (int i = 0; i < manualEvents.size(); i++) {
                            if (editing.id.equals(manualEvents.get(i).id)) {
                                manualEvents.set(i, event);
                                break;
                            }
                        }
                    } else {
                        manualEvents.add(event);
                    }
                    ManualEventStore.save(store, manualEvents);
                    setResult(RESULT_OK);
                    dialog.dismiss();
                    reloadState();
                    refreshContent();
                } catch (Exception error) {
                    Toast.makeText(this, "时间格式不正确", Toast.LENGTH_SHORT).show();
                }
            });
            if (isEdit) {
                dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> {
                    dialog.dismiss();
                    new AlertDialog.Builder(this)
                            .setTitle("删除日程")
                            .setMessage("确定删除「" + editing.title + "」吗？")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("删除", (confirm, which) -> {
                                manualEvents.remove(editing);
                                ManualEventStore.save(store, manualEvents);
                                setResult(RESULT_OK);
                                reloadState();
                                refreshContent();
                            })
                            .show();
                });
            }
        });
        dialog.show();
    }

    private String findManualEventConflict(ManualEvent candidate, String excludeId) {
        int candidateStart = minutesOfDay(candidate.startTime);
        int candidateEnd = minutesOfDay(candidate.endTime);
        if (candidateStart < 0 || candidateEnd <= candidateStart) return null;
        int occurrences = candidate.weekly ? Math.max(1, candidate.repeatWeeks) : 1;
        LocalDate start = candidate.localDate();
        for (int index = 0; index < occurrences; index++) {
            LocalDate date = start.plusWeeks(index);
            for (ManualEvent other : ManualEventStore.onDate(manualEvents, date)) {
                if (other == null) continue;
                if (excludeId != null && excludeId.equals(other.id)) continue;
                int otherStart = minutesOfDay(other.startTime);
                int otherEnd = minutesOfDay(other.endTime);
                if (otherStart >= 0 && otherEnd > otherStart
                        && candidateStart < otherEnd && candidateEnd > otherStart) {
                    return "与日程「" + other.title + "」在 " + ManualEvent.formatDateLabel(date)
                            + " " + other.timeRange() + " 冲突";
                }
            }
            String courseConflict = findCourseConflict(candidate, date, candidateStart, candidateEnd);
            if (courseConflict != null) return courseConflict;
        }
        return null;
    }

    private String findCourseConflict(ManualEvent candidate, LocalDate date, int candidateStart, int candidateEnd) {
        ScheduleModels.Semester semester = selectedSemester();
        if (semester == null) return null;
        int week = ScheduleUtils.weekNumberForDate(date, semester);
        if (week <= 0) return null;
        int day = date.getDayOfWeek().getValue();
        for (ScheduleModels.Course course : coursesForSemester(semester.id)) {
            for (ScheduleModels.TimeSlot slot : course.timeSlots) {
                if (slot.dayOfWeek != day
                        || !ScheduleUtils.isWeekInRange(week, slot.weekRange)
                        || !ScheduleUtils.matchesRepeatRule(week, slot.repeatRule)
                        || slot.classSections == null || slot.classSections.isEmpty()) {
                    continue;
                }
                int first = Collections.min(slot.classSections);
                int last = Collections.max(slot.classSections);
                if (first < 1 || last > semester.sectionCount) continue;
                int courseStart = sectionStartMinutes(semester, course, slot, date, first);
                int courseEnd = sectionEndMinutes(semester, course, slot, date, last);
                if (courseEnd <= courseStart) continue;
                if (candidateStart < courseEnd && candidateEnd > courseStart) {
                    return "与课程「" + course.name + "」在 " + ManualEvent.formatDateLabel(date)
                            + " " + formatMinutes(courseStart) + "–" + formatMinutes(courseEnd) + " 冲突";
                }
            }
        }
        return null;
    }

    private void ensureSelectedSemester() {
        if (selectedSemesterId != null && !selectedSemesterId.isEmpty()) {
            for (ScheduleModels.Semester semester : semesters) {
                if (semester.id.equals(selectedSemesterId)) return;
            }
        }
        selectedSemesterId = semesters.isEmpty() ? "" : semesters.get(0).id;
    }

    private ScheduleModels.Semester selectedSemester() {
        for (ScheduleModels.Semester semester : semesters) {
            if (semester.id.equals(selectedSemesterId)) return semester;
        }
        return null;
    }

    private List<ScheduleModels.Course> coursesForSemester(String semesterId) {
        List<ScheduleModels.Course> result = new ArrayList<>();
        if (semesterId == null) return result;
        for (ScheduleModels.Course course : courses) {
            if (course != null && semesterId.equals(course.semesterId)) result.add(course);
        }
        return result;
    }

    private int sectionStartMinutes(ScheduleModels.Semester semester, ScheduleModels.Course course,
                                    ScheduleModels.TimeSlot slot, LocalDate date, int section) {
        String location = slot != null && slot.location != null
                ? slot.location : (course == null ? null : course.location);
        ScheduleModels.SectionTime time = ScheduleModels.sectionTimeFor(semester, location, date, section);
        if (time != null) {
            int value = minutesOfDay(time.start);
            if (value >= 0) return value;
        }
        return 8 * 60 + Math.max(0, section - 1) * 60;
    }

    private int sectionEndMinutes(ScheduleModels.Semester semester, ScheduleModels.Course course,
                                  ScheduleModels.TimeSlot slot, LocalDate date, int section) {
        String location = slot != null && slot.location != null
                ? slot.location : (course == null ? null : course.location);
        ScheduleModels.SectionTime time = ScheduleModels.sectionTimeFor(semester, location, date, section);
        if (time != null) {
            int value = minutesOfDay(time.end);
            if (value > 0) return value;
        }
        return sectionStartMinutes(semester, course, slot, date, section) + 45;
    }

    private int minutesOfDay(String value) {
        try {
            LocalTime time = LocalTime.parse(value);
            return time.getHour() * 60 + time.getMinute();
        } catch (Exception ignored) {
            return -1;
        }
    }

    private String formatMinutes(int value) {
        int safe = Math.max(0, value);
        return String.format(Locale.CHINA, "%02d:%02d", safe / 60, safe % 60);
    }

    private void styleDialogInput(EditText input) {
        input.setTextColor(textColor());
        input.setHintTextColor(mutedColor());
        input.setPadding(dp(14), 0, dp(14), 0);
        input.setBackground(border(surfaceColor(), lineColor(), 8));
    }

    private void showDatePicker(String currentValue, Consumer<String> consumer) {
        LocalDate base = currentValue == null || currentValue.isEmpty()
                ? LocalDate.now() : LocalDate.parse(currentValue);
        DatePickerDialog picker = new DatePickerDialog(this, (view, year, month, day) ->
                consumer.accept(LocalDate.of(year, month + 1, day).toString()),
                base.getYear(), base.getMonthValue() - 1, base.getDayOfMonth());
        picker.show();
    }

    private void showTimePicker(String current, Consumer<String> consumer) {
        LocalTime base;
        try {
            base = LocalTime.parse(current);
        } catch (Exception ignored) {
            base = LocalTime.of(8, 0);
        }
        new TimePickerDialog(this, (view, hour, minute) ->
                consumer.accept(String.format(Locale.CHINA, "%02d:%02d", hour, minute)),
                base.getHour(), base.getMinute(), true).show();
    }

    private String eventDateLabel(String value) {
        try {
            ManualEvent helper = new ManualEvent("", "", value, "08:00", "09:00");
            return helper.fullDateLabel();
        } catch (Exception ignored) {
            return value;
        }
    }

    private void addFormLabel(LinearLayout parent, String text) {
        TextView view = label(text, 11, mutedColor());
        view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(0, dp(9), 0, dp(4));
        parent.addView(view);
    }

    private EditText multilineField(LinearLayout parent, String hint, String value) {
        EditText input = new EditText(this);
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

    private TextView inputLike(String value) {
        TextView view = label(value, 13, textColor());
        view.setGravity(Gravity.CENTER_VERTICAL);
        view.setPadding(dp(14), 0, dp(14), 0);
        view.setBackground(border(surfaceColor(), lineColor(), 8));
        view.setClickable(true);
        return view;
    }

    private void refreshEventSwatches(LinearLayout container, String chosen, Consumer<String> onChoose) {
        container.removeAllViews();
        for (String value : ScheduleModels.PRESET_COLORS) {
            View swatch = colorSwatch(value, value.equals(chosen));
            swatch.setOnClickListener(v -> onChoose.accept(value));
            container.addView(swatch);
            addHorizontalGap(container, 8);
        }
    }

    private EditText field(LinearLayout parent, String hint, String value) {
        EditText input = new EditText(this);
        input.setHint(hint);
        if (value != null) input.setText(value);
        parent.addView(input, new LinearLayout.LayoutParams(-1, dp(58)));
        return input;
    }

    private LinearLayout sectionHeader(String heading, String trailing) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView text = section(heading);
        row.addView(text, new LinearLayout.LayoutParams(0, dp(54), 1f));
        if (trailing != null && !trailing.isEmpty()) {
            TextView count = label(trailing, 11, mutedColor());
            count.setGravity(Gravity.CENTER_VERTICAL | Gravity.END);
            row.addView(count, new LinearLayout.LayoutParams(-2, dp(54)));
        }
        return row;
    }

    private TextView section(String text) {
        TextView view = label(text, 13, mutedColor());
        view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return view;
    }

    private TextView label(String text, float size, int color) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setGravity(Gravity.CENTER_VERTICAL);
        return view;
    }

    private LinearLayout card(int color) {
        LinearLayout container = new LinearLayout(this);
        container.setOrientation(LinearLayout.VERTICAL);
        container.setBackground(border(color, lineColor(), 5));
        container.setPadding(dp(14), dp(12), dp(14), dp(12));
        return container;
    }

    private GradientDrawable bg(int color, int radiusDp) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radiusDp));
        return drawable;
    }

    private GradientDrawable border(int fill, int stroke, int radiusDp) {
        GradientDrawable drawable = bg(fill, radiusDp);
        drawable.setStroke(dp(1), stroke);
        return drawable;
    }

    private Button action(String text, boolean filled) {
        Button button = new Button(this);
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

    private View colorSwatch(String value, boolean selected) {
        View swatch = new View(this);
        GradientDrawable drawable = bg(Color.parseColor(value), 10);
        drawable.setStroke(dp(selected ? 3 : 1), selected ? textColor() : lineColor());
        swatch.setBackground(drawable);
        swatch.setLayoutParams(new LinearLayout.LayoutParams(dp(28), dp(28)));
        return swatch;
    }

    private TextView emptyHint(String text) {
        TextView view = label(text, 13, mutedColor());
        view.setGravity(Gravity.CENTER);
        view.setBackground(border(panelColor(), lineColor(), 5));
        view.setPadding(dp(14), dp(18), dp(14), dp(18));
        return view;
    }

    private void applySystemBarInsets() {
        if (rootView == null) return;
        rootView.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
            return insets;
        });
        rootView.requestApplyInsets();
    }

    private void applyWindowTheme() {
        Window window = getWindow();
        window.setStatusBarColor(backgroundColor());
        View decor = window.getDecorView();
        int flags = decor.getSystemUiVisibility();
        if (darkMode) {
            flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
        } else {
            flags |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
        }
        decor.setSystemUiVisibility(flags);
    }

    private int backgroundColor() {
        return darkMode ? Color.rgb(17, 21, 28) : Color.rgb(247, 249, 252);
    }

    private int surfaceColor() {
        return darkMode ? Color.rgb(28, 34, 43) : Color.rgb(239, 244, 249);
    }

    private int panelColor() {
        return darkMode ? Color.rgb(24, 29, 37) : Color.WHITE;
    }

    private int textColor() {
        return darkMode ? Color.rgb(245, 248, 252) : Color.rgb(25, 50, 77);
    }

    private int mutedColor() {
        return darkMode ? Color.rgb(156, 176, 199) : Color.rgb(94, 113, 133);
    }

    private int lineColor() {
        return darkMode ? Color.rgb(53, 62, 74) : Color.rgb(220, 227, 235);
    }

    private int primaryColor() {
        return parseColorSafe(themeColor, Color.rgb(47, 128, 237));
    }

    private int parseColorSafe(String value, int fallback) {
        try {
            return value == null ? fallback : Color.parseColor(value);
        } catch (Exception ignored) {
            return fallback;
        }
    }

    private String emptyToNull(String value) {
        return value == null || value.trim().isEmpty() ? null : value.trim();
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void addHorizontalGap(LinearLayout layout, int widthDp) {
        View gap = new View(this);
        layout.addView(gap, new LinearLayout.LayoutParams(dp(widthDp), 1));
    }
}
