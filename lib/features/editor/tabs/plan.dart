part of '../page.dart';

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
            // Rises in for each new selection, with the click of a choice.
            child: RiseIn(
                key: ValueKey(selectionIdentity),
                haptic: true,
                child: LayoutBuilder(builder: (context, c) => card))),
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
                            tooltip: '楼层操作'
                                .trKey('Қабат әрекеттері', 'Действия с этажом', 'Floor actions', 'Кабат боюнча аракеттер', 'Qavat amallari'),
                            visualDensity: VisualDensity.compact,
                            onPressed: floorOptions,
                            icon: const Icon(Icons.layers_outlined, size: 20)),
                        IconButton(
                            tooltip: '房屋长宽'.trKey('Үйдің ені мен ұзындығы',
                                'Ширина и длина дома',
                                'House width and length', 'Үйдүн туурасы жана узундугу', 'Uy eni va uzunligi'),
                            visualDensity: VisualDensity.compact,
                            onPressed: footprintOptions,
                            icon: const Icon(Icons.aspect_ratio, size: 20)),
                        IconButton(
                            tooltip: '立即保存'
                                .trKey('Қазір сақтау', 'Сохранить сейчас', 'Save now', 'Азыр сактоо', 'Hozir saqlash'),
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
                                        (
                                          i,
                                          displayFloorName(
                                              history.present.floors[i].name)
                                        )
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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
    final moved =
        gestureScreen == null || (e.position - gestureScreen!).distance > 8;
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
    const size = 118.0;
    const lift = 96.0;
    // Above the finger; beside it when the finger is near the top edge.
    var centre = local - const Offset(0, lift);
    if (centre.dy < size / 2 + 4) {
      centre = local + Offset(local.dx > box.size.width / 2 ? -lift : lift, 0);
    }
    centre = Offset(
        centre.dx.clamp(size / 2 + 4,
            math.max(size / 2 + 4, box.size.width - size / 2 - 4)),
        centre.dy.clamp(size / 2 + 4,
            math.max(size / 2 + 4, box.size.height - size / 2 - 4)));
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
      button(Icons.add, tr3('放大', 'Үлкейту', 'Увеличить', 'Zoom in', ky: 'Чоңойтуу', uz: 'Kattalashtirish'), () => zoom(1.3)),
      button(Icons.remove, tr3('缩小', 'Кішірейту', 'Уменьшить', 'Zoom out', ky: 'Кичирейтүү', uz: 'Kichiklashtirish'),
          () => zoom(1 / 1.3)),
      button(
          Icons.fit_screen_outlined,
          tr3('恢复画布视角', 'Көріністі қалпына келтіру', 'Сбросить вид', 'Reset view', ky: 'Көрүнүштү баштапкы абалга келтирүү', uz: 'Koʻrinishni asliga qaytarish'),
          () => canvasTransform.value = Matrix4.identity()),
    ]);
  }

  Widget legend() {
    final t = Tokens.of(context);
    Widget swatch(Widget mark, String text) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          mark,
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11.5, color: t.ink))
        ]);
    Widget bar(Color c, {double h = 8, bool hatch = false}) => Container(
        width: 14,
        height: h,
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        child: hatch ? CustomPaint(painter: _HatchPainter(t.bg)) : null);
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: t.panel.withValues(alpha: 0.9),
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(8)),
                child: Wrap(spacing: 12, runSpacing: 4, children: [
                  swatch(
                      bar(t.wall, hatch: true),
                      tr3('承重墙 ≥$bearing', 'Көтергіш ≥$bearing',
                          'Несущая ≥$bearing',
                          'Load-bearing ≥$bearing', ky: 'Көтөрүүчү ≥$bearing', uz: 'Yuk koʻtaruvchi ≥$bearing')),
                  swatch(bar(t.wall, h: 4),
                      tr3('隔墙', 'Қалқа қабырға', 'Перегородка', 'Partition', ky: 'Тосмо', uz: 'Toʻsiq')),
                  swatch(bar(t.chk), tr3('窗', 'Терезе', 'Окно', 'Window', ky: 'Терезе', uz: 'Deraza')),
                  if (showFoundation) ...[
                    swatch(dashed(t.ok),
                        '${tr3('有基础', 'Іргетасы бар', 'Есть фундамент', 'Has a foundation', ky: 'Пайдубалы бар', uz: 'Poydevori bor')} ${history.present.extras.foundation.width}×${history.present.extras.foundation.height}'),
                    swatch(
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: t.chk, shape: BoxShape.circle)),
                        tr3('预留套管', 'Гильза', 'Гильза', 'Sleeve', ky: 'Гильза', uz: 'Gilza')),
                    swatch(dashed(t.crit, fill: true),
                        tr3('缺基础', 'Іргетасы жоқ', 'Нет фундамента', 'No foundation', ky: 'Пайдубалы жок', uz: 'Poydevori yoʻq')),
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
    'split': [EditorTool.split],
    'box': [EditorTool.box],
    'utility': [EditorTool.placeUtility],
    'selectWall': [EditorTool.selectWall, EditorTool.editWall],
    'resize': [EditorTool.resize],
  };

  List<Widget> toolButtons() => [
        for (final (key, widget) in keyedTools())
          // A room or stair being slid into place is the box tool
          // underneath; its button stays in the sheet meanwhile.
          if (!phoneTools ||
              !secondaryTools.containsKey(key) ||
              (secondaryTools[key]!.contains(tool) &&
                  !(key == 'box' && stamping)))
            widget
      ];

  /// The tools the phone row leaves out, for the "更多工具" sheet.
  List<Widget> secondaryToolButtons() => [
        for (final (key, widget) in keyedTools())
          if (secondaryTools.containsKey(key)) widget
      ];

  List<(String, Widget)> keyedTools() {
    return [
      (
        'browse',
        basicTool(
            Icons.pan_tool_outlined, tr3('浏览', 'Шолу', 'Просмотр', 'View', ky: 'Көрүнүш', uz: 'Koʻrinish'), browse, () {
          tool = EditorTool.browse;
        })
      ),
      // A room with a use and a size, slid into place: the way most
      // people think of a house, so it comes before drawing walls.
      (
        'room',
        basicTool(Icons.add_home_outlined, '加房间', stamping && !stampStair,
            addRoomBySize)
      ),
      (
        'wall',
        basicTool(Icons.add_outlined, '墙体', tool == EditorTool.drawWall,
            startWallDrawing)
      ),
      if (tool == EditorTool.drawWall)
        (
          'freeWall',
          basicTool(Icons.add_box_outlined, '独立墙', placingWallStart, () {
            drawingOrigin = null;
            placingWallStart = true;
            placementHint = tr3(
                '在空白处拖出独立墙，或点一下选起点',
                'Бос жерден қабырға тартыңыз немесе бастауды басыңыз',
                'Протяните стену на свободном месте или нажмите, чтобы задать начало',
                'Drag a wall in empty space, or tap to set its start', ky: 'Бош жерде дубал сүйрөңүз же башталышын коюу үчүн басыңыз', uz: 'Boʻsh joyda devor chizing yoki boshlanishini belgilash uchun bosing');
          })
        ),
      (
        'split',
        basicTool(
            Icons.vertical_split_outlined, '拉线分房', tool == EditorTool.split,
            () => toolBody('split'))
      ),
      (
        'box',
        basicTool(
            Icons.crop_square, '拖动划房', tool == EditorTool.box && !stamping, () => toolBody('box'))
      ),
      (
        'door',
        openingTool(OpeningKind.door, Icons.door_front_door_outlined, '拖入门')
      ),
      ('window', openingTool(OpeningKind.window, Icons.window_outlined, '拖入窗')),
      (
        'furniture',
        basicTool(Icons.chair_outlined, '家具', tool == EditorTool.placeFurniture,
            chooseFurniture)
      ),
      (
        'utility',
        basicTool(Icons.electrical_services_outlined, '水电',
            tool == EditorTool.placeUtility, chooseUtility)
      ),
      (
        'selectWall',
        basicTool(Icons.view_week_outlined, '墙体调整',
            tool == EditorTool.selectWall || tool == EditorTool.editWall, () => toolBody('selectWall'))
      ),
      (
        'resize',
        basicTool(Icons.open_in_full, '房屋尺寸', tool == EditorTool.resize, () => toolBody('resize'))
      ),
      ('more', basicTool(Icons.more_horiz, '更多工具', false, moreTools)),
    ];
  }

  /// What taking up a tool does, for the tools that are one step.
  void toolBody(String key) {
    switch (key) {
      case 'split':
        view3d = false;
        tool = EditorTool.split;
      case 'box':
        view3d = false;
        tool = EditorTool.box;
        roomStamp = null;
        brush = RoomType.custom;
      case 'selectWall':
        view3d = false;
        tool = EditorTool.selectWall;
      case 'resize':
        view3d = false;
        tool = EditorTool.resize;
      case 'room':
        addRoomBySize();
      case 'wall':
        startWallDrawing();
      case 'door':
        startOpening(OpeningKind.door);
      case 'window':
        startOpening(OpeningKind.window);
      case 'furniture':
        chooseFurniture();
      case 'utility':
        chooseUtility();
    }
  }

  Widget layerRow() => Wrap(spacing: 8, runSpacing: 6, children: layerChips());

  /// What can be shown on the plan or hidden: name, whether it shows,
  /// and the switch.
  List<(String, bool, ValueChanged<bool>)> layerToggles() => [
        (
          tr3('家具', 'Жиһаз', 'Мебель', 'Furniture', ky: 'Эмерек', uz: 'Mebel'),
          showFurniture,
          (v) => update(() => showFurniture = v)
        ),
        (
          tr3('尺寸', 'Өлшемдер', 'Размеры', 'Dimensions', ky: 'Өлчөмдөр', uz: 'Oʻlchamlar'),
          showDimensions,
          (v) => update(() => showDimensions = v)
        ),
        (
          tr3('水电', 'Су-электр', 'Электрика и вода', 'Electrical and water', ky: 'Электр жана суу', uz: 'Elektr va suv'),
          showUtilities,
          (v) => update(() {
                showUtilities = v;
                if (!v) {
                  selectedUtilityId = null;
                  if (tool == EditorTool.placeUtility) {
                    tool = EditorTool.browse;
                    placementHint = null;
                  }
                }
              })
        ),
        (
          tr3('地基', 'Іргетас', 'Фундамент', 'Foundation', ky: 'Пайдубал', uz: 'Poydevor'),
          showFoundation,
          (v) => update(() {
                showFoundation = v;
                if (v && floorIndex != 0) {
                  floorIndex = 0;
                  derive();
                }
              })
        ),
      ];

  String get measureLabel => tr3('测距', 'Қашықтық өлшеу', 'Измерить расстояние', 'Measure distance', ky: 'Аралыкты өлчөө', uz: 'Masofani oʻlchash');

  void toggleMeasure(bool on) => update(() {
        cancelDrag();
        clearWallSelection();
        measurePoints = [];
        tool = on ? EditorTool.measure : EditorTool.browse;
        placementHint = null;
      });

  List<Widget> layerChips() => [
        for (final (label, on, set) in layerToggles())
          PillToggle(label: label, selected: on, onChanged: set),
        PillToggle(
            label: measureLabel,
            icon: Icons.straighten,
            checkbox: false,
            selected: tool == EditorTool.measure,
            onChanged: toggleMeasure),
      ];

  Widget hintRow() {
    final t = Tokens.of(context);
    final coach = !view3d && coachText != null && placementHint == null;
    final children = hintChildren(t, coach);
    if (compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final c in children)
          if (c is Expanded) c.child else c
      ]);
    }
    // The assistant's orb has its place at the end of this line, in the
    // corner it has on other pages and off the tools.
    return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [...children, const VoiceSlot()]));
  }

  /// The whole budget in a few characters, e.g. "≈ ₸ 18,4 млн".
  String get costChipText {
    if (!identical(costChipFor, history.present)) {
      final e = estimate;
      final v = e.total;
      costChipFor = history.present;
      costChip = v <= 0
          ? ''
          : '≈ ${currencySymbol(e.currency)} ${v < 1e6 ? money(v) : isKk ? '${dec((v / 1e6).toStringAsFixed(1))} млн' : isUz ? '${dec((v / 1e6).toStringAsFixed(1))} mln' : isEn ? '${(v / 1e6).toStringAsFixed(1)}M' : '${(v / 1e4).round()} 万'}';
    }
    return costChip;
  }

  /// Findings that ask for a change, as the issues tab would list them.
  ({int crit, int warn}) get openIssues {
    if (!identical(issueCountFor, history.present)) {
      final doc = history.present;
      var crit = 0;
      var warn = 0;
      void count(Level l) {
        if (l == Level.crit) crit++;
        if (l == Level.warn) warn++;
      }

      for (final i in doc.extras.issues) {
        count(Level.values[i.level.index]);
      }
      for (final r in runChecks(doc, derived)) {
        count(r.level == 'important' ? Level.crit : Level.warn);
      }
      for (final c in [
        ...constructionChecks(doc, derived, nameOf: displayRoomName),
        ...heatChecks(doc, heatLoss(doc, derived)),
        ...siteChecks(doc, nameOf: siteItemName),
      ]) {
        count(Level.values[c.level.index]);
      }
      issueCountFor = doc;
      issueCount = (crit: crit, warn: warn);
    }
    return issueCount;
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
                  color: coach ? t.ink : t.muted))),
      if (tool == EditorTool.resize)
        TextButton.icon(
            onPressed: footprintOptions,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(tr3('输入长宽', 'Өлшем енгізу', 'Ввести размеры', 'Enter dimensions', ky: 'Өлчөмдөрдү киргизүү', uz: 'Oʻlchamlarni kiritish'))),
      if (reachAcrossPoint != null)
        TextButton(
            key: const Key('wall-reach-across'),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: reachAcross,
            child: Text(
                tr3('接到对面', 'Қарсы қабырғаға дейін', 'До стены напротив', 'To the opposite wall', ky: 'Карама-каршы дубалга чейин', uz: 'Qarama-qarshi devorgacha'))),
      if (stamping) ...[
        TextButton(
            key: const Key('stamp-cancel'),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: cancelStamp,
            child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
        FilledButton(
            key: const Key('stamp-place'),
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14)),
            onPressed: spatialError == null ? placeStamp : null,
            child: Text(tr3('放下', 'Қою', 'Поставить', 'Place', ky: 'Коюу', uz: 'Joylash'))),
      ],
      if (tool == EditorTool.drawWall)
        IconButton(
            tooltip: '输入墙长',
            onPressed: drawingOrigin == null ? null : addWallByLength,
            icon: const YusalIcon(YIcon.measure, size: 18)),
      if (tool == EditorTool.drawWall ||
          tool == EditorTool.stair ||
          tool == EditorTool.placeFurniture ||
          tool == EditorTool.placeUtility ||
          tool == EditorTool.measure ||
          // No tool row on a phone to go back to browsing with.
          (phone && !browse && !stamping))
        TextButton(
            key: const Key('tool-done'),
            onPressed: () => update(() {
                  cancelDrag();
                  if (tool == EditorTool.selectWall ||
                      tool == EditorTool.editWall) {
                    clearWallSelection();
                  }
                  tool = EditorTool.browse;
                  drawingOrigin = null;
                  drawingEnd = null;
                  placementHint = null;
                  placingFurniture = null;
                  placingUtility = null;
                  measurePoints = [];
                }),
            child: Text(tr3('结束', 'Аяқтау', 'Завершить', 'Finish', ky: 'Бүтүрүү', uz: 'Tugatish'))),
      // While just looking at the plan: how much the checks found,
      // so nobody has to reach the last tab to learn of it.
      if (!coach && browse && openIssues.crit + openIssues.warn > 0)
        TextButton.icon(
            key: const Key('plan-issues'),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: openIssues.crit > 0 ? t.crit : t.warn,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => showTab('iss'),
            icon: const Icon(Icons.error_outline, size: 16),
            label: Text(
                tr3(
                    '问题 ${openIssues.crit + openIssues.warn}',
                    'Ескерту ${openIssues.crit + openIssues.warn}',
                    'Замечания: ${openIssues.crit + openIssues.warn}',
                    'Issues: ${openIssues.crit + openIssues.warn}', ky: 'Маселелер: ${openIssues.crit + openIssues.warn}', uz: 'Muammolar: ${openIssues.crit + openIssues.warn}'),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600))),
      // While just looking at the plan: what it would cost to build.
      if (!coach && browse && costChipText.isNotEmpty)
        TextButton(
            key: const Key('plan-cost'),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => showTab('cost'),
            child: Text(costChipText,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600))),
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
    for (var d = -size.height; d < size.width; d += 4) {
      canvas.drawLine(Offset(d, size.height), Offset(d + size.height, 0), p);
    }
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
    // The mask stays in the tree at the row's end too, with nothing faded:
    // taking it away there rebuilt the scroll view, which jumped back to
    // its start, so the last tool could never be brought fully into view.
    return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(colors: [
              Colors.black,
              Colors.black,
              more ? Colors.transparent : Colors.black
            ], stops: const [
              0,
              0.86,
              1
            ]).createShader(r),
        child: row);
  }
}
