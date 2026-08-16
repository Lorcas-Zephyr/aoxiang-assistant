package cn.nwpu.campus;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class UnifiedAuthTrackerTest {
    @Test public void onlyLeavingUisAfterVisitingItCountsAsSuccess() {
        UnifiedAuthTracker tracker = new UnifiedAuthTracker();
        tracker.record("https://jwxt.nwpu.edu.cn/student/sso-login");
        assertFalse(tracker.hasExited());

        tracker.record("https://uis.nwpu.edu.cn/cas/login?service=test");
        assertFalse(tracker.hasExited());
        tracker.record("https://uis.nwpu.edu.cn/cas/login?execution=next");
        assertFalse(tracker.hasExited());

        tracker.record("https://jwxt.nwpu.edu.cn/student/sso-login?ticket=test");
        assertTrue(tracker.hasExited());
    }

    @Test public void resetRequiresACompleteNewTransition() {
        UnifiedAuthTracker tracker = new UnifiedAuthTracker();
        tracker.record("https://uis.nwpu.edu.cn/cas/login");
        tracker.record("https://jwxt.nwpu.edu.cn/student/home");
        tracker.reset();

        tracker.record("https://jwxt.nwpu.edu.cn/student/home");
        assertFalse(tracker.hasExited());
    }
}
