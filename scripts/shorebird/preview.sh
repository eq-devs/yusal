#!/usr/bin/env bash
# 在连接的真机 / 模拟器上运行某个已发布版本（含 staging 补丁），用于验证补丁。
#
#   scripts/shorebird/preview.sh android          # 默认 staging 通道
#   TRACK=stable scripts/shorebird/preview.sh ios
source "$(dirname "$0")/_common.sh"

p="${1:-}"; check_platform "$p"
release_version="${RELEASE_VERSION:-$(pubspec_version)}"
shorebird preview --platform="$p" --release-version="$release_version" --track="${TRACK:-staging}"
