package cn.nwpu.campus;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class VersionUtilsTest {
    @Test public void extractsVersionFromTagAndReleaseName() {
        assertEquals("1.9.0", VersionUtils.extractVersion("v1.9.0"));
        assertEquals("1.10.2", VersionUtils.extractVersion("翱翔助手 v1.10.2 正式版"));
    }

    @Test public void comparesSemanticVersionSegments() {
        assertTrue(VersionUtils.isNewer("1.10.0", "1.9.9"));
        assertTrue(VersionUtils.isNewer("v2.0", "1.99.9"));
        assertFalse(VersionUtils.isNewer("1.9.0", "1.9"));
        assertFalse(VersionUtils.isNewer("1.8.1", "1.9.0"));
    }

    @Test public void buildsDirectGitCodeApkDownloadUrl() {
        assertEquals("https://gitcode.com/lorcas/aoxiang-assistant/releases/download/"
                        + "v1.9.1/aoxiang-assistant-v1.9.1.apk",
                VersionUtils.gitCodeApkDownloadUrl("v1.9.1"));
        assertEquals("", VersionUtils.gitCodeApkDownloadUrl("latest"));
    }
}
