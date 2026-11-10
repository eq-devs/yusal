part of '../house_editor.dart';

/// The 2D plan page: the drawing on a sheet with zoom buttons and a legend,
/// the tool row and layer chips under it, and the card for the selection.
extension _PlanTab on _HouseEditorState {
  Widget planTab(bool wide) {
    final t = Tokens.of(context);
    final card = selectionCard();
    final surface = Sheet(
        child: Stack(key: planSheetKey, children: [
      Positioned.fill(child: planCanvas()),
      Positioned(top: 10, right: 10, child: zoomButtons()),
      if (wide || card == null || panelCollapsed)
        Positioned(left: 10, bottom: 10, right: 60, child: legend()),
      Positioned(top: 10, left: 12, right: 56, child: statusChip()),
      if (!wide && card != null)
        Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: LayoutBuilder(builder: (context, c) => card)),
      if (wallMenuCard() case final menu?) menu,
      if (loupe() case final l?) l,
    ]));
    final bars = Column(
        key: barsKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          toolRow(),
          const SizedBox(height: 6),
          // Phones: one scrolling line instead of a wrapped block, so the
          // drawing keeps the height.
          if (wide) layerRow() else fadeRow(layerChips()),
          hintRow(),
        ]);
    if (compact) {
      final t2 = Tokens.of(context);
      return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: surface),
            const SizedBox(width: 8),
            SizedBox(
                width: 184,
                child: SingleChildScrollView(
                    child: Column(
                        key: barsKey,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Row(children: [
                        IconButton(
                            tooltip: '楼层操作'.trKey('Қабат әрекеттері', 'Действия с этажом'),
                            visualDensity: VisualDensity.compact,
                            onPressed: floorOptions,
                            icon: const Icon(Icons.layers_outlined, size: 20)),
                        IconButton(
                            tooltip: '房屋长宽'.trKey('Үйдің ені мен ұзындығы', 'Ширина и длина дома'),
                            visualDensity: VisualDensity.compact,
                            onPressed: footprintOptions,
                            icon: const Icon(Icons.aspect_ratio, size: 20)),
                        IconButton(
                            tooltip: '立即保存'.trKey('Қазір сақтау', 'Сохранить сейчас'),
                            visualDensity: VisualDensity.compact,
                            onPressed: save,
                            icon: const Icon(Icons.save_outlined, size: 20)),
                        Flexible(child: saveIndicator()),
                      ]),
                      if (history.present.floors.length > 1)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Seg<int>(
                                    value: floorIndex,
                                    items: [
                                      for (var i = 0;
                                          i < history.present.floors.length;
                                          i++)
                                        (i, displayFloorName(history.present.floors[i].name))
                                    ],
                                    onChanged: selectFloor))),
                      Wrap(spacing: 6, runSpacing: 6, children: toolButtons()),
                      const SizedBox(height: 8),
                      layerRow(),
                      const SizedBox(height: 4),
                      DefaultTextStyle.merge(
                          style: TextStyle(color: t2.muted), child: hintRow()),
                    ]))),
          ]));
    }
    final plan = Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: surface),
          bars,
        ]));
    if (!wide) return plan;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: plan),
      SizedBox(
          width: 380,
          child: DecoratedBox(
              decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: t.line))),
              child: ListView(padding: const EdgeInsets.all(12), children: [
                card ?? houseCard(),
                const SizedBox(height: 10),
                if (card != null) houseCard(),
                if (card != null) const SizedBox(height: 10),
                compareCard(),
              ]))),
    ]);
  }

  /// Follow a dragging finger on a touch screen (not a mouse or pen, which
  /// do not hide what they point at).
  void trackLoupe(PointerMoveEvent e) {
    final dragging = !cancelledStroke &&
        pointers.length == 1 &&
        e.kind == PointerDeviceKind.touch &&
        (wallGesture == 'draw' ||
            wallGesture == 'edit' ||
            wallGesture == 'opening' ||
            draggingAxis != null ||
            draggingOpening != null ||
            furnitureGrip != null ||
            utilityDown != null ||
            (spatialTool && spatialStart != null));
    final moved = gestureScreen == null ||
        (e.position - gestureScreen!).distance > 8;
    final next = dragging && moved ? e.position : null;
    if (next != loupeAt) update(() => loupeAt = next);
  }

  /// A round magnifier above the finger, like the text loupe on phones and
  /// the precision cursor of mobile CAD apps: the snapped end, the length
  /// label and nearby walls stay visible under the thumb.
  Widget? loupe() {
    final at = loupeAt;
    final box = planSheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (at == null || box == null || !box.hasSize) return null;
    final local = box.globalToLocal(at);
    const size = 118.0, lift = 96.0;
    // Above the finger; beside it when the finger is near the top edge.
    var centre = local - const Offset(0, lift);
    if (centre.dy < size / 2 + 4)
      centre = local +
          Offset(local.dx > box.size.width / 2 ? -lift : lift, 0);
    centre = Offset(
        centre.dx.clamp(size / 2 + 4, math.max(size / 2 + 4, box.size.width - size / 2 - 4)),
        centre.dy.clamp(size / 2 + 4, math.max(size / 2 + 4, box.size.height - size / 2 - 4)));
    final t = Tokens.of(context);
    return Positioned(
        left: centre.dx - size / 2,
        top: centre.dy - size / 2,
        child: IgnorePointer(
            child: RawMagnifier(
                key: const ValueKey('plan-loupe'),
                size: const Size(size, size),
                magnificationScale: 2,
                focalPointOffset: local - centre,
                decoration: MagnifierDecoration(
                    shape: CircleBorder(
                        side: BorderSide(color: t.accent, width: 2)),
                    shadows: const [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 10,
                          offset: Offset(0, 3))
                    ]),
                child: Center(
                    child: Icon(Icons.add, size: 18, color: t.accent)))));
  }

  Widget zoomButtons() {
    Widget button(IconData icon, String tip, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
            width: 34,
            height: 34,
            child: Btn(label: '', icon: icon, tooltip: tip, onPressed: onTap)));
    void zoom(double factor) {
      final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
      final current = canvasTransform.value.getMaxScaleOnAxis();
      final target = (current * factor).clamp(0.4, 5.0);
      final f = target / current;
      final m = Matrix4.identity()
        ..translateByDouble(center.dx, center.dy, 0, 1)
        ..scaleByDouble(f, f, 1, 1)
        ..translateByDouble(-center.dx, -center.dy, 0, 1);
      canvasTransform.value = m..multiply(canvasTransform.value);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      button(Icons.add, tr3('放大', 'Үлкейту', 'Увеличить'), () => zoom(1.3)),
      button(Icons.remove, tr3('缩小', 'Кішірейту', 'Уменьшить'), () => zoom(1 / 1.3)),
      button(Icons.fit_screen_outlined, tr3('恢复画布视角', 'Көріністі қалпына келтіру', 'Сбросить вид'),
          () => canvasTransform.value = Matrix4.identity()),
    ]);
  }

  Widget legend() {
    final t = Tokens.of(context);
    Widget swatch(Widget mark, String text) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(width: 4),
              Text(text, style: TextStyle(fontSize: 11.5, color: t.ink))
            ]);
    Widget bar(Color c, {double h = 8, bool hatch = false}) => Container(
        width: 14,
        height: h,
        decoration: BoxDecoration(
            color: c, borderRadius: BorderRadius.circular(2)),
        child: hatch
            ? CustomPaint(painter: _HatchPainter(t.bg))
            : null);
    Widget dashed(Color c, {bool fill = false}) => Container(
        width: 14,
        height: 8,
        decoration: BoxDecoration(
            color: fill ? c.withValues(alpha: 0.22) : null,
            border: Border.all(color: c, width: 1.5),
            borderRadius: BorderRadius.circular(2)));
    final bearing = history.present.extras.foundation.bearingMin;
    return Align(
        alignment: Alignment.bottomLeft,
        child: IgnorePointer(
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: t.panel.withValues(alpha: 0.9),
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(8)),
                child: Wrap(spacing: 12, runSpacing: 4, children: [
                  swatch(bar(t.wall, hatch: true),
                      tr3('承重墙 ≥$bearing', 'Көтергіш ≥$bearing', 'Несущая ≥$bearing')),
                  swatch(bar(t.wall, h: 4), tr3('隔墙', 'Қалқа қабырға', 'Перегородка')),
                  swatch(bar(t.chk), tr3('窗', 'Терезе', 'Окно')),
                  if (showFoundation) ...[
                    swatch(dashed(t.ok),
                        '${tr3('有基础', 'Іргетасы бар', 'Есть фундамент')} ${history.present.extras.foundation.width}×${history.present.extras.foundation.height}'),
                    swatch(
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: t.chk, shape: BoxShape.circle)),
                        tr3('预留套管', 'Гильза', 'Гильза')),
                    swatch(dashed(t.crit, fill: true),
                        tr3('缺基础', 'Іргетасы жоқ', 'Нет фундамента')),
                  ],
                ]))));
  }

  Widget toolRow() => fadeRow(toolButtons());

  /// A horizontally scrolling line whose right edge fades out while more
  /// is hidden there, so the cut-off tools read as "swipe for more".
  Widget fadeRow(List<Widget> children) => FadeRow(children: children);

  /// Every plan tool with a key; the phone row shows the common ones.
  /// Phones get six tools in the row, like the four-to-six modes of
  /// RoomSketcher, magicplan and Planner 5D; the rest sit in "更多工具".
  bool get phoneTools => !compact && MediaQuery.sizeOf(context).width < 600;

  static const secondaryTools = {
    'split': ['split'],
    'box': ['box'],
    'utility': ['placeUtility'],
    'selectWall': ['selectWall', 'editWall'],
    'resize': ['resize'],
  };

  List<Widget> toolButtons() => [
        for (final (key, widget) in keyedTools())
          if (!phoneTools ||
              !secondaryTools.containsKey(key) ||
              secondaryTools[key]!.contains(tool))
            widget
      ];

  /// The tools the phone row leaves out, for the "更多工具" sheet.
  List<Widget> secondaryToolButtons() => [
        for (final (key, widget) in keyedTools())
          if (secondaryTools.containsKey(key)) widget
      ];

  List<(String, Widget)> keyedTools() {
    return [
      ('browse', basicTool(Icons.pan_tool_outlined, tr3('浏览', 'Шолу', 'Просмотр'), browse, () {
        tool = 'browse';
        browse = true;
      })),
      ('wall', basicTool(Icons.add_outlined, '墙体', tool == 'drawWall', startWallDrawing)),
      if (tool == 'drawWall')
        ('freeWall', basicTool(Icons.add_box_outlined, '独立墙', placingWallStart, () {
          drawingOrigin = null;
          placingWallStart = true;
          placementHint = tr3('在空白处拖出独立墙，或点一下选起点',
              'Бос жерден қабырға тартыңыз немесе бастауды басыңыз', 'Протяните стену на свободном месте или нажмите, чтобы задать начало');
        })),
      ('split', basicTool(Icons.vertical_split_outlined, '拉线分房', tool == 'split', () {
        view3d = false;
        browse = false;
        tool = 'split';
      })),
      ('box', basicTool(Icons.crop_square, '拖动划房', tool == 'box', () {
        view3d = false;
        browse = false;
        tool = 'box';
        brush = RoomType.custom;
      })),
      ('door', openingTool(OpeningKind.door, Icons.door_front_door_outlined, '拖入门')),
      ('window', openingTool(OpeningKind.window, Icons.window_outlined, '拖入窗')),
      ('furniture', basicTool(Icons.chair_outlined, '家具', tool == 'placeFurniture',
          chooseFurniture)),
      ('utility', basicTool(Icons.electrical_services_outlined, '水电',
          tool == 'placeUtility', chooseUtility)),
      ('selectWall', basicTool(Icons.view_week_outlined, '墙体调整',
          tool == 'selectWall' || tool == 'editWall', () {
        view3d = false;
        tool = 'selectWall';
        browse = false;
      })),
      ('resize', basicTool(Icons.open_in_full, '房屋尺寸', tool == 'resize', () {
        view3d = false;
        browse = false;
        tool = 'resize';
      })),
      ('more', basicTool(Icons.more_horiz, '更多工具', false, moreTools)),
    ];
  }

  Widget layerRow() =>
      Wrap(spacing: 8, runSpacing: 6, children: layerChips());

  List<Widget> layerChips() => [
        PillToggle(
            label: tr3('家具', 'Жиһаз', 'Мебель'),
            selected: showFurniture,
            onChanged: (v) => update(() => showFurniture = v)),
        PillToggle(
            label: tr3('尺寸', 'Өлшемдер', 'Размеры'),
            selected: showDimensions,
            onChanged: (v) => update(() => showDimensions = v)),
        PillToggle(
            label: tr3('水电', 'Су-электр', 'Электрика и вода'),
            selected: showUtilities,
            onChanged: (v) => update(() {
                  showUtilities = v;
                  if (!v) {
                    selectedUtilityId = null;
                    if (tool == 'placeUtility') {
                      tool = 'browse';
                      browse = true;
                      placementHint = null;
                    }
                  }
                })),
        PillToggle(
            label: tr3('地基', 'Іргетас', 'Фундамент'),
            selected: showFoundation,
            onChanged: (v) => update(() {
                  showFoundation = v;
                  if (v && floorIndex != 0) {
                    floorIndex = 0;
                    derive();
                  }
                })),
        PillToggle(
            label: tr3('测距', 'Қашықтық өлшеу', 'Измерить расстояние'),
            icon: Icons.straighten,
            checkbox: false,
            selected: tool == 'measure',
            onChanged: (v) => update(() {
                  cancelDrag();
                  clearWallSelection();
                  measurePoints = [];
                  tool = v ? 'measure' : 'browse';
                  browse = !v;
                  placementHint = null;
                })),
      ];

  Widget hintRow() {
    final t = Tokens.of(context);
    final coach = !view3d && coachText != null && placementHint == null;
    final children = hintChildren(t, coach);
    if (compact)
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in children)
              if (c is Expanded) c.child else c
          ]);
    return Padding(
        padding: const EdgeInsets.only(top: 6), child: Row(children: children));
  }

  List<Widget> hintChildren(Tokens t, bool coach) {
    return [
          if (coach) ...[
            Icon(Icons.touch_app_outlined, size: 18, color: t.accent),
            const SizedBox(width: 6),
          ],
          Expanded(
              child: Text(coach ? coachText! : interactionHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: coach ? 13 : 12,
                      fontWeight: coach ? FontWeight.w600 : FontWeight.w400,
                      color: coach ? t.accent : t.muted))),
          if (tool == 'resize')
            TextButton.icon(
                onPressed: footprintOptions,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(tr3('输入长宽', 'Өлшем енгізу', 'Ввести размеры'))),
          if (tool == 'drawWall')
            IconButton(
                tooltip: '输入墙长',
                onPressed: drawingOrigin == null ? null : addWallByLength,
                icon: const Icon(Icons.straighten, size: 18)),
          if (tool == 'drawWall' ||
              tool == 'placeFurniture' ||
              tool == 'placeUtility' ||
              tool == 'measure')
            TextButton(
                onPressed: () => update(() {
                      cancelDrag();
                      tool = 'browse';
                      browse = true;
                      drawingOrigin = null;
                      drawingEnd = null;
                      placementHint = null;
                      placingFurniture = null;
                      placingUtility = null;
                      measurePoints = [];
                    }),
                child: Text(tr3('结束', 'Аяқтау', 'Завершить'))),
        ];
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.clipRect(Offset.zero & size);
    for (var d = -size.height; d < size.width; d += 4)
      canvas.drawLine(Offset(d, size.height), Offset(d + size.height, 0), p);
  }

  @override
  bool shouldRepaint(covariant _HatchPainter old) => old.color != color;
}

/// A horizontally scrolling line whose right edge fades out while more is
/// hidden there, so cut-off tools read as "swipe for more".
class FadeRow extends StatefulWidget {
  const FadeRow({super.key, required this.children});
  final List<Widget> children;
  @override
  State<FadeRow> createState() => _FadeRowState();
}

class _FadeRowState extends State<FadeRow> {
  final controller = ScrollController();
  bool more = false;

  void check() {
    if (!controller.hasClients) return;
    final p = controller.position;
    final next = p.pixels < p.maxScrollExtent - 4;
    if (next != more) setState(() => more = next);
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(check);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) check();
    });
    final row = SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final w in widget.children)
            Padding(padding: const EdgeInsets.only(right: 6), child: w)
        ]));
    if (!more) return row;
    return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.86, 1])
            .createShader(r),
        child: row);
  }
}
