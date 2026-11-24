package cn.nwpu.campus;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;

/** 优先用已保存的独立网费会话同步；需要验证码时显示校方登录页。 */
public class NetworkFeeActivity extends Activity {
    // 自助首页和提取脚本。余额面板可能在 iframe 里，所以脚本要遍历子 frame。
    private static final String URL = NetworkFeeSync.HOME;
    private static final String BALANCE_JS =
            "(function(){var t=document.body?document.body.innerText:'';" +
            "for(var i=0;i<window.frames.length;i++){try{var d=window.frames[i].document;" +
            "if(d&&d.body)t+='\\n'+d.body.innerText;}catch(e){}}return t;})()";
    private final Handler handler = new Handler(Looper.getMainLooper());

    // 页面是异步加载的，第一次 onPageFinished 不一定有余额，最多重试几次。
    private final Runnable captureTask = new Runnable() {
        @Override public void run() {
            captureBalance();
            if (!completed && ++captureAttempts < 12) handler.postDelayed(this, 2000L);
        }
    };
    private WebView web;
    private SharedPreferences prefs;
    private int captureAttempts;
    private boolean completed;
    private boolean capturing;
    private boolean destroyed;
    private long sessionGeneration;

    // ---- 页面 ----

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences("campus_private", MODE_PRIVATE);
        sessionGeneration = NetworkFeeSession.generation(prefs);
        boolean dark = ScheduleStorage.loadDarkMode(
                getSharedPreferences("campus_private", MODE_PRIVATE));
        int background = dark ? Color.parseColor("#111827") : Color.parseColor("#F5F7FA");
        int surface = dark ? Color.parseColor("#1F2937") : Color.WHITE;
        int text = dark ? Color.parseColor("#F3F4F6") : Color.parseColor("#172033");
        int muted = dark ? Color.parseColor("#9CA3AF") : Color.parseColor("#6B7280");

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(background);

        LinearLayout bar = new LinearLayout(this);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(12), 0, dp(16), 0);
        bar.setBackgroundColor(surface);
        ImageView back = new ImageView(this);
        back.setImageResource(R.drawable.ic_arrow_back);
        back.setColorFilter(text);
        back.setContentDescription("返回");
        back.setOnClickListener(v -> finish());
        bar.addView(back, new LinearLayout.LayoutParams(dp(40), dp(52)));
        LinearLayout titles = new LinearLayout(this);
        titles.setOrientation(LinearLayout.VERTICAL);
        TextView title = new TextView(this);
        title.setText("校园网费");
        title.setTextSize(18);
        title.setTextColor(text);
        title.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        titles.addView(title);
        TextView subtitle = new TextView(this);
        subtitle.setText("网络自助 · 余额、套餐与上网明细");
        subtitle.setTextSize(11);
        subtitle.setTextColor(muted);
        titles.addView(subtitle);
        bar.addView(titles, new LinearLayout.LayoutParams(0, dp(52), 1));
        TextView sync = new TextView(this);
        sync.setText("同步");
        sync.setTextSize(13);
        sync.setTextColor(text);
        sync.setGravity(Gravity.CENTER);
        sync.setPadding(dp(10), 0, dp(10), 0);
        sync.setOnClickListener(v -> {
            captureAttempts = 0;
            handler.removeCallbacks(captureTask);
            handler.post(captureTask);
            Toast.makeText(this, "正在读取当前页面余额…", Toast.LENGTH_SHORT).show();
        });
        bar.addView(sync, new LinearLayout.LayoutParams(dp(56), dp(52)));
        root.addView(bar);

        ProgressBar progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        root.addView(progress, new LinearLayout.LayoutParams(-1, dp(3)));

        FrameLayout webHost = new FrameLayout(this);
        web = new WebView(this);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        CookieManager.getInstance().setAcceptCookie(true);
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                if (isCampusUrl(url)) return false;
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
                } catch (Exception ignored) {}
                return true;
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                captureAttempts = 0;
                handler.removeCallbacks(captureTask);
                handler.post(captureTask);
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progress.setProgress(newProgress);
            }
        });
        webHost.addView(web, new FrameLayout.LayoutParams(-1, -1));
        root.addView(webHost, new LinearLayout.LayoutParams(-1, 0, 1));

        TextView hint = new TextView(this);
        hint.setText("使用校园网账号登录；会话会加密保存，失效后请重新完成验证码登录。");
        hint.setTextSize(10);
        hint.setTextColor(muted);
        hint.setGravity(Gravity.CENTER);
        hint.setPadding(dp(12), dp(6), dp(12), dp(8));
        root.addView(hint);

        setContentView(root);
        if (Build.VERSION.SDK_INT >= 21) {
            root.setOnApplyWindowInsetsListener((view, insets) -> {
                view.setPadding(0, insets.getSystemWindowInsetTop(),
                        0, insets.getSystemWindowInsetBottom());
                return insets;
            });
            root.requestApplyInsets();
        }
        if (Build.VERSION.SDK_INT >= 21) {
            getWindow().setStatusBarColor(background);
            getWindow().setNavigationBarColor(background);
            int flags = root.getSystemUiVisibility();
            if (dark) flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            else flags |= View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            root.setSystemUiVisibility(flags);
        }
        if (prefs.getBoolean(NetworkFeeSync.KEY_READY, false)) {
            web.setVisibility(View.INVISIBLE);
            TextView loading = new TextView(this);
            loading.setText("正在更新网费…");
            loading.setTextColor(muted);
            loading.setTextSize(14);
            loading.setGravity(Gravity.CENTER);
            webHost.addView(loading, new FrameLayout.LayoutParams(-1, -1));
            new Thread(() -> {
                NetworkFeeSync.Result result = NetworkFeeSync.fetch(prefs);
                handler.post(() -> {
                    if (destroyed || isFinishing()) return;
                    if (result.success()) {
                        completeSync(result.balance);
                    } else {
                        webHost.removeView(loading);
                        web.setVisibility(View.VISIBLE);
                        if (result.loginRequired) {
                            hint.setText("网费登录已过期，请完成验证码登录；成功后自动同步并返回。");
                        }
                        web.loadUrl(URL);
                    }
                });
            }, "NetworkFeeManualSync").start();
        } else {
            NetworkFeeSession.restore(prefs, false);
            web.loadUrl(URL);
        }
    }

    private boolean isCampusUrl(String value) {
        try {
            Uri uri = Uri.parse(value);
            String host = uri.getHost();
            return "https".equalsIgnoreCase(uri.getScheme()) && host != null
                    && ("nwpu.edu.cn".equalsIgnoreCase(host)
                    || host.toLowerCase(java.util.Locale.ROOT).endsWith(".nwpu.edu.cn"));
        } catch (Exception ignored) {
            return false;
        }
    }

    /** 先让 WebView 处理返回键，方便在自助站里返回。 */
    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    // ---- 余额抓取 ----

    /** 读取到可信余额即保存并返回；余额未变化也视为同步成功。 */
    private void captureBalance() {
        if (web == null || completed || capturing || isFinishing()
                || !isBalancePage(web.getUrl())) return;
        capturing = true;
        web.evaluateJavascript(BALANCE_JS, result -> {
            capturing = false;
            if (completed || isFinishing()) return;
            try {
                String text = new JSONArray("[" + result + "]").getString(0);
                String value = NetworkFeeSync.parseBalance(text);
                if (value == null) return;
                completeSync(value);
            } catch (Exception ignored) {
            }
        });
    }

    private boolean isBalancePage(String value) {
        try {
            Uri uri = Uri.parse(value == null ? "" : value);
            return "https".equalsIgnoreCase(uri.getScheme())
                    && "zizhu.nwpu.edu.cn".equalsIgnoreCase(uri.getHost())
                    && uri.getPort() == 8900 && "/home".equals(uri.getPath());
        } catch (Exception ignored) {
            return false;
        }
    }

    private void completeSync(String value) {
        if (sessionGeneration != NetworkFeeSession.generation(prefs)) {
            finish();
            return;
        }
        completed = true;
        handler.removeCallbacks(captureTask);
        NetworkFeeSync.save(this, prefs, value);
        BackgroundSyncScheduler.schedule(this);
        Toast.makeText(this, "网费余额已同步：" + value + " 元", Toast.LENGTH_SHORT).show();
        finish();
    }

    @Override
    protected void onPause() {
        captureBalance();
        CookieManager.getInstance().flush();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        destroyed = true;
        handler.removeCallbacks(captureTask);
        if (web != null) {
            web.stopLoading();
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
