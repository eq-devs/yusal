# Shared by release.sh / patch.sh. Sourced, not run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Same dart-defines for a release and every patch to it: Shorebird refuses a
# patch whose --dart-define values differ from its release.
DEFINES="${DEFINES:-$ROOT/config/dart_defines.release.json}"
# Where finished .aab / .ipa files are copied.
OUT_DIR="${OUT_DIR:-$HOME/Desktop/eq/yusal-release}"

die() { echo "错误: $*" >&2; exit 1; }
info() { echo "==> $*"; }

command -v shorebird >/dev/null || die "未找到 shorebird，先安装: curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | bash"
[ -f shorebird.yaml ] || die "缺少 shorebird.yaml，先运行 shorebird init"
grep -q "^app_id: PENDING" shorebird.yaml && die "shorebird.yaml 还没有 app_id，先 shorebird login 再 shorebird init"
[ -f "$DEFINES" ] || die "缺少 $DEFINES"

# version: 0.4.0+5  ->  0.4.0+5
pubspec_version() { sed -n 's/^version: *//p' pubspec.yaml | tr -d '[:space:]'; }

check_platform() {
  case "$1" in
    android|ios) ;;
    *) die "平台只能是 android 或 ios，收到: $1" ;;
  esac
}

check_android_signing() {
  [ -f android/key.properties ] || die "缺少 android/key.properties（上传密钥在 ~/Desktop/eq/yusal-signing/），否则会用 debug 签名，商店不收"
}
