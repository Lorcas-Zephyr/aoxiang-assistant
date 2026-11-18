package cn.nwpu.campus;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.DatePickerDialog;
import android.app.Dialog;
import android.app.NotificationManager;
import android.app.TimePickerDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.view.Window;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.function.Consumer;

/** Full checklist manager. Kept dependency-free and styled like the rest of the app. */
public class ChecklistActivity extends Activity {
    public static final String EXTRA_CHECKLIST_ID = "checklist_id";
    private static final int REQUEST_NOTIFICATIONS = 41;
    private static final String[] REMINDER_LABELS = {
            "不提醒", "截止时提醒", "提前 5 分钟", "提前 15 分钟",
            "提前 30 分钟", "提前 1 小时", "提前 1 天"
    };
    private static final int[] REMINDER_VALUES = {-1, 0, 5, 15, 30, 60, 1440};
    private static final DateTimeFormatter DATE_LABEL = DateTimeFormatter.ofPattern("yyyy年M月d日", Locale.CHINA);
    private static final DateTimeFormatter TIME_LABEL = DateTimeFormatter.ofPattern("HH:mm", Locale.CHINA);

    private SharedPreferences store;
    private boolean darkMode;
    private String themeColor;
    private FrameLayout root;
    private ScrollView page;
    private LinearLayout column;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final List<Runnable> countdownTicks = new ArrayList<>();
    private final Map<String, View> cardViews = new HashMap<>();
    private final List<Checklist> renderedChecklists = new ArrayList<>();
    private TextView summaryLine;
    private boolean ticking;
    private String focusId = "";
    private boolean modified;

    private static class ChecklistCardBinding {
        TextView countdown;
        TextView progressLabel;
        LinearLayout progressTrack;
    }

    private final Runnable ticker = new Runnable() {
        @Override
        public void run() {
            if (!ticking) return;
            long now = System.currentTimeMillis();
            for (Runnable tick : countdownTicks) {
                try {
                    tick.run();
                } catch (Exception ignored) {}
            }
            handler.postDelayed(this, 1000L);
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        store = getSharedPreferences("campus_private", MODE_PRIVATE);
        themeColor = ScheduleStorage.loadThemeColor(store);
        darkMode = ScheduleStorage.loadDarkMode(store);
        focusId = getIntent().getStringExtra(EXTRA_CHECKLIST_ID);
        if (focusId == null) focusId = "";
        ChecklistReminderScheduler.ensureChannel(this);
        applyWindowTheme();
        buildRoot();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String id = intent.getStringExtra(EXTRA_CHECKLIST_ID);
        if (id != null && !id.isEmpty()) {
            focusId = id;
            render();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        render();
        startTicker();
    }

    @Override
    protected void onPause() {
        stopTicker();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        stopTicker();
        super.onDestroy();
    }

    @Override
    public void finish() {
        if (modified) setResult(RESULT_OK);
        super.finish();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_NOTIFICATIONS) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                ChecklistReminderScheduler.rescheduleAll(this);
                Toast.makeText(this, "通知已开启，提醒会发送到手机", Toast.LENGTH_SHORT).show();
            } else {
                Toast.makeText(this, "通知未开启，打开应用时会补提醒", Toast.LENGTH_LONG).show();
            }
            render();
        }
    }

    private void buildRoot() {
        root = new FrameLayout(this);
        root.setBackgroundColor(backgroundColor());
        setContentView(root);
        applySystemBarInsets();

        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(16), dp(16), dp(16), dp(10));

        ImageView back = iconButton(R.drawable.ic_arrow_back, "返回");
        back.setOnClickListener(v -> finish());
        header.addView(back, new LinearLayout.LayoutParams(dp(40), dp(40)));

        LinearLayout heading = new LinearLayout(this);
        heading.setOrientation(LinearLayout.VERTICAL);
        heading.setPadding(dp(12), 0, 0, 0);
        TextView title = label("清单", 24, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        heading.addView(title);
        heading.addView(label("截止倒计时 · 多清单 · 提醒", 11, mutedColor()));
        header.addView(heading, new LinearLayout.LayoutParams(0, -2, 1));

        Button add = action("新建", true);
        add.setOnClickListener(v -> showChecklistDialog(null));
        header.addView(add, new LinearLayout.LayoutParams(dp(70), dp(40)));
        shell.addView(header);

        page = new ScrollView(this);
        page.setFillViewport(true);
        page.setBackgroundColor(backgroundColor());
        page.setSaveEnabled(false);
        column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setPadding(dp(16), dp(4), dp(16), dp(28));
        page.addView(column);
        shell.addView(page, new LinearLayout.LayoutParams(-1, 0, 1));
        root.addView(shell, new FrameLayout.LayoutParams(-1, -1));
    }

    private void applySystemBarInsets() {
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
            return insets;
        });
        root.requestApplyInsets();
    }

    private void render() {
        if (column == null) return;
        int scrollY = page.getScrollY();
        column.removeAllViews();
        countdownTicks.clear();
        cardViews.clear();

        List<Checklist> values = ChecklistStore.load(store);
        ChecklistStore.sortForDisplay(values, System.currentTimeMillis());
        renderedChecklists.clear();
        renderedChecklists.addAll(values);
        addSummary(values);
        if (DeviceCompat.isHuaweiFamily()) addHuaweiReminderCard();

        if (values.isEmpty()) {
            addEmptyState();
        } else {
            for (Checklist checklist : values) addChecklistCard(checklist);
        }

        int safeScroll = scrollY;
        page.post(() -> page.scrollTo(0, safeScroll));
        if (!focusId.isEmpty()) {
            View target = cardViews.get(focusId);
            if (target != null) {
                page.post(() -> page.smoothScrollTo(0, Math.max(0, target.getTop() - dp(8))));
            }
            focusId = "";
        }
    }

    private void addSummary(List<Checklist> values) {
        int pending = 0;
        for (Checklist checklist : values) pending += checklist.pendingCount();
        LinearLayout summary = card(panelColor());
        summary.setPadding(dp(14), dp(12), dp(14), dp(12));
        TextView line = label(values.size() + " 个清单 · " + pending + " 项待完成", 13, textColor());
        line.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        summaryLine = line;
        summary.addView(line);
        summary.addView(label("提醒会通过系统通知发送；通知被关闭时，打开应用会补提醒。", 11, mutedColor()));
        if (!notificationsEnabled()) {
            addGap(summary, 8);
            LinearLayout warning = new LinearLayout(this);
            warning.setGravity(Gravity.CENTER_VERTICAL);
            TextView text = label("通知未开启", 11, warningColor());
            text.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
            warning.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
            Button enable = action("开启", false);
            enable.setOnClickListener(v -> requestNotifications());
            warning.addView(enable, new LinearLayout.LayoutParams(dp(62), dp(34)));
            summary.addView(warning);
        }
        column.addView(summary);
        addGap(column, 10);
    }

    private void addHuaweiReminderCard() {
        LinearLayout card = card(panelColor());
        card.setPadding(dp(14), dp(12), dp(14), dp(12));
        TextView title = label("鸿蒙 / 华为提醒设置", 13, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        card.addView(title);
        TextView hint = label("HarmonyOS 可能限制后台提醒。建议允许通知、自启动和后台活动，并把电池优化设为“不限制”。",
                11, mutedColor());
        hint.setLineSpacing(0, 1.15f);
        hint.setPadding(0, dp(3), 0, dp(2));
        card.addView(hint);
        LinearLayout actions = new LinearLayout(this);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(0, dp(7), 0, 0);
        Button notify = action("通知设置", false);
        notify.setTextSize(11);
        notify.setMinHeight(0);
        notify.setOnClickListener(v -> DeviceCompat.openNotificationSettings(this));
        actions.addView(notify, new LinearLayout.LayoutParams(0, dp(36), 1));
        addHorizontalGap(actions, 8);
        Button settings = action("应用设置", true);
        settings.setTextSize(11);
        settings.setMinHeight(0);
        settings.setOnClickListener(v -> DeviceCompat.openAppSettings(this));
        actions.addView(settings, new LinearLayout.LayoutParams(0, dp(36), 1));
        card.addView(actions);
        column.addView(card);
        addGap(column, 10);
    }

    private void addEmptyState() {
        LinearLayout empty = card(panelColor());
        empty.setGravity(Gravity.CENTER_HORIZONTAL);
        empty.setPadding(dp(18), dp(28), dp(18), dp(24));
        TextView title = label("还没有清单", 17, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setGravity(Gravity.CENTER);
        empty.addView(title);
        TextView hint = label("把要交的作业、要买的东西或近期目标拆成事项，\n设置截止时间后会在首页倒计时。", 12, mutedColor());
        hint.setGravity(Gravity.CENTER);
        hint.setLineSpacing(0, 1.2f);
        empty.addView(hint, new LinearLayout.LayoutParams(-1, -2));
        addGap(empty, 14);
        Button create = action("创建第一个清单", true);
        create.setOnClickListener(v -> showChecklistDialog(null));
        empty.addView(create, new LinearLayout.LayoutParams(-1, dp(44)));
        column.addView(empty);
    }

    private void addChecklistCard(Checklist checklist) {
        ChecklistCardBinding binding = new ChecklistCardBinding();
        LinearLayout card = card(panelColor());
        card.setPadding(dp(14), dp(12), dp(14), dp(10));

        LinearLayout top = new LinearLayout(this);
        top.setGravity(Gravity.TOP);

        LinearLayout textBox = new LinearLayout(this);
        textBox.setOrientation(LinearLayout.VERTICAL);
        TextView title = label(checklist.title, 16, textColor());
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setMaxLines(2);
        textBox.addView(title);
        TextView deadline = label("截止 " + checklist.deadlineDisplay() + " · " + checklist.reminderLabel(),
                11, deadlineColor(checklist));
        deadline.setPadding(0, dp(3), 0, 0);
        textBox.addView(deadline);
        top.addView(textBox, new LinearLayout.LayoutParams(0, -2, 1));

        LinearLayout countdownBox = new LinearLayout(this);
        countdownBox.setOrientation(LinearLayout.VERTICAL);
        countdownBox.setGravity(Gravity.END);
        TextView countdown = label("", 13, primaryColor());
        countdown.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        countdown.setGravity(Gravity.END);
        countdown.setMaxLines(1);
        countdownBox.addView(countdown);
        TextView progressLabel = label(checklist.doneCount() + "/" + checklist.items.size() + " 已完成",
                10, mutedColor());
        progressLabel.setGravity(Gravity.END);
        countdownBox.addView(progressLabel);
        binding.countdown = countdown;
        binding.progressLabel = progressLabel;
        top.addView(countdownBox, new LinearLayout.LayoutParams(-2, -2));
        card.addView(top);

        LinearLayout bar = progressBar(checklist.progress());
        binding.progressTrack = bar;
        LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(-1, dp(4));
        barParams.topMargin = dp(10);
        card.addView(bar, barParams);

        if (checklist.items.isEmpty()) {
            TextView hint = label("还没有事项，在下面添加第一条。", 12, mutedColor());
            hint.setPadding(0, dp(12), 0, dp(2));
            card.addView(hint);
        } else {
            for (Checklist.Item item : checklist.items) card.addView(itemRow(checklist, item, binding));
        }

        LinearLayout addRow = new LinearLayout(this);
        addRow.setGravity(Gravity.CENTER_VERTICAL);
        addRow.setPadding(0, dp(7), 0, 0);
        EditText input = input("添加事项…");
        input.setSingleLine(true);
        input.setImeOptions(EditorInfo.IME_ACTION_DONE);
        input.setTextSize(13);
        addRow.addView(input, new LinearLayout.LayoutParams(0, dp(42), 1));
        addHorizontalGap(addRow, 8);
        Button add = action("添加", true);
        add.setTextSize(12);
        add.setMinHeight(0);
        add.setOnClickListener(v -> addItem(checklist, input));
        input.setOnEditorActionListener((view, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                addItem(checklist, input);
                return true;
            }
            return false;
        });
        addRow.addView(add, new LinearLayout.LayoutParams(dp(58), dp(42)));
        card.addView(addRow);

        LinearLayout footer = new LinearLayout(this);
        footer.setGravity(Gravity.CENTER_VERTICAL);
        footer.setPadding(0, dp(8), 0, 0);
        TextView reminder = label(checklist.reminderMinutes < 0 ? "未设置提醒" : "提醒 · " + checklist.reminderLabel(),
                10, mutedColor());
        footer.addView(reminder, new LinearLayout.LayoutParams(0, -2, 1));
        Button edit = action("编辑清单", false);
        edit.setTextSize(11);
        edit.setMinHeight(0);
        edit.setOnClickListener(v -> showChecklistDialog(checklist));
        footer.addView(edit, new LinearLayout.LayoutParams(dp(84), dp(34)));
        card.addView(footer);

        column.addView(card);
        addGap(column, 10);
        cardViews.put(checklist.id, card);
        registerCountdown(countdown, checklist);
    }

    private View itemRow(Checklist checklist, Checklist.Item item, ChecklistCardBinding binding) {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, dp(3), 0, dp(3));

        CheckBox check = new CheckBox(this);
        check.setChecked(item.done);
        check.setButtonTintList(ColorStateList.valueOf(item.done ? successColor() : primaryColor()));
        check.setContentDescription(item.done ? "标记为未完成" : "标记为完成");
        row.addView(check, new LinearLayout.LayoutParams(dp(36), dp(40)));

        TextView text = label(item.text, 13, item.done ? mutedColor() : textColor());
        text.setPadding(dp(2), 0, dp(4), 0);
        if (item.done) text.setPaintFlags(text.getPaintFlags() | Paint.STRIKE_THRU_TEXT_FLAG);
        text.setOnClickListener(v -> showItemDialog(checklist, item));
        row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));

        TextView more = label("⋮", 20, mutedColor());
        more.setGravity(Gravity.CENTER);
        more.setContentDescription("事项操作");
        more.setOnClickListener(v -> showItemMenu(more, checklist, item));
        row.addView(more, new LinearLayout.LayoutParams(dp(30), dp(40)));

        check.setOnCheckedChangeListener((button, checked) -> {
            if (item.done == checked) return;
            item.done = checked;
            check.setButtonTintList(ColorStateList.valueOf(checked ? successColor() : primaryColor()));
            check.setContentDescription(checked ? "标记为未完成" : "标记为完成");
            text.setTextColor(checked ? mutedColor() : textColor());
            int flags = text.getPaintFlags();
            if (checked) {
                flags |= Paint.STRIKE_THRU_TEXT_FLAG;
            } else {
                flags &= ~Paint.STRIKE_THRU_TEXT_FLAG;
            }
            text.setPaintFlags(flags);

            checklist.updatedAt = System.currentTimeMillis();
            ChecklistStore.save(store, renderedChecklists);
            if (!checked) ChecklistStore.clearReminded(store, checklist);
            if (checklist.allDone()) {
                ChecklistReminderScheduler.cancel(this, checklist.id);
            } else {
                ChecklistReminderScheduler.schedule(this, checklist);
            }
            refreshChecklistCard(binding, checklist);
            updateSummaryText();
            modified = true;
        });
        return row;
    }

    private void addItem(Checklist checklist, EditText input) {
        String value = input.getText().toString().trim();
        if (value.isEmpty()) {
            Toast.makeText(this, "请输入事项内容", Toast.LENGTH_SHORT).show();
            return;
        }
        Checklist.Item item = new Checklist.Item("item-" + System.currentTimeMillis(), value);
        checklist.items.add(item);
        ChecklistStore.upsert(store, checklist);
        ChecklistStore.clearReminded(store, checklist);
        ChecklistReminderScheduler.schedule(this, checklist);
        modified = true;
        input.setText("");
        render();
    }

    private void showItemMenu(View anchor, Checklist checklist, Checklist.Item item) {
        PopupMenu menu = new PopupMenu(this, anchor);
        menu.getMenu().add("编辑事项");
        menu.getMenu().add("删除事项");
        menu.setOnMenuItemClickListener(choice -> {
            if ("编辑事项".contentEquals(choice.getTitle())) {
                showItemDialog(checklist, item);
            } else {
                confirm("删除事项", "确定删除「" + item.text + "」吗？", () -> {
                    checklist.items.remove(item);
                    ChecklistStore.upsert(store, checklist);
                    if (checklist.allDone()) {
                        ChecklistReminderScheduler.cancel(this, checklist.id);
                    } else {
                        ChecklistReminderScheduler.schedule(this, checklist);
                    }
                    modified = true;
                    render();
                });
            }
            return true;
        });
        menu.show();
    }

    private void showChecklistDialog(Checklist editing) {
        boolean isEdit = editing != null;
        LocalDateTime baseDeadline = isEdit ? editing.deadlineTime()
                : LocalDateTime.now().plusDays(1).withHour(23).withMinute(59).withSecond(0).withNano(0);
        final String[] chosenDate = {baseDeadline.toLocalDate().toString()};
        final String[] chosenTime = {baseDeadline.toLocalTime().format(TIME_LABEL)};
        final int[] chosenReminder = {isEdit ? editing.reminderMinutes : 30};
        final String[] chosenColor = {isEdit && editing.color != null ? editing.color : Checklist.DEFAULT_COLOR};

        Dialog dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setPadding(dp(20), dp(18), dp(20), dp(16));
        shell.setBackground(bg(panelColor(), 16));
        applyOutline(shell, 16, 12);

        TextView eyebrow = label("清单", 11, primaryColor());
        eyebrow.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(eyebrow);
        TextView heading = label(isEdit ? "编辑清单" : "新建清单", 21, textColor());
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(heading);
        TextView subtitle = label("设置截止时间，首页会显示实时倒计时。", 11, mutedColor());
        subtitle.setPadding(0, dp(3), 0, dp(10));
        shell.addView(subtitle);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(0, 0, 0, dp(4));
        scroll.addView(form);

        addFormLabel(form, "清单名称");
        EditText titleInput = field(form, "例如：高数作业 / 周末采购", isEdit ? editing.title : "");
        titleInput.setSingleLine(true);

        addFormLabel(form, "截止时间");
        LinearLayout dateRow = new LinearLayout(this);
        dateRow.setGravity(Gravity.CENTER_VERTICAL);
        final TextView dateValue = inputLike(dateLabel(chosenDate[0]));
        dateValue.setOnClickListener(v -> {
            LocalDate base = parseDate(chosenDate[0]);
            new DatePickerDialog(this, (view, year, month, day) -> {
                chosenDate[0] = LocalDate.of(year, month + 1, day).toString();
                dateValue.setText(dateLabel(chosenDate[0]));
            }, base.getYear(), base.getMonthValue() - 1, base.getDayOfMonth()).show();
        });
        dateRow.addView(dateValue, new LinearLayout.LayoutParams(0, dp(48), 1));
        addHorizontalGap(dateRow, 8);
        final TextView timeValue = inputLike(chosenTime[0]);
        timeValue.setOnClickListener(v -> {
            LocalTime base = parseTime(chosenTime[0]);
            new TimePickerDialog(this, (view, hour, minute) -> {
                chosenTime[0] = String.format(Locale.CHINA, "%02d:%02d", hour, minute);
                timeValue.setText(chosenTime[0]);
            }, base.getHour(), base.getMinute(), true).show();
        });
        dateRow.addView(timeValue, new LinearLayout.LayoutParams(dp(88), dp(48)));
        form.addView(dateRow);

        addFormLabel(form, "提前提醒");
        final TextView reminderValue = inputLike(reminderLabel(chosenReminder[0]));
        reminderValue.setOnClickListener(v -> showReminderPicker(chosenReminder[0], value -> {
            chosenReminder[0] = value;
            reminderValue.setText(reminderLabel(value));
        }));
        form.addView(reminderValue, new LinearLayout.LayoutParams(-1, dp(48)));

        addFormLabel(form, "清单颜色");
        LinearLayout swatches = new LinearLayout(this);
        swatches.setGravity(Gravity.CENTER_VERTICAL);
        form.addView(swatches);
        refreshSwatches(swatches, chosenColor[0], value -> {
            chosenColor[0] = value;
            refreshSwatches(swatches, value, ignored -> {});
        });

        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        if (isEdit) {
            TextView delete = label("删除这个清单", 11, warningColor());
            delete.setGravity(Gravity.CENTER);
            delete.setPadding(0, dp(10), 0, 0);
            delete.setOnClickListener(v -> {
                dialog.dismiss();
                confirm("删除清单", "确定删除「" + editing.title + "」吗？", () -> {
                    ChecklistReminderScheduler.cancel(this, editing.id);
                    ChecklistStore.delete(store, editing.id);
                    modified = true;
                    render();
                });
            });
            shell.addView(delete);
        }

        LinearLayout actions = new LinearLayout(this);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(0, dp(12), 0, 0);
        Button cancel = action("取消", false);
        cancel.setOnClickListener(v -> dialog.dismiss());
        actions.addView(cancel, new LinearLayout.LayoutParams(0, dp(44), 1));
        addHorizontalGap(actions, 10);
        Button save = action("保存", true);
        actions.addView(save, new LinearLayout.LayoutParams(0, dp(44), 1));
        shell.addView(actions);

        save.setOnClickListener(v -> {
            String title = titleInput.getText().toString().trim();
            if (title.isEmpty()) {
                Toast.makeText(this, "请输入清单名称", Toast.LENGTH_SHORT).show();
                return;
            }
            LocalDate date = parseDate(chosenDate[0]);
            LocalTime time = parseTime(chosenTime[0]);
            String deadline = Checklist.formatDeadline(date, time);
            Checklist checklist = isEdit ? editing : new Checklist(
                    "checklist-" + System.currentTimeMillis(), title, deadline, chosenReminder[0]);
            checklist.title = title;
            checklist.deadline = deadline;
            checklist.reminderMinutes = chosenReminder[0];
            checklist.color = chosenColor[0];
            checklist.updatedAt = System.currentTimeMillis();
            ChecklistStore.upsert(store, checklist);
            ChecklistStore.clearReminded(store, checklist);
            ChecklistReminderScheduler.schedule(this, checklist);
            modified = true;
            focusId = checklist.id;
            dialog.dismiss();
            if (checklist.reminderMinutes >= 0 && !notificationsEnabled()) requestNotifications();
            render();
        });

        dialog.setContentView(shell);
        dialog.setCanceledOnTouchOutside(true);
        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            WindowManager.LayoutParams params = window.getAttributes();
            params.dimAmount = 0.34f;
            window.setAttributes(params);
        }
        dialog.show();
        if (window != null) {
            int width = Math.min(getResources().getDisplayMetrics().widthPixels - dp(32), dp(440));
            int height = Math.min(getResources().getDisplayMetrics().heightPixels - dp(80), dp(670));
            window.setLayout(width, height);
        }
    }

    private void showItemDialog(Checklist checklist, Checklist.Item item) {
        Dialog dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout shell = new LinearLayout(this);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setPadding(dp(20), dp(18), dp(20), dp(16));
        shell.setBackground(bg(panelColor(), 16));
        applyOutline(shell, 16, 12);
        TextView heading = label("编辑事项", 20, textColor());
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(heading);
        EditText input = field(shell, "事项内容", item.text);
        input.setSingleLine(false);
        input.setMinLines(1);
        input.setMaxLines(3);
        LinearLayout actions = new LinearLayout(this);
        actions.setPadding(0, dp(12), 0, 0);
        Button cancel = action("取消", false);
        cancel.setOnClickListener(v -> dialog.dismiss());
        actions.addView(cancel, new LinearLayout.LayoutParams(0, dp(44), 1));
        addHorizontalGap(actions, 10);
        Button save = action("保存", true);
        save.setOnClickListener(v -> {
            String value = input.getText().toString().trim();
            if (value.isEmpty()) {
                Toast.makeText(this, "事项内容不能为空", Toast.LENGTH_SHORT).show();
                return;
            }
            item.text = value;
            ChecklistStore.upsert(store, checklist);
            modified = true;
            dialog.dismiss();
            render();
        });
        actions.addView(save, new LinearLayout.LayoutParams(0, dp(44), 1));
        shell.addView(actions);
        dialog.setContentView(shell);
        dialog.setCanceledOnTouchOutside(true);
        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            window.setGravity(Gravity.CENTER);
        }
        dialog.show();
        if (window != null) {
            int width = Math.min(getResources().getDisplayMetrics().widthPixels - dp(40), dp(380));
            window.setLayout(width, WindowManager.LayoutParams.WRAP_CONTENT);
        }
    }

    private void showReminderPicker(int current, Consumer<Integer> callback) {
        int checked = 0;
        for (int i = 0; i < REMINDER_VALUES.length; i++) {
            if (REMINDER_VALUES[i] == current) {
                checked = i;
                break;
            }
        }
        new AlertDialog.Builder(this)
                .setTitle("提前提醒")
                .setSingleChoiceItems(REMINDER_LABELS, checked, (dialog, which) -> {
                    callback.accept(REMINDER_VALUES[which]);
                    dialog.dismiss();
                })
                .setNegativeButton("取消", null)
                .show();
    }

    private void confirm(String title, String message, Runnable onConfirm) {
        new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setNegativeButton("取消", null)
                .setPositiveButton("删除", (dialog, which) -> onConfirm.run())
                .show();
    }

    private void refreshChecklistCard(ChecklistCardBinding binding, Checklist checklist) {
        if (binding == null) return;
        if (binding.progressLabel != null) {
            binding.progressLabel.setText(checklist.doneCount() + "/" + checklist.items.size() + " 已完成");
        }
        if (binding.progressTrack != null) {
            fillProgressTrack(binding.progressTrack, checklist.progress());
        }
        updateChecklistCountdown(binding.countdown, checklist);
    }

    private void updateSummaryText() {
        if (summaryLine == null) return;
        int pending = 0;
        for (Checklist checklist : renderedChecklists) pending += checklist.pendingCount();
        summaryLine.setText(renderedChecklists.size() + " 个清单 · " + pending + " 项待完成");
    }

    private void updateChecklistCountdown(TextView view, Checklist checklist) {
        if (view == null) return;
        long now = System.currentTimeMillis();
        view.setText(checklist.compactCountdownText(now));
        if (checklist.allDone()) {
            view.setTextColor(successColor());
        } else if (checklist.deadlineMillis() <= now) {
            view.setTextColor(warningColor());
        } else {
            view.setTextColor(primaryColor());
        }
    }

    private void registerCountdown(TextView view, Checklist checklist) {
        Runnable tick = () -> updateChecklistCountdown(view, checklist);
        tick.run();
        countdownTicks.add(tick);
    }

    private void startTicker() {
        if (ticking) return;
        ticking = true;
        handler.post(ticker);
    }

    private void stopTicker() {
        ticking = false;
        handler.removeCallbacks(ticker);
    }

    private void requestNotifications() {
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"}, REQUEST_NOTIFICATIONS);
            return;
        }
        try {
            Intent intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
            startActivity(intent);
        } catch (Exception ignored) {
            Toast.makeText(this, "请到系统设置中开启通知权限", Toast.LENGTH_LONG).show();
        }
    }

    private boolean notificationsEnabled() {
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
            return false;
        }
        NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        return manager != null && manager.areNotificationsEnabled();
    }

    private void addFormLabel(LinearLayout parent, String text) {
        TextView view = label(text, 11, mutedColor());
        view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(0, dp(9), 0, dp(4));
        parent.addView(view);
    }

    private EditText field(LinearLayout parent, String hint, String value) {
        EditText input = new EditText(this);
        input.setHint(hint);
        if (value != null) input.setText(value);
        input.setTextColor(textColor());
        input.setHintTextColor(mutedColor());
        input.setPadding(dp(14), 0, dp(14), 0);
        input.setBackground(border(surfaceColor(), lineColor(), 8));
        parent.addView(input, new LinearLayout.LayoutParams(-1, dp(52)));
        return input;
    }

    private EditText input(String hint) {
        EditText input = new EditText(this);
        input.setHint(hint);
        input.setTextColor(textColor());
        input.setHintTextColor(mutedColor());
        input.setPadding(dp(12), 0, dp(12), 0);
        input.setBackground(border(surfaceColor(), lineColor(), 8));
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

    private void refreshSwatches(LinearLayout container, String chosen, Consumer<String> onChoose) {
        container.removeAllViews();
        for (String value : ScheduleModels.PRESET_COLORS) {
            View swatch = colorSwatch(value, value.equals(chosen));
            swatch.setOnClickListener(v -> onChoose.accept(value));
            container.addView(swatch);
            addHorizontalGap(container, 8);
        }
    }

    private View colorSwatch(String value, boolean selected) {
        View swatch = new View(this);
        GradientDrawable drawable = bg(parseColorSafe(value, primaryColor()), 10);
        drawable.setStroke(dp(selected ? 3 : 1), selected ? textColor() : lineColor());
        swatch.setBackground(drawable);
        swatch.setLayoutParams(new LinearLayout.LayoutParams(dp(28), dp(28)));
        return swatch;
    }

    private LinearLayout progressBar(float fraction) {
        LinearLayout track = new LinearLayout(this);
        track.setOrientation(LinearLayout.HORIZONTAL);
        track.setBackground(bg(lineColor(), 3));
        fillProgressTrack(track, fraction);
        return track;
    }

    private void fillProgressTrack(LinearLayout track, float fraction) {
        if (track == null) return;
        track.removeAllViews();
        float safe = Math.max(0f, Math.min(1f, fraction));
        View fill = new View(this);
        fill.setBackground(bg(safe >= 1f ? successColor() : primaryColor(), 3));
        track.addView(fill, new LinearLayout.LayoutParams(0, dp(4), safe));
        View rest = new View(this);
        track.addView(rest, new LinearLayout.LayoutParams(0, dp(4), 1f - safe));
    }

    private void applyWindowTheme() {
        Window window = getWindow();
        window.setStatusBarColor(backgroundColor());
        window.setNavigationBarColor(panelColor());
        if (Build.VERSION.SDK_INT >= 23) {
            int flags = window.getDecorView().getSystemUiVisibility();
            if (darkMode) {
                flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
                if (Build.VERSION.SDK_INT >= 26) flags &= ~View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            } else {
                flags |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
                if (Build.VERSION.SDK_INT >= 26) flags |= View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            }
            window.getDecorView().setSystemUiVisibility(flags);
        }
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
        try {
            return Color.parseColor(themeColor);
        } catch (Exception ignored) {
            return Color.rgb(47, 128, 237);
        }
    }

    private int successColor() {
        return darkMode ? Color.rgb(126, 226, 168) : Color.rgb(33, 150, 83);
    }

    private int warningColor() {
        return darkMode ? Color.rgb(255, 138, 128) : Color.rgb(198, 40, 40);
    }

    private int deadlineColor(Checklist checklist) {
        if (checklist.allDone()) return successColor();
        if (checklist.deadlineMillis() <= System.currentTimeMillis()) return warningColor();
        return mutedColor();
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
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setBackground(border(color, lineColor(), 8));
        layout.setPadding(dp(14), dp(12), dp(14), dp(12));
        return layout;
    }

    private ImageView iconButton(int resource, String description) {
        ImageView button = new ImageView(this);
        button.setImageResource(resource);
        button.setColorFilter(primaryColor());
        button.setContentDescription(description);
        button.setPadding(dp(9), dp(9), dp(9), dp(9));
        button.setBackground(border(panelColor(), lineColor(), 8));
        return button;
    }

    private Button action(String text, boolean filled) {
        Button button = new Button(this);
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

    private void applyOutline(View view, int radiusDp, int elevationDp) {
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

    private int parseColorSafe(String value, int fallback) {
        try {
            return Color.parseColor(value);
        } catch (Exception ignored) {
            return fallback;
        }
    }

    private LocalDate parseDate(String value) {
        try {
            return LocalDate.parse(value);
        } catch (Exception ignored) {
            return LocalDate.now();
        }
    }

    private LocalTime parseTime(String value) {
        try {
            return LocalTime.parse(value);
        } catch (Exception ignored) {
            return LocalTime.of(23, 59);
        }
    }

    private String dateLabel(String value) {
        return DATE_LABEL.format(parseDate(value));
    }

    private String reminderLabel(int value) {
        for (int i = 0; i < REMINDER_VALUES.length; i++) {
            if (REMINDER_VALUES[i] == value) return REMINDER_LABELS[i];
        }
        return REMINDER_LABELS[4];
    }

    private int dp(int value) {
        return Math.round(getResources().getDisplayMetrics().density * value);
    }

    private void addGap(LinearLayout parent, int heightDp) {
        View gap = new View(this);
        parent.addView(gap, new LinearLayout.LayoutParams(-1, dp(heightDp)));
    }

    private void addHorizontalGap(LinearLayout parent, int widthDp) {
        View gap = new View(this);
        parent.addView(gap, new LinearLayout.LayoutParams(dp(widthDp), 1));
    }
}
