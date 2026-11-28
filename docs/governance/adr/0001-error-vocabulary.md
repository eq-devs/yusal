# ADR 0001：一套错误词汇，错误码是前后端契约

_2026-11-27 · 已采纳_

## 背景

- 后端 `post`、`snapshot`、`backup` 各自声明了 `ErrNotFound`、`ErrInvalidInput` 等哨兵，各写一个 `fail()`，映射到的状态码和错误码与 `internal/pkg/apperr` 完全相同；五个 controller 手写 `ShouldBindJSON` + 400 `VALIDATION_ERROR`，与 `apperr.Bind` 相同。
- App 的 `ApiCodes` 靠人工跟后端对齐：`NOT_LINKED` 和三个 `VOICE_` 错误码 App 里没有名字，语音浮层直接写字符串 `'VOICE_BUSY'`、`'RATE_LIMITED'`；`BAD_CODE`、`BAD_PHONE` 只属于一个没有页面、后端也没有的手机验证码登录。

## 决定

- 后端：通用哨兵只在 `apperr` 里定义，模块用 `apperr.ErrX`、`apperr.Invalid/State/With`、`apperr.Fail`、`apperr.Bind`。只有自带错误码的错误（auth 的 `PROVIDER_TAKEN` 等）保留模块哨兵，在该 controller 里映射，其余交给 `apperr.Fail`。
- 后端把它可能返回的全部错误码写进 `docs/api_codes.json`，由测试从源码（AST）生成并校验；App 在 `docs/` 放一份副本，测试校验每个码都经 `ApiClient.mapCode` 落到一个 `ApiCodes` 上，且 `ApiCodes` 里除了 `NOT_SIGNED_IN`、`NETWORK` 两个客户端码之外没有别的。
- 删除手机验证码登录（`requestCode`/`verify`、`BAD_CODE`、`BAD_PHONE`）。以后要做手机登录时按真实接口重新加。

## 防回归

- `yusal-api/internal/pkg/apperr/contract_test.go`：`TestCodesContract`（码表）、`TestOneErrorVocabulary`（模块不得自建通用哨兵、不得手写 `ShouldBindJSON`）。
- `yusal/test/platform/api_codes_test.dart`。

## 影响

状态码和错误码不变；响应里的 `msg` 现在是 `apperr` 的 detail（App 只记录日志，不显示）。
