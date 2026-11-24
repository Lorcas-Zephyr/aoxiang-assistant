package cn.nwpu.campus;

import android.content.SharedPreferences;

import org.json.JSONObject;

/**
 * 教学班排名存储：courseItemMap 归一化为 {课程ID: "名次/人数"} 后整体落盘。
 * 数据随成绩采集一并读取，展示时按成绩记录的 courseId 匹配。
 */
public final class GradeRankStorage {
    public static final String KEY_RANKS = "grade_class_ranks";

    private GradeRankStorage() {}

    public static void save(SharedPreferences store, JSONObject ranks) {
        if (ranks == null) return;
        store.edit().putString(KEY_RANKS, ranks.toString()).apply();
    }

    /** 读取指定课程的教学班排名文本；无数据时返回空字符串。 */
    public static String rankText(SharedPreferences store, String courseId) {
        if (courseId == null || courseId.isEmpty()) return "";
        try {
            JSONObject ranks = new JSONObject(store.getString(KEY_RANKS, ""));
            return ranks.optString(courseId, "");
        } catch (Exception ignored) {
            return "";
        }
    }
}
