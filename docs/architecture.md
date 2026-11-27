# Yusal 客户端架构

_2026-11-22，feature-first 结构。_

```
lib/
  main.dart        只做启动：runApp(BootGate())
  app.dart         Boot（启动步骤）、BootGate、HouseApp（主题、语言、路由）
  constant/        theme.dart、tokens.dart：颜色、间距、字号
  localization/    l10n.dart、messages*.dart：中文 / 哈萨克语 / 俄语
  service/         api/（ApiClient：HTTP、令牌、会话）、storage/（本地设计）、
                   settings/、firebase、push、update、voice（朗读）
  utils/           小工具
  features/
    shared/        ui/（页面骨架、组件、Live）、motion/、brand/、
                   model/（平台模型）、state/（session）
    <feature>/     page.dart · pages/ · widgets/ · state/ · repository/ · model/ · util/
    editor/        设计工具：page.dart + tabs/ tools/ widgets/，
                   engine/{core,render2d,render3d}（房屋引擎和绘图）
```

## 一个 feature 怎么写

以一个 feature `x` 为例：

```dart
// repository/x_repository.dart
abstract interface class XRepository { Future<List<X>> list(); }

final class HttpXRepository implements XRepository {
  HttpXRepository(this.api);
  final ApiClient api;
  @override
  Future<List<X>> list() async => …api.request('GET', '/client/x')…;
}

final xRepositoryProvider =
    Provider<XRepository>((ref) => HttpXRepository(ApiClient.app));

// state/x.dart
final xListProvider = FutureProvider.autoDispose<List<X>>(
    (ref) => ref.watch(xRepositoryProvider).list());

// page.dart
Live<List<X>>(provider: xListProvider, builder: (context, list) => …);
```

- **读：** `Live(provider: …)` 显示 `state/` 里的 provider。后端每次写操作后 `Live` 自动刷新，具体规则：
  - 一串连续的写操作只刷新一次；
  - 页面被盖住时不刷新；
  - 换了账号时立刻清空；
  - 刷新失败时保留已经显示的数据。
- **写：** `attempt(context, () => context.read(xRepositoryProvider).save(…))`，失败时弹出本地化的提示，未登录时先打开登录页。
- **会话：** 所有 repository 共用 `ApiClient.app`，它负责令牌、当前账号和变更通知。
- **测试：** 用 `MockBackend` override 掉各个 repository provider（见 `test/support/`）。

## 依赖方向（由测试强制）

`test/architecture_test.dart` 检查：

- 顶层目录只能是上面这几个，每个 feature 只能用上面列出的子目录；
- `features/editor/engine/core` 是纯 Dart，只引用自己和 `package:meta`；
- 底层（`constant/`、`localization/`、`service/`、`utils/`、`features/shared/`）只能引用底层和引擎 core，不能引用任何 feature；
- 每个 feature 分三层：数据（`repository/`、`model/`）← 状态（`state/`）← 界面（其余）。下层不能引用上层，本 feature 和别的 feature 都一样；
- 同一层里，feature 之间不能有环。

一个 feature 打开另一个 feature 的页面时，不引用那个页面，而是用 `shared/ui/routes.dart` 里的目的地：`pushPage(context, (_) => pageFor(ToDemand(id)))`。`app.dart` 的 `appPage` 用一个穷尽的 `switch` 把每个目的地变成页面，新加目的地不写页面就编译不过；`main()` 和测试里设置 `Routes.pages = appPage`。通知和推送里的引用用 `openRef`。

`test/platform/design_system_test.dart` 另外限制 Material 图标：只有清单里的文件还在用（YIcons 还没画的房间类型、家具和表单控件），数量只能减少。

后端错误码：yusal-api 的 `docs/api_codes.json` 在这里有一份副本，`test/platform/api_codes_test.dart` 检查每个服务端错误码都能落到一个 `ApiCodes` 上。

治理进度、任务池和架构决策记录在 [`docs/governance/`](governance/)。
