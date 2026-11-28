# 任务池

价值从高到低。做完的移到 PROGRESS.md。

## 待确认（需要产品或架构决定）

1. **按 feature 整体看仍有一个大的强连通分量。** 三层各自无环，但"A 的界面读 B 的仓库、B 的界面读 A 的仓库"这类交叉还在（例如聊天页读需求、需求页读聊天）。要彻底消掉，得让语音、聊天等横切能力用注册方式接入各页面，改动面很大、收益有限。建议维持现在的分层规则，除非出现具体的改动痛点。
2. **新画的 73 个图标**需要设计过目（预览图见 PR 说明）；改形状只要改 `tool/brand/icons.json` 再运行 `gen_yicons.py`。
3. **PR 63** 已移植进本分支，原 PR 可以关闭。

## 可以直接做（下一轮候选）

6. **auth controller 的 `fail()`** 仍为每个 auth 专属错误码写一行 `response.Fail`；可以改成一张表（同 `apperr.table`），保持错误码不变。
7. **超大文件**：`features/editor/page.dart`（3145 行，part 文件的宿主）、`features/admin/page.dart`（2213 行）、`features/shared/model/models.dart`（1444 行）。按职责拆分前先确认没有更好的模块边界，避免无意义搬迁。
8. **分页结果**：admin 用 `Paged`，post 仓库手读 `data['items']`；统一一种分页读取。
9. **golden 测试**：`plan_kz_template.png` 在 dev（9844cbd）的 macOS CI 上就已失败（0.05% 像素差），需要在 macOS 上 `flutter test --update-goldens test/goldens/plan_goldens_test.dart` 重新生成；两张平面图 golden 在 Linux 上也不一致。

## 外部阻塞

- yusal-api 的 GitHub Actions 在启动前就失败（多半是账单），本地测试全过。
