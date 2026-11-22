# Yusal 客户端架构

_2026-11-22，按 janapost（`~/Desktop/janapost/janapost/docs/architecture.md`）的 feature-first 结构整理。_

所有路径相对 `lib/`。

## 1. 分层

```
┌────────────────────────────────────────────────────────────────┐
│ app/        组合根：启动、HouseApp、Backend、HttpBackend、       │
│             ProviderScope 覆盖（每个 repository → 一个后端）      │
├────────────────────────────────────────────────────────────────┤
│ features/<x>/   page.dart · pages/ · widgets/ · state/ ·        │
│                 repository/ · model/ · util/                    │
│   UI      ConsumerWidget / Live(provider: …)：画 AsyncValue，   │
│           自己弹 toast、跳页面                                   │
│   State   state/：FutureProvider.autoDispose(.family)，只读      │
│           repository provider，不碰 BuildContext                 │
│   Repo    repository/：接口 + `mixin HttpXRepository on         │
│           ApiClient` + `xRepositoryProvider`                    │
├────────────────────────────────────────────────────────────────┤
│ shared/     ui（页面骨架、组件、Live）、theme、l10n、motion、    │
│             brand、settings、model（平台模型）、state（session）  │
│ services/   api（ApiClient：HTTP、令牌、会话、变更通知、codec）、 │
│             storage（本地设计）、firebase、push、update、voice    │
│ core/ render2d/ render3d/   房屋引擎：纯 Dart 文档与渲染          │
└────────────────────────────────────────────────────────────────┘
```

依赖只往下走：

1. `shared/ services/ core/ render*/` 不 import `features/`，也不 import `app/`。
2. `features/` 不 import `app/`；可以用别的 feature 的 repository、页面和组件。
3. `main.dart` 只做启动。

`test/architecture_test.dart` 检查这三条，并且只允许 `app features shared services core render2d render3d` 这几个顶层目录。

## 2. 数据怎么走

- **一个会话，多个 repository。** `ApiClient`（`services/api/api_client.dart`）持有令牌、当前账号、推送 token 和账号缓存，并在每次写操作后 `notify()`。每个 feature 的 `HttpXRepository` 是一个 `on ApiClient` 的 mixin，`app/http_backend.dart` 把它们组合成 `HttpBackend`，所以它们共享同一个会话。
- **Provider 覆盖。** 每个 feature 声明自己的 `xRepositoryProvider`，默认实现会抛错。`HouseApp` 用 `backendOverrides(repos)` 把它们和 `sessionProvider` 统一指向同一个后端。测试里换成 `MockBackend`（`test/support/test_scope.dart` 的 `TestScope`）。
- **读。** 页面写 `Live<T>(provider: someProvider(arg))`。provider 放在 feature 的 `state/` 里。`Live` 监听 `session.changes`：
  - 一串连续的写操作结束 60 ms 后才刷新一次；
  - 页面被别的路由盖住时不刷新，露出来时再补一次；
  - 换了账号时立刻清空，不显示上一个人的数据；
  - 刷新失败时保留已经显示的数据；
  - 下拉刷新失败会弹 toast。
- **写。** 写 `attempt(context, () => context.read(xRepositoryProvider).method(…))`，失败时弹本地化的提示；未登录时打开登录页，登录成功后重试一次。
- **Voice。** 助手只依赖 `VoiceRepositories`（Session + Demand + Cooperation），`Backend` 实现了它。

## 3. 新代码怎么写

1. 新接口：在 `features/<x>/repository/<x>_repository.dart` 里先改接口，再改 `HttpXRepository` mixin，然后改 `test/support/mock/mock_backend.dart`。
2. 新 feature 的 repository：把 mixin 加进 `HttpBackend`，接口加进 `Backend`，provider 加进 `backendOverrides`。
3. 新页面读数据：先在 `state/` 写 provider，再在页面里用 `Live(provider:)`。family 的参数只能用基本类型或基本类型组成的 record。
4. 模型放在 `shared/model/`（多个 feature 共用的平台模型），或者放进 feature 自己的 `model/`。
