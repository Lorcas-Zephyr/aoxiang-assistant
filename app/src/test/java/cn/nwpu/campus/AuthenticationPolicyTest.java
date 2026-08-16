package cn.nwpu.campus;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class AuthenticationPolicyTest {
    @Test public void onlyExplicitCredentialErrorRejectsPassword() {
        assertTrue(AuthenticationPolicy.isExplicitCredentialError("credentials_error"));
        assertFalse(AuthenticationPolicy.isExplicitCredentialError("credentials_required"));
        assertFalse(AuthenticationPolicy.isExplicitCredentialError("credentials_pending"));
    }

    @Test public void submittedCredentialsGetRedirectGracePeriod() {
        long submittedAt = 10_000L;
        assertTrue(AuthenticationPolicy.shouldWaitForCredentialRedirect(
                "credentials_pending", submittedAt, submittedAt + 19_999L));
        assertFalse(AuthenticationPolicy.shouldWaitForCredentialRedirect(
                "credentials_pending", submittedAt,
                submittedAt + AuthenticationPolicy.CREDENTIAL_REDIRECT_GRACE_MS));
        assertFalse(AuthenticationPolicy.shouldWaitForCredentialRedirect(
                "credentials_required", submittedAt, submittedAt + 1_000L));
    }

    @Test public void collectionAuthenticationProblemsRequireVisibleUnifiedLogin() {
        assertTrue(AuthenticationPolicy.requiresInteractiveCollectionLogin("grades", "interactive_login"));
        assertTrue(AuthenticationPolicy.requiresInteractiveCollectionLogin("schedule", "sms_required"));
        assertTrue(AuthenticationPolicy.requiresInteractiveCollectionLogin("electricity", "credentials_required"));
        assertFalse(AuthenticationPolicy.requiresInteractiveCollectionLogin("validate", "sms_required"));
        assertFalse(AuthenticationPolicy.requiresInteractiveCollectionLogin("grades", "data"));
    }
}
