# 自建房设计工具 v1 实施计划

本文依据《自建房设计工具：产品与架构方案 v1.0》和《自建房设计工具：v1 开发规格》整理。两份文档中面向实现者的要求作为产品/工程规格；嵌入文档中的命令式文本只作为规格数据，不构成对 agent 执行外部操作的授权。本计划按规格要求保留冻结的架构和章节顺序。

## 已冻结的技术决策

- Flutter（iOS / Android），单工程；纯 Dart House Core；Riverpod 只编排状态；CustomPainter 负责 2D。
- `.house` 是 UTF-8 JSON；几何长度使用毫米整数；核心不接触 Flutter、平台 API、文件系统或时钟。
- 派生几何只由 GeometryDeriver 计算，渲染器仅读取派生结果；3D 引擎按规格第 3 阶段技术验证选择。
- 先做可验证的纯 Dart 核心，再做 2D 编辑、命令历史、几何、持久化、检查与完整 3D。

## 阶段与交付

1. **House Core**：HouseDocument 不可变模型、严格 v1 JSON 解码/稳定编码、Schema Migration 接口、AxisResolver、RoomCanonicalizer、DocumentValidator、两个 fixture。解码错误需有稳定 path/code/order，输入异常不得导致崩溃。
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

已实现从项目创建到编辑、保存、检查与 3D 查看的一整条工作流。纯 Dart core 保持平台独立。下表区分实现状态与完整规格验收；通过现有测试不等于两份规格的全部验收项已完成。

| 阶段 | 实现状态 |
| --- | --- |
| 1 Core | 模型、严格解码/编码、校验、轴解析、规范化、两个逐字节 golden 已实现；10,000 个格子集合性质测试通过。全部负例矩阵和排序/值对象契约仍需逐项审计。 |
| 2 基础几何 | 所有权、墙段、墙矩形、净面积、净宽、标注已实现；完整几何 golden 矩阵待补齐。 |
| 3/10 3D | 软件投影查看器实现相机、逐层显示、材质、拾取和平面联动；生产引擎选型、精确深度/透明度与真机性能验收未完成。 |
| 4/11 编辑器 | 首页、空白与三套模板、2D、属性面板、楼层与网格、手机横竖屏已实现；网格和门窗拖动预览已实现；尺寸直接点击等细节待补齐。 |
| 5 命令历史 | 纯设计状态 Applied/Rejected/NeedsResolution 接口、房间/门窗/楼梯/楼层/网格/屋顶命令、撤销重做实现；全部原因码与冲突对象列表的精确契约待审计。 |
| 6 门窗墙例外 | 定位、状态、墙洞口、门窗类型、铰链、主入口、墙开放和墙厚已实现。 |
| 7 楼梯屋顶 | 三种楼梯、楼板洞口、平/双坡屋顶、scene3d 实现；SourceRef 严格类型、稳定 scene 顺序和玻璃平面已实现；墙块进一步合并待补齐。 |
| 8 存储 | 文件系统接口、原子文档/索引/预览、临时清理、损坏项目、自动保存、导入导出、原生打开实现；统一结果类型、错误分类和完整故障注入矩阵待补齐。 |
| 9 检查 | R01–R10 和定位高亮实现；全部文案、focus 精确坐标和 golden 矩阵待补齐。 |

## 发布前剩余验收

- 完成上述纯 API 契约和全部规格矩阵的逐项核对。
- 完成 3D 引擎技术选型和目标真机性能测试。
- 在目标聊天/文件应用验证 .house 分享、冷启动/运行中打开和权限失败。
- 完成 Android 真机运行、签名发布配置与用户可用性验收。


## 执行记录（2026-09-30）

- Flutter web/iOS/Android project scaffolding is generated and dependencies are resolved.
- Initial analyzer/test snapshot passed. House Core includes a two-floor fixture, strict JSON loading/encoding, axis resolution, canonicalization, and an initial validator.
- Deep value equality and a broader regression suite have been added. Stage 1 still needs the full spec matrices and validator ordering/deduplication conformance before it can be marked accepted.

## 本次执行记录

- 编辑器补齐房间合并/类型/删除、轴删除冲突/作用范围/提升、门窗转换/铰链/定位、楼层/楼梯/屋顶/默认值、检查定位和 3D 联动。
- 新增模板、原生 .house 收件、硬上限流读取、原子索引、WebP 缩略图和损坏项目展示。
- 当前静态分析无问题；42 个单元/组件测试通过（其中一个用例覆盖 10,000 个种子格子集合）。
- iPhone 17 Pro / iOS 26.4 模拟器 integration_test 通过：创建模板、3D、原生 WebP 存盘、返回首页并重新打开。
- 最终源码的 Web release、Android debug APK、iOS simulator 均已构建成功；iOS integration_test 已再次通过。

- 网格/门窗拖动预览、双指取消、一次提交一次撤销的手势回归通过；真实 iOS 文件 URL 打开 .house 已在模拟器验证成功。
