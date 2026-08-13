package cn.nwpu.campus;

public final class GradeMath {
    private GradeMath() {}

    public static double weightedAverage(double[] credits, double[] values) {
        if (credits == null || values == null || credits.length != values.length) {
            throw new IllegalArgumentException("credits and values must have equal lengths");
        }
        double weighted = 0;
        double includedCredits = 0;
        for (int i = 0; i < credits.length; i++) {
            if (credits[i] > 0 && Double.isFinite(values[i])) {
                weighted += credits[i] * values[i];
                includedCredits += credits[i];
            }
        }
        return includedCredits == 0 ? Double.NaN : weighted / includedCredits;
    }
}
