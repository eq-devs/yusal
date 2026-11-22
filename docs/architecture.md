# Yusal 客户端架构

_2026-11-22，和 janapost（`~/Desktop/janapost/janapost`）一样的 feature-first 结构。_

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

和 janapost 的 `referral` 一样：

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
    Provider<XRepository>((ref) => HttpXRepository(ref.watch(apiClientProvider)));

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

`test/architecture_test.dart` 检查两件事：顶层目录只能是上面这几个，每个 feature 只能用上面列出的子目录。
