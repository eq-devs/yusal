# 进度

## 现状地图（2026-11-27）

- **App**（Flutter 3.47.3，247 个 Dart 文件，约 8.3 万行）：feature-first。引擎 `features/editor/engine/core` 是纯 Dart（已由测试锁定）；底层 `constant/ localization/ service/ utils/ features/shared/`；18 个 feature。状态用 Riverpod，读用 `Live`，写用 `attempt()`；每个 feature 一个 `XRepository` 接口 + `HttpXRepository`，测试用 `MockBackend`。
- **API**（Go + Gin + MongoDB，约 2.1 万行）：`internal/module/<x>` 分 controller → service → repository；共用代码在 `internal/pkg/`；AI 网关是独立进程 `internal/gateway`。
- **前后端共享的定义**（单一来源 + 副本 + 双端测试）：`state_machines.json`（状态机）、`voice_tools.json`（语音工具表）、`api_codes.json`（错误码，本轮新增）、`yform.json`（语音小模型格式）、`price_keys.json`（价格地区、币种、价目键，本轮新增）。
- **基线**：API `go vet` + `go test` 全过（MongoDB 集成测试在本地跳过，CI 有 MongoDB）。App `flutter analyze --fatal-infos` 无问题；`flutter test` 940 过、2 个失败：`test/goldens/plan_goldens_test.dart` 的两张图，在 Linux 上渲染与 macOS 基线不同，未改动的 dev 上同样失败（CI 跑在 macOS）。

## 第 1 轮（2026-11-27）

| 批次 | 仓库 | 内容 | 防回归 |
|---|---|---|---|
| 1 | API | `post`/`snapshot`/`backup`/auth 的通用错误哨兵和 `fail()` 并入 `apperr`；手写 `ShouldBindJSON` 换成 `apperr.Bind`；删除无调用方的 `admin.ErrSelf`/`ErrRestricted` | `TestOneErrorVocabulary` |
| 2 | API + App | 错误码契约 `docs/api_codes.json`；App 补齐 4 个没有名字的错误码，语音浮层不再写裸字符串；删除没有页面也没有后端的手机验证码登录 | `TestCodesContract`、`api_codes_test.dart` |
| 3 | App | 账号 JSON 解析移到 `service/api/`；`ProjectStore` 不再引用编辑器渲染器，由 `main()` 注入；feature 依赖清单棘轮；Material 图标棘轮 | `architecture_test.dart` 的 `dependency direction`、`design_system_test.dart` |
| 4 | App | 手写的 JSON 列表解析换成 `utils/json.dart` 的 `jsonStrings`/`jsonMaps`；编辑器导出日期用引擎的 `formatDay` | — |
| 5 | API + App | 价格地区、币种、价目键的前后端契约 `docs/price_keys.json`（原来只靠注释同步） | `TestPriceKeysContract`、`price_keys_test.dart` |
| — | API | CLAUDE.md、README、`rules.go` 里指向已不存在的 `lib/platform/...` 的路径改成现在的位置 | — |

ADR：[0001 错误词汇](adr/0001-error-vocabulary.md)、[0002 依赖方向](adr/0002-dependency-direction.md)。
