#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTED_JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"

export JAVA_HOME="${JAVA_HOME:-$DETECTED_JAVA_HOME}"
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

exec "$PROJECT_ROOT/gradlew" --no-daemon -Dorg.gradle.vfs.watch=false -Dorg.gradle.native=false \
  -p "$PROJECT_ROOT" "$@"
