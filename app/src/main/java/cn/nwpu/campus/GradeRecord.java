package cn.nwpu.campus;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

final class GradeRecord {
    String course;
    String category;
    String detail;
    double credits;
    Double point;
    Double score;

    GradeRecord(String course, double credits, Double point, Double score, String category, String detail) {
        this.course = course;
        this.credits = credits;
        this.point = point;
        this.score = score;
        this.category = category;
        this.detail = detail;
    }

    String pointText() {
        return point == null ? "--" : String.format(Locale.US, "%.1f", point);
    }

    String scoreText() {
        return score == null ? "--" : String.format(Locale.US, "%.0f", score);
    }

    JSONObject json() {
        JSONObject object = new JSONObject();
        try {
            object.put("course", course)
                    .put("credits", credits)
                    .put("point", point == null ? JSONObject.NULL : point)
                    .put("score", score == null ? JSONObject.NULL : score)
                    .put("category", category)
                    .put("detail", detail);
        } catch (Exception ignored) {}
        return object;
    }

    static GradeRecord from(JSONObject object) {
        return new GradeRecord(
                object.optString("course"),
                object.optDouble("credits", 0),
                object.isNull("point") ? null : object.optDouble("point"),
                object.isNull("score") ? null : object.optDouble("score"),
                object.optString("category", "课程"),
                cleanDetail(object.optString("detail", ""))
        );
    }

    static GradeRecord from(JSONArray cells) {
        String course = cells.optString(0);
        double credits = parse(cells.optString(1));
        double point = parse(cells.optString(2));
        double score = parse(cells.optString(3));
        return new GradeRecord(course, Double.isNaN(credits) ? 0 : credits,
                Double.isNaN(point) ? null : point, Double.isNaN(score) ? null : score,
                "课程", cleanDetail(cells.optString(4)));
    }

    static List<GradeRecord> keepHighest(List<GradeRecord> records) {
        Map<String, GradeRecord> bestByCourse = new LinkedHashMap<>();
        for (GradeRecord candidate : records) {
            if (candidate == null) continue;
            String key = normalizeCourseName(candidate.course);
            if (key.isEmpty()) continue;
            GradeRecord current = bestByCourse.get(key);
            if (current == null || isHigher(candidate, current)) bestByCourse.put(key, candidate);
        }
        return new ArrayList<>(bestByCourse.values());
    }

    static String normalizeCourseName(String value) {
        return value == null ? "" : value.trim().replaceAll("\\s+", " ").toLowerCase(Locale.ROOT);
    }

    private static String cleanDetail(String raw) {
        String value = raw == null ? "" : raw;
        // The grade endpoint returns escaped HTML spans for the component scores.
        for (int pass = 0; pass < 2; pass++) {
            value = value.replace("&nbsp;", " ")
                    .replace("&quot;", "\"")
                    .replace("&#39;", "'")
                    .replace("&#x27;", "'")
                    .replace("&lt;", "<")
                    .replace("&gt;", ">")
                    .replace("&amp;", "&");
            value = value.replaceAll("(?i)<br\\s*/?>", " ")
                    .replaceAll("(?s)<[^>]*>", " ");
        }
        return value.replace("\\n", " ").replace("\\r", " ")
                .replaceAll("\\s+", " ").trim();
    }

    private static boolean isHigher(GradeRecord candidate, GradeRecord current) {
        if (candidate.score != null || current.score != null) {
            if (candidate.score == null) return false;
            if (current.score == null) return true;
            int scoreComparison = Double.compare(candidate.score, current.score);
            if (scoreComparison != 0) return scoreComparison > 0;
        }
        if (candidate.point == null) return false;
        return current.point == null || candidate.point > current.point;
    }

    private static double parse(String value) {
        try {
            return Double.parseDouble(value.replaceAll("[^0-9.\\-]", ""));
        } catch (Exception ignored) {
            return Double.NaN;
        }
    }
}
