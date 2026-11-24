package cn.nwpu.campus;

import android.app.Activity;
import android.app.Dialog;
import android.app.DatePickerDialog;
import android.app.TimePickerDialog;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.view.Gravity;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.Locale;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;

/** 新建/编辑清单的弹窗。保存和删除后的刷新由外部回调处理。 */
final class ChecklistEditor {
    private final Activity activity;
    private final ChecklistUi ui;
    private final SharedPreferences store;
    private final Checklist editing;
    private final Consumer<String> onChanged;
    private final BooleanSupplier notificationsEnabled;
    private final Runnable requestNotifications;

    ChecklistEditor(Activity activity, ChecklistUi ui, SharedPreferences store, Checklist editing,
                    Consumer<String> onChanged, BooleanSupplier notificationsEnabled,
                    Runnable requestNotifications) {
        this.activity = activity;
        this.ui = ui;
        this.store = store;
        this.editing = editing;
        this.onChanged = onChanged;
        this.notificationsEnabled = notificationsEnabled;
        this.requestNotifications = requestNotifications;
    }

    void show() {
        boolean isEdit = editing != null;
        LocalDateTime base = isEdit ? editing.deadlineTime()
                : LocalDateTime.now().plusDays(1).withHour(23).withMinute(59).withSecond(0).withNano(0);
        String[] chosenDate = {base.toLocalDate().toString()};
        String[] chosenTime = {base.toLocalTime().format(java.time.format.DateTimeFormatter.ofPattern("HH:mm", Locale.CHINA))};
        int[] chosenReminder = {isEdit ? editing.reminderMinutes : 30};
        String[] chosenColor = {isEdit && editing.color != null ? editing.color : Checklist.DEFAULT_COLOR};

        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout shell = new LinearLayout(activity);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setPadding(ui.dp(20), ui.dp(18), ui.dp(20), ui.dp(16));
        shell.setBackground(ui.bg(ui.panelColor(), 16));
        ui.applyOutline(shell, 16, 12);

        TextView eyebrow = ui.label("清单", 11, ui.primaryColor());
        eyebrow.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(eyebrow);
        TextView heading = ui.label(isEdit ? "编辑清单" : "新建清单", 21, ui.textColor());
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(heading);
        TextView subtitle = ui.label("设置截止时间，事项页会显示实时倒计时。", 11, ui.mutedColor());
        subtitle.setPadding(0, ui.dp(3), 0, ui.dp(10));
        shell.addView(subtitle);

        ScrollView scroll = new ScrollView(activity);
        scroll.setFillViewport(true);
        LinearLayout form = new LinearLayout(activity);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(0, 0, 0, ui.dp(4));
        scroll.addView(form);

        ui.addFormLabel(form, "清单名称");
        EditText titleInput = ui.field(form, "例如：高数作业 / 周末采购", isEdit ? editing.title : "");
        titleInput.setSingleLine(true);

        ui.addFormLabel(form, "截止时间");
        LinearLayout dateRow = new LinearLayout(activity);
        dateRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView dateValue = ui.inputLike(ui.dateLabel(chosenDate[0]));
        dateValue.setOnClickListener(v -> {
            LocalDate baseDate = ui.parseDate(chosenDate[0]);
            new DatePickerDialog(activity, (view, year, month, day) -> {
                chosenDate[0] = LocalDate.of(year, month + 1, day).toString();
                dateValue.setText(ui.dateLabel(chosenDate[0]));
            }, baseDate.getYear(), baseDate.getMonthValue() - 1, baseDate.getDayOfMonth()).show();
        });
        dateRow.addView(dateValue, new LinearLayout.LayoutParams(0, ui.dp(48), 1));
        ui.addHorizontalGap(dateRow, 8);
        TextView timeValue = ui.inputLike(chosenTime[0]);
        timeValue.setOnClickListener(v -> {
            LocalTime baseTime = ui.parseTime(chosenTime[0]);
            new TimePickerDialog(activity, (view, hour, minute) -> {
                chosenTime[0] = String.format(Locale.CHINA, "%02d:%02d", hour, minute);
                timeValue.setText(chosenTime[0]);
            }, baseTime.getHour(), baseTime.getMinute(), true).show();
        });
        dateRow.addView(timeValue, new LinearLayout.LayoutParams(ui.dp(88), ui.dp(48)));
        form.addView(dateRow);

        ui.addFormLabel(form, "提前提醒");
        TextView reminderValue = ui.inputLike(ui.reminderLabel(chosenReminder[0]));
        reminderValue.setOnClickListener(v -> ui.showReminderPicker(chosenReminder[0], value -> {
            chosenReminder[0] = value;
            reminderValue.setText(ui.reminderLabel(value));
        }));
        form.addView(reminderValue, new LinearLayout.LayoutParams(-1, ui.dp(48)));

        ui.addFormLabel(form, "清单颜色");
        LinearLayout swatches = new LinearLayout(activity);
        swatches.setGravity(Gravity.CENTER_VERTICAL);
        form.addView(swatches);
        ui.refreshSwatches(swatches, chosenColor[0], value -> {
            chosenColor[0] = value;
            ui.refreshSwatches(swatches, value, ignored -> {});
        });

        shell.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        if (isEdit) {
            TextView delete = ui.label("删除这个清单", 11, ui.warningColor());
            delete.setGravity(Gravity.CENTER);
            delete.setPadding(0, ui.dp(10), 0, 0);
            delete.setOnClickListener(v -> {
                dialog.dismiss();
                confirmDelete();
            });
            shell.addView(delete);
        }

        LinearLayout actions = new LinearLayout(activity);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        actions.setPadding(0, ui.dp(12), 0, 0);
        Button cancel = ui.action("取消", false);
        cancel.setOnClickListener(v -> dialog.dismiss());
        actions.addView(cancel, new LinearLayout.LayoutParams(0, ui.dp(44), 1));
        ui.addHorizontalGap(actions, 10);
        Button save = ui.action("保存", true);
        actions.addView(save, new LinearLayout.LayoutParams(0, ui.dp(44), 1));
        shell.addView(actions);

        save.setOnClickListener(v -> save(dialog, titleInput, chosenDate, chosenTime, chosenReminder, chosenColor));

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
            int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels - ui.dp(32), ui.dp(440));
            int height = Math.min(activity.getResources().getDisplayMetrics().heightPixels - ui.dp(80), ui.dp(670));
            window.setLayout(width, height);
        }
    }

    private void save(Dialog dialog, EditText titleInput, String[] chosenDate, String[] chosenTime,
                      int[] chosenReminder, String[] chosenColor) {
        String title = titleInput.getText().toString().trim();
        if (title.isEmpty()) {
            Toast.makeText(activity, "请输入清单名称", Toast.LENGTH_SHORT).show();
            return;
        }
        LocalDate date = ui.parseDate(chosenDate[0]);
        LocalTime time = ui.parseTime(chosenTime[0]);
        String deadline = Checklist.formatDeadline(date, time);
        boolean isEdit = editing != null;
        Checklist checklist = isEdit ? editing : new Checklist(
                "checklist-" + System.currentTimeMillis(), title, deadline, chosenReminder[0]);
        checklist.title = title;
        checklist.deadline = deadline;
        checklist.reminderMinutes = chosenReminder[0];
        checklist.color = chosenColor[0];
        checklist.updatedAt = System.currentTimeMillis();
        ChecklistStore.upsert(store, checklist);
        ChecklistStore.clearReminded(store, checklist);
        ChecklistReminderScheduler.schedule(activity, checklist);
        dialog.dismiss();
        onChanged.accept(checklist.id);
        if (checklist.reminderMinutes >= 0 && !notificationsEnabled.getAsBoolean()) {
            requestNotifications.run();
        }
    }

    private void confirmDelete() {
        new android.app.AlertDialog.Builder(activity)
                .setTitle("删除清单")
                .setMessage("确定删除「" + editing.title + "」吗？")
                .setNegativeButton("取消", null)
                .setPositiveButton("删除", (dialog, which) -> {
                    ChecklistReminderScheduler.cancel(activity, editing.id);
                    ChecklistStore.delete(store, editing.id);
                    onChanged.accept(null);
                })
                .show();
    }
}
