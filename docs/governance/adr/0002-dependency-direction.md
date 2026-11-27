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
- `scope.dart → auth/page.dart` 暂作为唯一登记的例外：`attempt()`/`requireLogin()` 有 31 个调用文件，改成命名路由会让没有 `onGenerateRoute` 的测试壳失效，收益不抵风险。见 TASKS.md。
- feature 之间的依赖用测试里的清单固定（棘轮）：新增一条必须改清单并写理由，删掉一条必须从清单删掉，清单只会变短。环的拆解列入任务池。

## 防回归

`test/architecture_test.dart` 的 `dependency direction` 组：引擎 core 纯度、底层不反向依赖、feature 依赖清单。
