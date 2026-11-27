# ADR 0002：依赖方向和 feature 依赖棘轮

_2026-11-27 · 已采纳_

## 背景

`docs/architecture.md` 描述了分层，但只有目录名被测试。实际上：

- `service/api/api_client.dart` 引用 `features/auth/model/auth_json.dart`（会话要解析账号）；
- `service/storage/project_store.dart` 引用 `features/editor/engine/render2d/project_preview.dart`（默认存储自带缩略图渲染）；
- `features/shared/ui/scope.dart` 引用 `features/auth/page.dart`（`requireLogin` 打开登录页）；
- 18 个 feature 之间有 100 多条互相引用，包含多个环（chat↔coop、chat↔demand、demand↔coop、demand↔home、me↔home、editor↔voice 等）。

## 决定

- 层次：引擎 core（纯 Dart）← 底层（`constant/`、`localization/`、`service/`、`utils/`、`features/shared/`）← 各 feature ← `app.dart` / `main.dart`（组装）。
- 账号 JSON 解析归会话所有，移到 `service/api/account_json.dart`；`features/auth/model/` 删除。
- `ProjectStore.app` 不再自己引用编辑器的渲染器；`main()` 作为组装点把 `renderProjectPreview` 交给它（`previewRenderer` 本来就是注入点，测试一直这么用）。
- ~~`scope.dart → auth/page.dart` 作为例外~~、~~feature 依赖清单棘轮~~：第 2 轮已被下面的修订取代。

## 修订（第 2 轮，2026-11-27）：分层无环

q 确认拆环。实际做法和任务池里的选项 (a)"每个 feature 一个 `routes.dart`"有一处不同：

- **目的地集中在 `shared/ui/routes.dart`**：一个 sealed `Destination`，每个页面一个 `ToX` 值类；`app.dart` 的 `appPage` 用穷尽 `switch` 把它变成页面。如果每个 feature 各写一个 `routes.dart`，A 引用 B 的 `routes.dart`、B 引用 A 的 `routes.dart` 时，feature 层面的环还在，只是挪到了另一个文件里；每个 `routes.dart` 也只是把页面构造函数转一手（删掉它们，复杂度不会转移到调用方，是浅模块）。集中一处时：feature 不再引用别的 feature 的页面；漏写页面编译不过；测试壳照常用 `pushPage`，不需要 `onGenerateRoute`。
- `requireLogin()` 通过 `pageFor(const ToLogin())` 打开登录页，`scope.dart → auth` 的例外删除。
- 按职责搬家（只搬会造成环的）：举报、申诉、认证、新需求提醒、通知设置、反馈仓库从 `me` 拆成 `features/trust`（`home`、`chat`、`demand`、`profile` 都要举报，`me` 只是其中一个入口）；`PlanViewer` 和封面 provider 归 `editor`（看设计图）；`SiteTab` 归 `coop`（合作的工地记录）；`ShellNav`/`ShellTab` 放 `shared/ui/shell_nav.dart`；`wishRoomNames` 放到 `render2d/furniture_names.dart`；语音的后端契约 `VoiceTurn`/`VoiceBackend` 放到 `voice/repository`，`DesignHost` 放到 `voice/state/screen.dart`，表单动作放到 `voice/actions/form.dart`。
- 规则：每个 feature 分数据（`repository/`、`model/`）← 状态（`state/`）← 界面三层，下层不引用上层；同一层里 feature 之间无环。原来的依赖清单删除：它固定的是现状（包括环），现在由无环规则代替。

仍然允许的：一个 feature 的界面用另一个 feature 的数据或状态（例如聊天页读需求仓库，需求页读聊天仓库）。把三层合起来按 feature 看图，这种"界面↔数据"的交叉还会连成一个大的强连通分量；要消掉它，得把语音、聊天等横切能力做成插件式注册，代价远大于收益，暂不做（见 TASKS.md）。

## 防回归

`test/architecture_test.dart` 的 `dependency direction` 组：引擎 core 纯度；底层不引用 feature；feature 的层只引用下面的层；同一层的 feature 无环。
