package cn.nwpu.campus;

import android.app.Activity;
import android.app.Dialog;
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
import android.widget.TextView;
import android.widget.Toast;

/** 编辑清单条目。保存后通知列表刷新。 */
final class ChecklistItemDialog {
    private final Activity activity;
    private final ChecklistUi ui;
    private final SharedPreferences store;
    private final Checklist checklist;
    private final Checklist.Item item;
    private final Runnable onChanged;

    ChecklistItemDialog(Activity activity, ChecklistUi ui, SharedPreferences store,
                        Checklist checklist, Checklist.Item item, Runnable onChanged) {
        this.activity = activity;
        this.ui = ui;
        this.store = store;
        this.checklist = checklist;
        this.item = item;
        this.onChanged = onChanged;
    }

    void show() {
        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        LinearLayout shell = new LinearLayout(activity);
        shell.setOrientation(LinearLayout.VERTICAL);
        shell.setPadding(ui.dp(20), ui.dp(18), ui.dp(20), ui.dp(16));
        shell.setBackground(ui.bg(ui.panelColor(), 16));
        ui.applyOutline(shell, 16, 12);
        TextView heading = ui.label("编辑事项", 20, ui.textColor());
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        shell.addView(heading);
        EditText input = ui.field(shell, "事项内容", item.text);
        input.setSingleLine(false);
        input.setMinLines(1);
        input.setMaxLines(3);

        LinearLayout actions = new LinearLayout(activity);
        actions.setPadding(0, ui.dp(12), 0, 0);
        Button cancel = ui.action("取消", false);
        cancel.setOnClickListener(v -> dialog.dismiss());
        actions.addView(cancel, new LinearLayout.LayoutParams(0, ui.dp(44), 1));
        ui.addHorizontalGap(actions, 10);
        Button save = ui.action("保存", true);
        save.setOnClickListener(v -> {
            String value = input.getText().toString().trim();
            if (value.isEmpty()) {
                Toast.makeText(activity, "事项内容不能为空", Toast.LENGTH_SHORT).show();
                return;
            }
            item.text = value;
            ChecklistStore.upsert(store, checklist);
            dialog.dismiss();
            onChanged.run();
        });
        actions.addView(save, new LinearLayout.LayoutParams(0, ui.dp(44), 1));
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
            int width = Math.min(activity.getResources().getDisplayMetrics().widthPixels - ui.dp(40), ui.dp(380));
            window.setLayout(width, WindowManager.LayoutParams.WRAP_CONTENT);
        }
    }
}
