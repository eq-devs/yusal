# 任务池

价值从高到低。做完的移到 PROGRESS.md。

## 待确认（需要产品或架构决定）

1. **拆 feature 之间的环。** 现有环：chat↔coop、chat↔demand、demand↔coop、demand↔home、demand↔me、home↔me、me↔profile、profile↔chat、editor↔voice 等。多数是页面互相 `push` 对方的页面。两种做法：(a) 每个 feature 只暴露一个 `routes.dart`（打开它的页面的函数），别的 feature 只能引用它，环变成对 routes 的单向依赖；(b) 命名路由表放在 `app.dart`。推荐 (a)：改动局部，测试壳不用改。需要确认后再动，因为会碰几十个文件。
2. **`shared/ui/scope.dart` → `auth/page.dart`。** `attempt()`/`requireLogin()` 打开登录页，是底层对 feature 的唯一反向依赖。跟第 1 条一起用 routes 方案解决最自然。
3. **126 处 Material 图标。** 房间类型、家具、表单控件 YIcons 里还没画。需要设计补画后再替换；测试已限制只减不增。
4. **两个 `money()`。** `localization/l10n.dart` 的是"1 250 000 ₸"（平台金额，带单位）；`render2d/planning_names.dart` 的是按语言选千分位、不带单位（设计预算）。语义不同，不能直接合并；是否统一千分位规则（哈萨克语空格、中文逗号）是产品决定。
5. **PR 63（语音设置）** 未合并，和新布局冲突，要先决定是否还要。

## 可以直接做（下一轮候选）

6. **auth controller 的 `fail()`** 仍为每个 auth 专属错误码写一行 `response.Fail`；可以改成一张表（同 `apperr.table`），保持错误码不变。
7. **超大文件**：`features/editor/page.dart`（3145 行，part 文件的宿主）、`features/admin/page.dart`（2213 行）、`features/shared/model/models.dart`（1444 行）。按职责拆分前先确认没有更好的模块边界，避免无意义搬迁。
8. **分页结果**：admin 用 `Paged`，post 仓库手读 `data['items']`；统一一种分页读取。
9. **golden 测试跨平台**：两张平面图 golden 只在 macOS 上一致；可考虑提高容差或只在 macOS 上跑。

## 外部阻塞

- yusal-api 的 GitHub Actions 在启动前就失败（多半是账单），本地测试全过。
