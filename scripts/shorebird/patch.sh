#!/usr/bin/env bash
# 给已上架的版本推送 Dart 代码热更新（不经过商店审核）。
#
#   scripts/shorebird/patch.sh android            # 补丁发到 staging，先自测
#   scripts/shorebird/patch.sh ios
#   scripts/shorebird/patch.sh all
#
# 可选环境变量：
#   RELEASE_VERSION=0.4.0+5   打给哪个版本，默认 pubspec.yaml 当前 version
#   TRACK=stable              直接发给所有用户（默认 staging）
#   ROLLOUT=20                灰度百分比（默认 100）
#
# 只能改 Dart 代码。改了原生代码、插件、Android/iOS 配置或新增资源时，
# Shorebird 会报 native/asset diff：那种改动必须走 release.sh 重新上架。
source "$(dirname "$0")/_common.sh"

target="${1:-}"
[ -n "$target" ] || die "用法: $0 android|ios|all"
platforms=("$target"); [ "$target" = all ] && platforms=(android ios)

release_version="${RELEASE_VERSION:-$(pubspec_version)}"
track="${TRACK:-staging}"
rollout="${ROLLOUT:-100}"
info "补丁 -> 版本 $release_version，通道 $track，灰度 $rollout%"

for p in "${platforms[@]}"; do
  check_platform "$p"
  [ "$p" = android ] && check_android_signing
  args=(patch "$p"
    --release-version="$release_version"
    --track="$track"
    --rollout="$rollout"
    --dart-define-from-file="$DEFINES")
  info "shorebird ${args[*]}"
  shorebird "${args[@]}"
done

if [ "$track" = staging ]; then
  cat <<MSG
==> 补丁已发到 staging。用 staging 测试包验证无误后，转为正式：
      shorebird patches list --release-version=$release_version
      shorebird patches promote --release-version=$release_version --patch-number=<号>
    出问题时回滚：
      shorebird patches rollback --release-version=$release_version --patch-number=<号>
MSG
fi
