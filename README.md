# Yusal · 自建房设计工具

Flutter house planning app for web, iOS and Android. Dimensions are integer millimeters in `.house` files; the editor displays meters.

## Implemented workflows

- Direct length/width creation, blank-canvas footprint sketching and optional starter templates.
- Local line partitions, rectangle room carving (including L-shaped remaining spaces), wall handles, types, naming, merging with hosted-object resolution and undo/redo.
- Direct door/window drag-and-drop, wall snapping, cross-wall relocation and click-to-place alternatives.
- Advanced room painting and erasing remain available under More tools.
- Global/per-floor grids, precise movement, promotion and deletion with conflict choices.
- Doors, windows, sliding doors, positioning, sizing, hinges and main entrance.
- Wall opening/thickness overrides; floors, floor copies, heights and deletion.
- Straight, L and U stairs; flat/gable roofs; configurable creation defaults.
- Net dimensions/areas, 2D plans, orbitable 3D previews and linked picking.
- R01–R10 design checks with highlighted locations.
- Local projects, atomic saves, autosave, recovery index, WebP thumbnails, damaged-file entries, import/export and native `.house` opening.

## Run

```sh
flutter pub get
flutter run -d chrome
```

Use `flutter devices` to choose an iOS simulator or Android device, then `flutter run -d <device-id>`.

## Verify

```sh
flutter analyze
flutter test
flutter test integration_test/app_test.dart -d <ios-simulator-id>
flutter build web --release
flutter build apk --release
flutter build ios --simulator --no-codesign
```

The unit/widget suite includes 10,000 seeded canonicalization cases, byte-for-byte fixtures, commands, all templates, storage failures, small-screen layouts and autosave/undo. The iOS integration workflows exercise templates, direct dimensions, local partitions, door drops, blank-canvas footprint sketching, continuous independent walls, hosted-door movement, 3D, native WebP generation and v2 reopening.

## Structure

- `lib/core/`: pure Dart documents, codec, validation, axes, canonicalization, commands, history, geometry and checks.
- `lib/features/`: project home and interactive editor.
- `lib/render2d/`, `lib/render3d/`: render derived geometry.
- `lib/storage/`: platform filesystem boundary, index and project persistence.
- `android/`, `ios/`: native bounded file-import handlers and document registration.

## Acceptance status

This is a runnable implementation candidate. Full acceptance of every matrix in the development specification has not been certified. The current 3D renderer uses software projection with CustomPainter; final engine selection, depth/transparency accuracy, performance and physical-device acceptance remain open. Storage failures currently use exceptions internally, and index listing rebuilds from source files. Grid lines and doors/windows support reversible drag previews, alongside precise property dialogs. Sharing/opening must still be tested in the target users' real chat/file apps on physical iOS/Android devices.

See `IMPLEMENTATION_PLAN.md` for implementation progress and remaining conformance work.


## v0.4 使用流程

1. 新建设计，输入宽（左右）与长（上下）；也可在空白画布拖出矩形外形，模板可选。
2. 右侧选择“建造”，底部点“墙体”。从墙上固定的绿色 ➕ 拖出横墙或竖墙，松手后末端可继续画墙；普通空白点击不移动起点。要单独起墙，先点“独立墙”再拖动或选择位置；完成后点“结束”。选定起点后也可输入墙长与方向。
3. 未闭合短墙直接保留，闭合墙链自动识别房间。“分房 / 框房”仍适合快速切分完整空间。
4. 把门窗从工具卡拖到墙上。已有门窗可跨墙移动；墙移动时其门窗一起移动，无法容纳时拒绝修改。
5. 长按墙体呼出接墙、长度、位置、墙厚和删除操作；外墙提供房屋长宽修改。点内墙也可直接出现手柄：拖两端改长度、拖中间移动，也可输入墙长、墙位置。带门窗的短墙可先点“调整 → 改墙”再选墙。删除宿主墙需确认。
6. “查看”包含视角恢复、楼层操作与设计检查；顶部随时切换 2D / 3D、撤销重做或保存。底部 radius20 浮层卡随类别与选中对象变化，系统减少动态效果开启后不播放切换动画。

### v0.5 交互更新

- 墙体模式手势固定：**拖 ＋ 建墙；点墙（含墙上的 ＋）选中墙；拖选中墙的两端改长度、拖墙身移动；拖空白处平移；双指缩放**。按住 ＋ 再拖仍是建墙。
- 建墙时末端靠近墙会自动接上并画圆环，顶部状态条显示“竖墙 6.00 米 · 已连到墙 / 末端没连墙 / 不能穿过门窗”等；拖出房屋会停在外墙上。
- 选中墙后，菜单出现在墙旁边：接墙、长度、位置、墙厚（12/18/24/37 墙快捷选择）、删除。侧移墙体时，端点落在这面墙上的墙会一起伸缩；会把它们压到 0.30 米以下时拒绝并说明。
- 门窗在任意墙体工具中都能直接拖动；从工具卡拖出时，图标浮在手指上方，箭头尖就是落点。
- 调整 → 房屋尺寸直接显示双向箭头手柄，也可点“输入长宽”。
- 删除、放置、撤销、重做和保存失败都有提示；保存失败每 5 秒自动重试。刷新页面或重启后回到正在编辑的设计。
- 键盘：Esc 逐级退出，Ctrl/⌘+Z 撤销，Ctrl/⌘+Shift+Z 或 Ctrl+Y 重做，Delete 删除选中墙。鼠标悬停时光标提示可拖、可点的位置。

改动过程、浏览器检查与剩余问题见 [v0.5 优化记录](docs/OPTIMIZATION_LOG_v05.md)。

### 文件兼容

旧 v1 `.house` 文件仍可读取；未使用独立墙体的项目继续按 v1 保存。首次绘制或直接调整内墙时，该楼层转换为独立墙段，文件使用 schema v2。保留旧房间名称、类型、开放区域及门窗宿主，转换可随操作撤销。仅支持 v1 的旧版应用不能读取 v2 文件，请使用新版打开和导出。

独立墙段至少 0.30 米，精确坐标以整数毫米保存。当前支持矩形外形和正交墙，斜墙、任意外轮廓不在本轮交付范围。手机上的吸附以屏幕距离计算，细微调整可使用数字输入。

研究、取舍、证据范围与代码自评见 [UX_IMPLEMENTATION_PLAN.md](docs/UX_IMPLEMENTATION_PLAN.md)。最终验证及构建记录见 [DELIVERY_REPORT.md](docs/DELIVERY_REPORT.md)。
