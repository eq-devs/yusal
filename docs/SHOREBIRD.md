# Shorebird 热更新：使用说明与计划

Shorebird 让我们在**不重新提交商店审核**的情况下，把 Dart 代码的修改直接推送到用户手机上。
用户下次冷启动 App 时生效。

## 1. 能热更新什么，不能热更新什么

| 可以通过补丁（patch）更新 | 必须重新上架（release） |
| --- | --- |
| `lib/` 下的任何 Dart 代码：页面、业务逻辑、文案、修 bug | 新增或升级插件（pubspec 里的依赖带原生代码时） |
| 调整 UI、动画、校验规则、接口调用 | 修改 `android/`、`ios/` 下的原生代码或配置（权限、Info.plist、Gradle、签名等） |
| | 新增或替换资源文件（图片、字体、`assets/`） |
| | 修改 Flutter 版本、`--dart-define` 的值 |
| | 修改 `pubspec.yaml` 的 `version` |

如果补丁里混进了不能热更新的改动，`shorebird patch` 会提示 native diff / asset diff，此时**不要强行加 `--allow-*-diffs`**，应该走一次正式发布。

> 商店政策：Apple 和 Google 都允许解释执行型的代码更新，但补丁不能改变 App 的主要用途、绕过审核去加审核不会通过的功能。大功能仍然走正常上架。

## 2. 代码里接入了什么

- `shorebird.yaml`：Shorebird 的 `app_id`，并关闭引擎自带的启动时更新（`auto_update: false`）。
- `lib/platform/update/code_push.dart`：`CodePush` 在启动时、以及 App 回到前台时（间隔至少 15 分钟）检查补丁并在后台下载，下次冷启动生效。下载失败只打日志，不影响使用。
- `lib/main.dart`：`runApp` 之后调用 `CodePush().start()`。
- 依赖 `shorebird_code_push`。用 `flutter run` / `flutter build` 构建时更新器不存在，代码什么也不做，开发调试不受影响。
- `config/dart_defines.release.json`：正式包的 `--dart-define`（后端地址等）。发布和补丁必须用同一份，脚本会自动带上。

## 3. 一次性准备

1. 安装 CLI（这台 Mac 已装好）：
   ```bash
   curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | bash
   ```
2. 登录：`shorebird login`（浏览器授权）。
3. 生成 app_id：在仓库根目录运行 `shorebird init`，它会改写 `shorebird.yaml`，提交这个文件。
4. Android 签名：`android/key.properties` 指向 `~/Desktop/eq/yusal-signing/upload-keystore.jks`（不入库）。
5. iOS：沿用现在的自动签名（Bundle ID `com.yusal.client`）。

## 4. 发布新版本（会上架商店）

```bash
# 1) pubspec.yaml 的 version 递增，例如 0.4.0+4 -> 0.4.0+5
# 2) 构建（取代 flutter build appbundle / flutter build ipa）
scripts/shorebird/release.sh all        # 或 android / ios
```

产物会复制到 `~/Desktop/eq/yusal-release/yusal-<版本>.aab|.ipa`，然后按原流程上传到 Play Console / TestFlight。

**重要**：只有用 `shorebird release` 构建并上架的包才能接收补丁。之前用 `flutter build` 打的 `0.4.0+4` 不能热更新，下一次上架务必改用这个脚本。

## 5. 推送补丁（不经过商店）

```bash
# 默认发到 staging 通道，普通用户收不到
scripts/shorebird/patch.sh all

# 指定版本 / 直接正式 / 灰度
RELEASE_VERSION=0.4.0+5 scripts/shorebird/patch.sh android
TRACK=stable ROLLOUT=20 scripts/shorebird/patch.sh all
```

### 推荐流程：staging → 验证 → 正式

1. `scripts/shorebird/patch.sh all`，补丁进 staging。
2. 用测试机验证：`scripts/shorebird/preview.sh android`（或 `ios`），它会安装该版本并拉取 staging 补丁。冷启动两次确认补丁生效。
3. 转正式：
   ```bash
   shorebird patches list --release-version=0.4.0+5
   shorebird patches promote --release-version=0.4.0+5 --patch-number=1
   ```
   需要灰度时加 `--rollout=20`，之后用 `shorebird patches rollout` 逐步提高。
4. 出问题立即回滚（用户下次启动回到上一个补丁 / 原始版本）：
   ```bash
   shorebird patches rollback --release-version=0.4.0+5 --patch-number=1
   ```

## 6. 版本与分支约定

- 补丁要从**该版本发布时的代码**出发修改。每次 `release.sh` 后给提交打 tag，例如 `git tag release/0.4.0+5`，修补丁时从这个 tag 拉分支。
- 一个版本可以有多个补丁，补丁号自动递增，后一个补丁包含前一个的全部修改。
- 只要商店里还有用户在用旧版本，修 bug 时可能需要给多个版本分别打补丁。

## 7. 计划

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| 1. 接入 | SDK、`shorebird.yaml`、更新检查、脚本、文档 | 本 PR |
| 2. 首个可热更新版本 | `shorebird init` 生成 app_id；版本号升到 `0.4.0+5`；`release.sh all` 构建并上传 TestFlight / Play 内测（替代现在的 `+4` 包） | 等 Shorebird 登录和 Firebase 接入合并后进行 |
| 3. 验证 | 做一个小的 Dart 改动（比如一句文案），走 staging → preview → promote 全流程，确认真机能收到并回滚正常 | 阶段 2 之后 |
| 4. 日常使用 | 小 bug、文案、UI 调整走补丁；涉及原生/插件/资源的改动随下个版本上架 | 持续 |
| 5. 可选加强 | 补丁签名（`--patch-signing`，防止补丁被篡改）；CI 里自动 `shorebird patch`；设置页显示当前补丁号方便客服排查 | 视需要 |

### 费用

Shorebird 有免费额度（按每月补丁安装次数计费），当前用户量下够用；用户量上来后再看付费方案，具体额度以 [shorebird.dev/pricing](https://shorebird.dev/pricing) 为准。

## 8. 常见问题

- **补丁没生效**：补丁在后台下载，需要彻底关闭 App 再打开；`flutter run` 构建的包永远收不到补丁。
- **报 dart-define 不一致**：发布和补丁必须用同一份 `config/dart_defines.release.json`；改了它就必须重新发布。
- **报 native diff**：说明改动包含原生代码/插件变更，走 `release.sh`。
- **Flutter 版本**：Shorebird 使用自带的 Flutter 构建；补丁会自动使用该版本发布时的 Flutter 版本，无需手动切换。如需指定，发布时设置 `FLUTTER_VERSION=3.x.y`。
