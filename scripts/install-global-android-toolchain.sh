#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JDK_ARCHIVE="$PROJECT_ROOT/.toolchains/downloads/jdk17.tar.gz"
SDK_ARCHIVE="$PROJECT_ROOT/.toolchains/downloads/android-commandlinetools.zip"
JDK_HOME="/opt/microsoft-jdk-17"
ANDROID_HOME="/opt/android-sdk"

test "$(id -u)" -eq 0 || { echo "This installer must run as root." >&2; exit 1; }
test -f "$JDK_ARCHIVE" || { echo "Missing $JDK_ARCHIVE" >&2; exit 1; }
test -f "$SDK_ARCHIVE" || { echo "Missing $SDK_ARCHIVE" >&2; exit 1; }

install -d -m 0755 "$JDK_HOME" "$ANDROID_HOME/cmdline-tools/latest"
tar -xzf "$JDK_ARCHIVE" -C "$JDK_HOME" --strip-components=1

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
unzip -q "$SDK_ARCHIVE" -d "$TEMP_DIR"
cp -a "$TEMP_DIR/cmdline-tools/." "$ANDROID_HOME/cmdline-tools/latest/"

chown -R root:root "$JDK_HOME" "$ANDROID_HOME"
chmod -R a+rX "$JDK_HOME" "$ANDROID_HOME"

update-alternatives --install /usr/bin/java java "$JDK_HOME/bin/java" 1716
update-alternatives --install /usr/bin/javac javac "$JDK_HOME/bin/javac" 1716
update-alternatives --set java "$JDK_HOME/bin/java"
update-alternatives --set javac "$JDK_HOME/bin/javac"

cat > /etc/profile.d/android-sdk.sh <<'EOF'
export JAVA_HOME=/opt/microsoft-jdk-17
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
EOF
chmod 0644 /etc/profile.d/android-sdk.sh

ln -sfn "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" /usr/local/bin/sdkmanager
ln -sfn "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" /usr/local/bin/avdmanager

echo "Global JDK and Android command-line tools installed."
