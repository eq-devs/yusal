# 自建房设计工具 v0.3 交付报告

交付日期：2026-10-01（Asia/Almaty）。版本：**0.3.0+3**。源码：/Users/estai/Desktop/eq/yusal。

本轮根据用户提出的连续 ➕ 绘墙、浮动 AppBar、右侧三分类与圆角工具卡实施。以下功能、测试和产物均对应本轮实际代码；不宣称绝对最优，也未把自动测试当作真人易用性研究。

## 现在如何使用

1. 新建设计，输入宽、长；空白画布拖外形与模板入口仍可用。
2. 右侧“建造” → 底部“墙体”，拖动绿色 ➕ 创建横墙或竖墙。松手后 ➕ 留在末端，可连续拉出下一段；点空白位置更换起点，“结束”退出绘墙。
3. 独立短墙与未闭合墙段可以保存。闭合墙链自动识别房间。也可继续使用“分房 / 框房”，或输入墙长和方向。
4. 门窗从工具卡直接拖到墙上，支持跨墙搬移、点击放置与精确属性。
5. 点内墙显示三个手柄：两端改长，中间移动。底部可输入墙长、墙位置或改墙厚。带门的短墙可先选“调整 → 改墙”，避免门抢占点击。删除宿主墙时明确确认门窗移除；撤销可恢复。
6. “查看”提供恢复视角、楼层和设计检查。恢复视角分别联动 2D 画布与 3D 相机；顶部随时切换 2D/3D、保存、撤销重做。

## 实际完成

- 完整 2D 画布，顶部轻量浮条、右侧建造/调整/查看、底部 radius20 自适应工具卡；默认视口避开浮层，绘图与命中采用相同变换。
- 约 200 ms 短动效，分类切换可以打断；系统减少动态效果开启后显示静态组件。图标带文字、语义与完整提示，数字输入提供拖动替代。
- 新增独立实体墙模型 SolidWall，支持短墙、连续墙、交叉、闭合识别、端点调整与中部平移。
- 门窗跟随墙平移；缩短后无法容纳、墙段重叠、越界、穿楼梯等冲突拒绝，非法操作不落盘。
- 旧 v1 文件可读取，旧房间边界按需转换；保留房间名称、类型、标识、开放区域和宿主。新独立墙文件使用 schema v2，旧版应用不能读取 v2。未升级项目仍按 v1 保存。
- 每次完成的手势一个事务；预览不写入本地、不进入撤销历史；双指介入、切换工具或无变化编辑不会产生多余保存。连续移动清理无引用局部坐标。
- 保留楼层复制、楼梯、屋顶、2D/3D、原有分房/框房、高级绘制、门窗属性、设计检查、自动保存及 .house 导入导出。

## 需求逐项核对

| 需求 | 当前证据 |
|---|---|
| 满屏画布与三处浮层 | HouseEditor 实现；界面测试断言画布等于 SafeArea；真实 2D/3D 截图 |
| ➕ 连续绘墙、松手续画、结束 | 连续四段界面测试及 iOS 原生流程；每次松手产生一段墙 |
| 开放短墙、闭合生成房间 | 核心测试：前三段不生成新房，第四段闭合生成，移除墙重新连通 |
| 横竖约束、吸附与长度输入 | 绘墙实现；非法斜墙拒绝；数值路径、100 mm 精调、缩放平移后绘墙测试 |
| 端点改长、中部移动 | 界面手柄测试；393×852 手机短墙回归；原生 0.5 米墙移动 |
| 门窗宿主保护与楼层隔离 | 核心宿主跟随/短墙拒绝/删除确认、楼梯冲突和其他楼层保护；原生门随墙移动 |
| 旧文件与房间信息兼容 | v1 字节级 fixture、v2 编解码、旧开放区域迁移、命名房间大幅移墙、楼层复制测试 |
| 撤销、本地保存及取消恢复 | 预览写入计数、单次撤销、双指取消、分类中断、原生保存重开 |
| 小屏、横屏、大字、减少动态效果 | 320×568、844×390、文字缩放 1.8；关闭 AnimatedSize/Switcher 的测试 |
| 自评、原生验证、三平台产物 | 下列完整日志、安装启动记录、ZIP 校验与 SHA-256 清单 |

研究基础覆盖 10 款代表性产品的官方资料，来源、范围与设计取舍见 [研究与实施方案](/Users/estai/Desktop/eq/yusal/docs/UX_IMPLEMENTATION_PLAN.md)。不是全部市场产品的实际操作比较。

## 自评发现并修复

原生验证发现短墙手柄命中区重叠、中部移动被自身吸附阻挡；修复为最近手柄选择和排除正在调整的轴。布局检查修复减少动态效果下零时长动画断言、横屏大字适配。兼容检查补上开放区域保留、局部补墙分割剩余开放间隔、房间身份保持及无引用坐标清理。截图检查移除 3D 重复提示，并让查看分类的恢复按钮实际重置 3D 相机。临时预览改用随机 ID，避免与导入文件标识冲突。

## 最终验证

| 检查 | 结果 |
|---|---|
| flutter analyze | 无问题 |
| flutter test | **91 项全部通过**，含 10,000 个固定随机种子的规范化样本 |
| iOS 模拟器集成测试 | **4 条全部通过**：模板/3D/预览重开；长宽/分房/门/重开；空白外形；连续墙/宿主门/3D/v2 重开 |
| Web release | 成功；HTTP 获取最终 JS 与 build/web/main.dart.js 逐字节一致 |
| Android release APK | 成功；版本 0.3.0 / build 3，apksigner 验证通过 |
| iOS 主应用模拟器构建 | 成功；版本 0.3.0 / build 3，已安装并启动主应用 |
| ZIP 完整性、git diff --check | 通过 |

最终日志：[单元/界面](/Users/estai/Desktop/eq/yusal/docs/verification/v03/unit-widget-tests.log)、[iOS 原生](/Users/estai/Desktop/eq/yusal/docs/verification/v03/ios-integration.log)、[静态检查](/Users/estai/Desktop/eq/yusal/docs/verification/v03/analyze.log)、[Web 构建](/Users/estai/Desktop/eq/yusal/docs/verification/v03/web-build.log)、[APK 构建](/Users/estai/Desktop/eq/yusal/docs/verification/v03/android-build.log)、[iOS 构建](/Users/estai/Desktop/eq/yusal/docs/verification/v03/ios-build.log)、[Android 签名](/Users/estai/Desktop/eq/yusal/docs/verification/v03/android-signature.log)、[运行记录](/Users/estai/Desktop/eq/yusal/docs/verification/v03/runtime.json)。此前 v0.2 验证日志仍保留，当前证据集中在 v03 目录。

## 可运行产物

本机 Web：[打开应用](http://127.0.0.1:8765/)。该地址仅为本机预览服务；需重新启动时，在 build/web 运行 `python3 -m http.server 8765 --bind 127.0.0.1`。

| 产物 | 大小 | SHA-256 |
|---|---|---|
| [yusal-0.3.0-android.apk](/Users/estai/Desktop/eq/yusal/build/delivery/yusal-0.3.0-android.apk) | 52.9 MB | `9ed2a5d6d0d0ae3da24aa4a2a1df4934fc0f9de6da1fabdb54390cf8526fcae7` |
| [yusal-0.3.0-web.zip](/Users/estai/Desktop/eq/yusal/build/delivery/yusal-0.3.0-web.zip) | 12.4 MB | `bb5bf3a3a458361dfc960254c6ca2acb1cdb2581dc2aa06fd4be12fda5ba06b8` |
| [yusal-0.3.0-ios-simulator.zip](/Users/estai/Desktop/eq/yusal/build/delivery/yusal-0.3.0-ios-simulator.zip) | 52.8 MB | `5c6836ef9e6f99d8a1be7a1c2eb1e656e42f85dec843ab1be283ad3bc93c844d` |

Web ZIP 解压后使用 HTTP 服务打开；Android APK 可安装测试；iOS ZIP 内是 Runner.app，可通过 Xcode 模拟器或 `xcrun simctl install booted Runner.app` 安装。完整清单见 [manifest.json](/Users/estai/Desktop/eq/yusal/build/delivery/manifest.json)。

## 真实界面截图

截图来自 iPhone 17 Pro / iOS 26.4 模拟器中的真实 Flutter 编辑器。开发预览入口只用于展示可复现样例；最终安装包和 Web 均使用 lib/main.dart 主应用入口。

[2D 浮层](/Users/estai/Desktop/eq/yusal/docs/screenshots/editor-floating.png) · [➕ 绘墙](/Users/estai/Desktop/eq/yusal/docs/screenshots/editor-plus.png) · [3D 查看](/Users/estai/Desktop/eq/yusal/docs/screenshots/editor-floating-3d.png)。

## 尚未开展或不属于本轮功能

- 未开展青年/老年真人研究、物理 iPhone/Android 交互性能验收及真实聊天/文件应用导入分享验证，不能据模拟器声称所有人都易用。
- Android 使用 Android Debug 开发证书，应用 ID 仍为 com.example.yusal；iOS 是未签名模拟器产物，没有物理设备 IPA。应用商店发布仍需正式标识、签名与发布验收。
- 当前为矩形房屋外形和正交墙，墙长至少 0.30 米。独立墙可用数字做毫米级调整；斜墙和任意多边形外轮廓未实现。
- 原有 CustomPainter 软件投影 3D 保留；真实设备性能、深度/透明准确性和最终渲染引擎选择仍未验收。自动建筑方案生成与建筑安全认证不属于当前工具交付。

本轮 goal 的已授权实现与验证范围已逐项对应实际代码和证据；后续真实用户研究可据反馈继续改善。
