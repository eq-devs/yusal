# Yusal 平台 MVP：实际做了什么、部署到哪了

更新：2026-11-04。分支 `claude/project-thread-wuq5me`，PR #1。

## 1. 一句话

设计工具保持不动，新增 `lib/platform/`：首页是“别人设计的房子”作品流，房子页可点赞、评分、评论、为这栋房子招人；工人 / 包工头 / 工程师可入驻接活。后端全部是内存 mock，界面 Airbnb 风格、木头 / 土壤主色、支持夜间模式、中 / 哈 / 俄三语。

## 2. 做了的功能

| 模块 | 内容 | 主要文件 |
| --- | --- | --- |
| 首页（作品流） | 搜索胶囊、排序（最新 / 最热 / 评分）、地区、“正在找施工方”筛选；卡片 = 平面图 + 地区 / 面积 / 层数 / 房间数 + 预估造价 + 作者 + 赞 / 评论数；悬浮按钮“设计我的房子” | `lib/platform/ui/home/home_page.dart`、`house_card.dart` |
| 房子页 | 大图 → 标题与事实 → 作者（私信）→ 故事 → 设计数据 → 这栋房子在招谁 → 评论（带 1–5 星）。访客底部“去报名 / 报价”或“我能建这栋房子”；房主底部“招人” | `lib/platform/ui/home/post_page.dart` |
| 发布设计 | 从“我的设计”或编辑器一键发布：标题、说明、地区、标签、是否欢迎施工方；面积、层数、房间数、造价从设计自动算出 | `lib/platform/ui/home/publish_post_page.dart`、`lib/platform/snapshot/design_snapshot.dart` |
| 招人 / 承包 | 从房子页发布需求，工程量从快照带出；报名、报价、对比、录用、合作约定、结束、评价（沿用首轮 MVP） | `lib/platform/ui/publish/`、`demands/`、`deals/` |
| 入驻 | 我的 → “入驻接活”选工人 / 包工头 / 工程师，再填名片；接活大厅降为一个入口 | `lib/platform/ui/profile/profile_edit_page.dart`、`discover/discover_page.dart` |
| 消息 | 聊天与通知（点赞、评论、报名、合作等），点通知直达房子 / 需求 | `lib/platform/ui/chat/` |
| 我的 | 我发布的房子、入驻、接活大厅、备份、外观（自动 / 日间 / 夜间）、语言、开发者工具、审核后台 | `lib/platform/ui/me/` |
| 底部导航 | 首页 · 设计 · 消息 · 我的 | `lib/platform/ui/shell.dart` |

## 3. 视觉与主题

- 色板在 `lib/platform/ui/theme.dart` 的 `YTokens`：日间主色胡桃木 `#A3673B`、底 `#FFFCF8`、面板 `#F6F0E8`、墨 `#2B2118`；夜间底 `#15110E`、主色 `#D28B5A`、字 `#F3EBE2`。
- 夜间模式跟随“我的 → 外观”，默认跟随系统。
- 设计工具（制图区）保留原配色。

## 4. Mock 后端说明

- 所有数据在 `lib/platform/data/mock/mock_backend.dart` 内存里，每次启动重新灌入 `mock_seed.dart` 的种子数据（4 个账号、4 栋已发布的房子、需求、报名、评论、点赞）。
- 登录：任意手机号，验证码固定 `1234`。
- 可注入时钟（`MockClock`）、模拟延迟、模拟离线；需求发布后约 1 秒自动过审，含违禁词（如“押金”）被拒。
- 接真实后端时按 `lib/platform/data/repositories.dart` 的接口实现（含 `PostRepository`），界面与领域模型不改。

## 5. 测试

```
flutter analyze   # 无告警
flutter test      # 218 个用例全部通过
```

- `test/platform/mock_backend_test.dart`：账号、需求、报名、报价、合作、评价、到期、审核规则。
- `test/platform/posts_test.dart`：发布作品、点赞、评分（房主不能给自己评分、重复评分覆盖）、评论限流、违禁词、按房子查需求。
- `test/widget_test.dart`：首页作品流、房子页、房主招人入口、设计页、俄语界面。

## 6. 安装与发布状态

| 目标 | 状态 |
| --- | --- |
| Pixel 8 Pro | 已安装 0.4.0 新版（手机系统语言为哈萨克语，界面随之显示哈语；可在“我的 → 语言”切换） |
| Web（Firebase Hosting，项目 `yusal-web`） | 线上 https://yusal-web.web.app 仍是上一版 MVP。新版已在 Mac 上构建到 `build/web`，发布命令在远程会话里被安全检查拦住，需要在 Mac 上手动执行： |

```
cd /Users/estai/Desktop/eq/yusal && firebase deploy --only hosting
```

或在 Claude Code 的 `permissions.allow` 里加入 `"Bash(firebase deploy:*)"` 后再让我执行。

## 7. 还没做的

- 作品实景 / 施工照片，现在只有平面图快照。
- 关注 / 粉丝、评论回复。
- 工程师付费图审、包工头整包报价模板。
- 短信验证码、图片上传、推送、真实数据持久化。
- 设计工具本身的俄语文案（俄语模式下回落为哈萨克语）。
