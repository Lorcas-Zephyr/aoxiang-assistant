package cn.nwpu.campus;

import java.net.URI;

final class UnifiedAuthTracker {
    private boolean visited;
    private boolean exited;

    void record(String url) {
        try {
            String host = URI.create(url).getHost();
            if ("uis.nwpu.edu.cn".equalsIgnoreCase(host)) {
                visited = true;
            } else if (visited && host != null
                    && (host.equals("nwpu.edu.cn") || host.endsWith(".nwpu.edu.cn"))) {
                exited = true;
            }
        } catch (Exception ignored) {}
    }

    boolean hasExited() {
        return exited;
    }

    void reset() {
        visited = false;
        exited = false;
    }
}
