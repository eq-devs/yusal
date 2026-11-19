#!/usr/bin/env bash
# 构建一个可以接收热更新的商店版本（取代 flutter build appbundle / ipa）。
#
#   scripts/shorebird/release.sh android        # 生成 .aab
#   scripts/shorebird/release.sh ios            # 生成 .ipa
#   scripts/shorebird/release.sh all            # 两个都做
#
# 发布前先把 pubspec.yaml 的 version 递增（例如 0.4.0+4 -> 0.4.0+5）。
# 只有用这个脚本构建并上传到商店的包，之后才能打补丁。
source "$(dirname "$0")/_common.sh"

target="${1:-}"
[ -n "$target" ] || die "用法: $0 android|ios|all"
platforms=("$target"); [ "$target" = all ] && platforms=(android ios)

version="$(pubspec_version)"
info "版本 $version，dart-define: $DEFINES"
mkdir -p "$OUT_DIR"

for p in "${platforms[@]}"; do
  check_platform "$p"
  args=(release "$p" --dart-define-from-file="$DEFINES" --no-patch-signing)
  [ -n "${FLUTTER_VERSION:-}" ] && args+=(--flutter-version="$FLUTTER_VERSION")
  if [ "$p" = android ]; then
    check_android_signing
    info "shorebird ${args[*]}"
    shorebird "${args[@]}"
    cp build/app/outputs/bundle/release/app-release.aab "$OUT_DIR/yusal-$version.aab"
    info "已复制到 $OUT_DIR/yusal-$version.aab"
  else
    info "shorebird ${args[*]}"
    shorebird "${args[@]}"
    ipa="$(ls -t build/ios/ipa/*.ipa | head -1)"
    cp "$ipa" "$OUT_DIR/yusal-$version.ipa"
    info "已复制到 $OUT_DIR/yusal-$version.ipa"
  fi
done

info "完成。把上面的包按原流程上传到 Play Console / TestFlight。"
