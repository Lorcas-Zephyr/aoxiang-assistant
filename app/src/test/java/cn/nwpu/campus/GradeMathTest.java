package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class GradeMathTest {
    @Test public void computesCreditWeightedAverage() {
        assertEquals(86.25, GradeMath.weightedAverage(
                new double[]{2, 4, 2}, new double[]{75, 97, 76}), 0.001);
    }

    @Test public void excludesPassFailAndInvalidCredits() {
        assertEquals(90, GradeMath.weightedAverage(
                new double[]{2, 1, 0}, new double[]{90, Double.NaN, 100}), 0.001);
    }

    @Test public void returnsNanWhenNoNumericGradeExists() {
        assertTrue(Double.isNaN(GradeMath.weightedAverage(
                new double[]{1, 2}, new double[]{Double.NaN, Double.NaN})));
    }

    @Test public void rejectsMismatchedArrays() {
        assertThrows(IllegalArgumentException.class,
                () -> GradeMath.weightedAverage(new double[]{1}, new double[]{}));
    }
}
