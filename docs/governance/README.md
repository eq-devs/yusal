# 架构治理

这里记录 yusal（App）和 yusal-api（后端）的架构降熵工作：每一轮做了什么、还有什么没做、为什么这样定。

- [PROGRESS.md](PROGRESS.md)：每一轮的结果和验证方式
- [TASKS.md](TASKS.md)：任务池（按价值排序）和需要产品或架构决定的待确认事项
- [adr/](adr/)：架构决策记录，一条决定一个文件

规则：

1. 每一轮必须闭环：新的标准实现上线时，旧调用方全部迁移，旧实现在同一轮删除。
2. 定下来的规范要变成测试（`test/architecture_test.dart`、`test/platform/design_system_test.dart`、`test/platform/api_codes_test.dart`，后端 `internal/pkg/apperr/contract_test.go`），不靠记忆。
3. 需要产品决定、破坏性迁移或大的架构变化的事项，记进 TASKS.md 的"待确认"，不擅自做。
