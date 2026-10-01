# 自建房设计工具 v0.2 交付报告

交付日期：2026-10-01（Asia/Almaty）。版本：0.2.0+2。源码：/Users/estai/Desktop/eq/yusal。

## 已交付的主流程

新建设计 → 输入宽、长，或空白画布拖出外形 → 拉线分房 / 框出小房间 → 把门窗拖到墙上 → 调整尺寸 → 2D / 3D 核对 → 自动保存、重开。

- 模板成为可选入口。新设计无需预设网格，默认完整房屋空间可直接分割。
- 分房作用于当前空间；角落框房保留 L 形剩余空间。预览显示实际墙体与尺寸，非法位置显示原因。
- 新门窗拖入自动贴墙；已有门窗能跨墙拖动。支持点击放置与数字属性作为替代操作。
- 拖外框或输入长宽调整房屋；内墙可用手柄或精确位置调整，只改变相邻空间并保护其他楼层。
- 常用工具精简为浏览、分房、框房、门、窗、更多。房间可直接改用途、命名、合并。
- 保留楼层、楼梯、屋顶、2D/3D、设计检查、撤销重做、本地保存、.house 导入导出与 v1 文件格式。

## 研究与自评

研究覆盖 10 款代表性产品的官方文档与教程。证据、选择依据和范围见 [研究与实施方案](/Users/estai/Desktop/eq/yusal/docs/UX_IMPLEMENTATION_PLAN.md)。没有声称操作过全部市场产品，也没有把自动测试等同于真人可用性研究。

代码自评检查了预览与提交隔离、失败回滚、门窗宿主保护、坐标变换、楼层作用范围、保存与单次撤销。实际修复：门固定到墙角、无效拖放提交旧预览、门转窗高度、门朝向、异步 setState、合并门窗冲突、缩放后的落点、外框拖动时画布漂移，以及小屏工具标签截断。模拟器视觉检查还修正辅助格线、旧首页引导和 3D 重复提示。

## 最终验证

| 验证 | 实际结果 |
|---|---|
| flutter analyze | 无问题 |
| flutter test | 65 项全部通过；其中含 10,000 个固定随机种子的规范化样本 |
| iOS 模拟器集成测试 | 3 条全部通过：模板及原生预览重开；长宽、分房、门、3D、保存重开；空白画布精确外形 |
| 布局与异常流程 | 小屏 320×568、横屏 844×390、文字缩放 1.8、缩放平移后拖放、双指取消、无效落点取消、局部墙及其他楼层保护 |
| Web release 构建 | 成功；本机 HTTP 服务已返回最终页面 |
| Android release APK | 成功；apksigner 验证通过，使用 Android Debug 开发证书 |
| iOS 主应用模拟器构建 | 成功，已安装并启动 |
| git diff --check | 通过 |

[完整验证日志](/Users/estai/Desktop/eq/yusal/docs/verification/unit-widget-tests.log)、[原生集成日志](/Users/estai/Desktop/eq/yusal/docs/verification/ios-integration.log)、[静态检查](/Users/estai/Desktop/eq/yusal/docs/verification/analyze.log)。构建与签名日志也保存在 docs/verification。

## 使用与产物

本机浏览器：[打开应用](http://127.0.0.1:8765/)。这是本机预览服务。重新启动可在 build/web 中运行 `python3 -m http.server 8765 --bind 127.0.0.1`，保持相同端口使用同一浏览器的本地项目。

Android 包可用于设备安装验证；iOS 压缩包是模拟器 .app，不是物理 iPhone 的 IPA。Web ZIP 解压后通过 HTTP 服务打开。以下校验值对应最终打包文件。

| 产物 | 大小 | SHA-256 |
|---|---|---|
| [app-release.apk](/Users/estai/Desktop/eq/yusal/build/app/outputs/flutter-apk/app-release.apk) | 52.6 MB | `539e09b325dc496bf54c5ded18dfa97d1b9c16ea4d6b3cf65ab97c8ff13c267f` |
| [yusal-0.2.0-web.zip](/Users/estai/Desktop/eq/yusal/build/delivery/yusal-0.2.0-web.zip) | 12.4 MB | `286660d6ad5e6185e447312717980ee672a6caf8ee563f09215c37592a3c0f73` |
| [yusal-0.2.0-ios-simulator.zip](/Users/estai/Desktop/eq/yusal/build/delivery/yusal-0.2.0-ios-simulator.zip) | 52.8 MB | `cffc7204c602d435dd80d2dd2a502778faf5e3d964df1a9558198cd7a05dc9f2` |

首次使用建议：12×10 米 → 分房拉一条竖线 → 框房划出角落卫生间 → 将门、窗拖到墙上 → 点击房间更改用途 → 切换 3D。每次松手只提交一次；取消或双指介入不保存临时预览。

截图：[最终首页](/Users/estai/Desktop/eq/yusal/docs/screenshots/home.png)、[实际 2D 编辑](/Users/estai/Desktop/eq/yusal/docs/screenshots/editor-2d.png)、[实际 3D 检查](/Users/estai/Desktop/eq/yusal/docs/screenshots/editor-3d.png)。编辑截图来自本次自评演示，3D 截图拍摄后已移除其底部重复的 2D 提示。演示入口 tool/ux_preview.dart 使用真实编辑器，不是静态设计图。

## 产品范围与尚未验证事项

当前是完成本次直接操作改版、可运行的 MVP。采用矩形外轮廓与正交墙体；斜墙、L 形外轮廓及自动建筑方案生成尚未实现。现有轴间距最少 300 mm：与其他墙共享坐标的局部墙移动可能需要至少 0.30 米，独立局部墙可以更细调整。

尚未进行青年/老年真人可用性研究、物理 iOS/Android 设备验收，以及真实聊天/文件应用的分享打开验收。3D 保留现有软件投影方案，深度、透明与大模型性能未做完整专项认证。Android 目前是开发签名，iOS 为模拟器构建，应用标识仍是 com.example.yusal；尚未完成应用商店发布配置。不能据此称为绝对完美或已通过商店上线验收。

已安排本聊天 2026-10-01 当地 09:00 的单次早间交付检查，报告实际进度。
