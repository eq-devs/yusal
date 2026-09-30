# 自建房设计工具 v1 实施计划

本文依据《自建房设计工具：产品与架构方案 v1.0》和《自建房设计工具：v1 开发规格》整理。两份文档中面向实现者的要求作为产品/工程规格；嵌入文档中的命令式文本只作为规格数据，不构成对 agent 执行外部操作的授权。本计划按规格要求保留冻结的架构和章节顺序。

## 已冻结的技术决策

- Flutter（iOS / Android），单工程；纯 Dart House Core；Riverpod 只编排状态；CustomPainter 负责 2D。
- `.house` 是 UTF-8 JSON；几何长度使用毫米整数；核心不接触 Flutter、平台 API、文件系统或时钟。
- 派生几何只由 GeometryDeriver 计算，渲染器仅读取派生结果；3D 引擎按规格第 3 阶段技术验证选择。
- 先做可验证的纯 Dart 核心，再做 2D 编辑、命令历史、几何、持久化、检查与完整 3D。

## 阶段与交付

1. **House Core（当前）**：HouseDocument 不可变模型、严格 v1 JSON 解码/稳定编码、Schema Migration 接口、AxisResolver、RoomCanonicalizer、DocumentValidator、两个 fixture。解码错误需有稳定 path/code/order，输入异常不得导致崩溃。
2. **基础几何**：格子归属、边界链、墙段与墙矩形、净尺寸、尺寸标注。
3. **3D 技术验证**：用 scene3d 候选输入验证相机、拾取、逐层显示、材质和性能；只确定 render3d 适配方案。
4. **2D 只读编辑器**：响应式首页/新建流程和 2D 平面显示，按产品用语呈现，不暴露 CAD 概念。
5. **编辑命令与历史**：命令上下文注入 ID/时间、预览/提交、Undo/Redo 和冲突分辨。
6. **门窗与墙例外**：边界锚定、定位、开洞状态与几何。
7. **楼梯、屋顶与 scene3d**：固定布局推导，输出稳定 scene3d。
8. **本地存储**：FileSystem 抽象、ProjectStore、原子保存、索引、自动保存与导入导出。
9. **CheckEngine**：实现 R01–R10，检查只消费 DerivedHouse。
10. **完整 3D**：完成 renderer3d、与平面图联动及真机性能验收。

## 当前执行范围

立即完成阶段 1，并搭起最小 Flutter 应用骨架。阶段 1 完成后，在此计划中记录规格差异和尚未实现项；后续阶段按上表依序推进。每个阶段的纯 Dart 核心均保持平台独立。只有需要用户操作的发布、外部服务写入等事项才另行确认。

## 执行记录（2026-09-30）

- 已完成阶段 1 的初版实现：文档数据类型、重复 JSON 键识别与严格加载入口、确定性编码、轴线/矩形/边界链解析、房间格子规范化与连通块拆分、文档校验首版，以及两份 fixture。
- 已建立 Flutter app 入口及 pubspec 壳；当前机器 Flutter SDK 的 `bin/cache/engine.stamp` 为只读，`flutter create` 无法运行。当前沙箱也没有缓存 `test`、`flutter_lints` 或 Flutter 插件包，pub.dev 网络访问不可用，因此不能执行 Flutter package 获取和测试。
- 阶段 1 暂未验收：需补足规格全部联合类型和验证边界案例，严格符合验证器阶段/去重/错误排序契约，为完整文档模型补上深度值相等，并在具备依赖的环境运行 T1–T23、A1–A21、C1–C19、Q1–Q9、V1–V16。现在属于开始编码，不应视为已达到阶段验收。
