# 自建房设计工具 v0.4 交付报告

版本 **0.4.0+4**；日期 2026-10-01；源码 /Users/estai/Desktop/eq/yusal。本轮直接响应“➕ 应固定在墙的可扩展位置、长按呼出修改”的实际反馈。前一版实现和证据保存在 DELIVERY_REPORT_v03.md，本报告对应新版最终代码与产物。

## 建墙交互重做

- 进入“墙体”或“调整 → 改墙”，看到固定在墙端、交接点和可接墙中段的 ➕。从接点拖动，松手建立墙段，末端可连续绘制。
- 普通空白点击不移动 ➕ 或新建墙。单独起墙先点“独立墙”，再拖出墙或点选明确起点；选定起点后可输入长度和方向。
- 墙中其他位置可点选为接墙起点；无可扩展正交方向的占满墙角和门窗孔洞不展示误导性接点。
- 接点按屏幕距离筛选，避免密集挤在一起，放大能看到更多。图标和命中范围保持屏幕尺寸，操作区域避开浮层。
- 改墙模式点击选择修改，拖动接点新建墙；建立新墙需要超过 8 屏幕像素的拖动，降低轻触误操作。
- 长按墙体 500 ms 呼出上下文菜单，显示所选墙长和高亮手柄。内墙提供从此接墙、长度、位置、墙厚、删除；外墙提供接墙和房屋长宽修改。
- 菜单中的改墙厚直接输入，省去再次选择菜单。点击内墙仍可使用底部手柄与数字操作，长按不是唯一编辑入口。
- 移动手指、多指、取消、离开页面会取消长按；打开菜单不保存、不进入历史。已有门窗位置禁用从此接墙，核心也拒绝新分支穿过门窗孔洞。

继承 v0.3 的开放短墙、闭合房间识别、分房/框房、门窗拖放与宿主联动、其他楼层保护、2D/3D、屋顶楼梯、撤销、自动保存和 .house 导入导出。文件模型仍为 schema v2，可读取 v1；v0.3 可读相同 v2 格式，仅支持 v1 的 v0.2 及更早应用不能读取 v2。

## 研究、分析与自评

本轮核对 Live Home 3D 的 iOS 绘墙与手势指南、RoomSketcher 精确墙长、Sweet Home 3D 用户指南。在此前 10 款代表性产品资料基础上，重新评估固定接点、拖动/点击/长按的分工。来源、设计判断和范围见 [研究与实施记录](/Users/estai/Desktop/eq/yusal/docs/UX_IMPLEMENTATION_PLAN.md)。没有声称实际操作全部市场产品，固定 ➕ 的具体组合是本产品的设计选择。

自评及实测修复：浮层吞掉外墙接点触摸、工具过多导致小屏拥挤、改墙接点点击与拖动混淆、缩放时接点大小和命中不一致、取消时残留新起点、门窗位置被新分支穿过，以及菜单尺寸与实际选中墙段不一致。

## 逐项验收

| 需求 | 实际证据 |
|---|---|
| 默认固定接点，空白点击不搬移 | 界面测试断言初始无游动 seed、空白点击不写入、不改变接点；真实截图 |
| 从墙接出、松手创建、连续扩展 | 外墙接点 → 独立墙段 → 转向续画的界面和原生测试 |
| 改墙模式可接墙且点击仍能修改 | 手机尺寸回归、改墙模式测试及原生门窗所在短墙流程 |
| 长按菜单及点击替代 | 菜单可见、手柄选中、直接改厚测试；原生长按改长度、保存重开 |
| 独立起墙与数字替代 | 显式按钮、数值建墙、连续四墙闭合及撤销测试 |
| 缩放、多指、取消、冲突恢复 | 变换坐标、双指、分类中断、移动取消长按、门窗穿越拒绝与存储写入计数 |
| 小屏、横屏、大字与动态效果 | 320×568、844×390、393×852、文字缩放 1.8、减少动态效果回归 |
| 旧文件及既有功能 | v1 fixture、v2 编解码、开放区域、房间身份、门窗、楼层、楼梯、3D 和存储测试 |

## 最终验证结果

- **98 项单元/界面测试全部通过**，包含 10,000 个固定随机种子的规范化样本。
- **5 条 iOS 模拟器原生流程全部通过**；新增固定接点、空白不移位、连续接墙、长按修改、保存重开。
- flutter analyze 无问题，git diff --check 通过。
- 验证期间一次磁盘空间耗尽导致编译中断；清理本项目旧编译缓存后，完整 98 项重跑成功。[中断记录](/Users/estai/Desktop/eq/yusal/docs/verification/v04/interrupted-disk-space.log)、[缓存处理记录](/Users/estai/Desktop/eq/yusal/docs/verification/v04/cache-cleanup.json)均保留。
- Web release、Android release APK、iOS 主应用模拟器构建全部成功。
- APK 签名验证通过，版本 0.4.0 / build 4；最终 iOS 主应用已安装启动。
- 本机 HTTP 获取的 JS 与最终 build/web/main.dart.js 逐字节一致；两个 ZIP 完整性检查通过。

证据：[完整测试](/Users/estai/Desktop/eq/yusal/docs/verification/v04/unit-widget-tests.log)、[原生流程](/Users/estai/Desktop/eq/yusal/docs/verification/v04/ios-integration.log)、[静态检查](/Users/estai/Desktop/eq/yusal/docs/verification/v04/analyze.log)、[Web 构建](/Users/estai/Desktop/eq/yusal/docs/verification/v04/web-build.log)、[Android 构建](/Users/estai/Desktop/eq/yusal/docs/verification/v04/android-build.log)、[iOS 构建](/Users/estai/Desktop/eq/yusal/docs/verification/v04/ios-build.log)、[签名](/Users/estai/Desktop/eq/yusal/docs/verification/v04/android-signature.log)、[原生启动](/Users/estai/Desktop/eq/yusal/docs/verification/v04/ios-launch.log)、[Web 服务核对](/Users/estai/Desktop/eq/yusal/docs/verification/v04/web-runtime.json)。

## 可运行产物

[打开本机 Web](http://127.0.0.1:8765/)。重新启动服务可在 build/web 运行 `python3 -m http.server 8765 --bind 127.0.0.1`。Web ZIP 解压后使用 HTTP 服务；APK 可安装测试；iOS ZIP 中是模拟器 Runner.app，可用 `xcrun simctl install booted Runner.app` 安装。

| 产物 | 大小 | SHA-256 |
|---|---|---|
| [yusal-0.4.0-android.apk](/Users/estai/Desktop/eq/yusal/build/delivery/yusal-0.4.0-android.apk) | 53.0 MB | `8c6d367e2531798befb590903ac713df6f7480be26b8bf0bb5c0d49737f66ad9` |
| [yusal-0.4.0-web.zip](/Users/estai/Desktop/eq/yusal/build/delivery/yusal-0.4.0-web.zip) | 12.4 MB | `244a7c10add3de70648728ddc75ba576867c0e06950aa15e8327549ec9ad7421` |
| [yusal-0.4.0-ios-simulator.zip](/Users/estai/Desktop/eq/yusal/build/delivery/yusal-0.4.0-ios-simulator.zip) | 52.9 MB | `2a294372c50562be2ef1c6ce483e195ba26a8512a1b3a4a55894dd2ffee01c6c` |

[完整校验清单](/Users/estai/Desktop/eq/yusal/build/delivery/manifest.json)。最终产物使用 lib/main.dart 主应用，截图使用真实编辑器组件和可复现样例的开发预览入口。

## 真实截图

[固定接墙点](/Users/estai/Desktop/eq/yusal/docs/screenshots/wall-attachments-v04.png) · [墙体上下文菜单](/Users/estai/Desktop/eq/yusal/docs/screenshots/wall-context-v04.png)。来自 iPhone 17 Pro / iOS 26.4 模拟器，已查看实际截图并检查布局。

## 尚未完成或未验证的范围

真人老年/青年易用性研究、物理 iPhone/Android 性能与真实文件应用导入分享未开展。Web 此次验证构建和 HTTP 内容，Android 验证构建/版本/签名，不能等同于两端真机手势验收。APK 仍用 Android Debug 开发签名、com.example.yusal 标识，iOS 仅模拟器产物，不是商店发布包。

仍支持矩形外形、正交墙和至少 0.30 米墙长。修改一段墙不会自动移动所有相连墙，需核对预览和闭合状态；斜墙、任意外轮廓及连接墙约束系统未实现。保留原 CustomPainter 软件投影 3D，其真机性能、深度和透明准确性未认证。不声称本轮已达到绝对完美。
