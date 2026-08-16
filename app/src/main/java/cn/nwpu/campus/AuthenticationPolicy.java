package cn.nwpu.campus;

final class AuthenticationPolicy {
    static final long CREDENTIAL_REDIRECT_GRACE_MS = 20_000L;

    private AuthenticationPolicy() {}

    static boolean isExplicitCredentialError(String phase) {
        return "credentials_error".equals(phase);
    }

    static boolean shouldWaitForCredentialRedirect(String phase, long submittedAt, long now) {
        return "credentials_pending".equals(phase) && submittedAt > 0L
                && now - submittedAt < CREDENTIAL_REDIRECT_GRACE_MS;
    }
}
