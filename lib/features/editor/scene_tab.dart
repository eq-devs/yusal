part of '../house_editor.dart';

/// 3D exterior and walk-through pages: the stage on a sheet, with the
/// drafting page's controls (layers, cut, views, sun, north) under it.
extension _SceneTab on _HouseEditorState {
  Widget sceneTab(bool wide) {
    final t = Tokens.of(context);
    final walk = tab == 'walk';
    final settings = sceneSettings.copyWith(dark: t.dark);
    final stage = Sheet(
        child: Stack(children: [
      Positioned.fill(
          child: SceneView(
              key: ValueKey(walk),
              doc: history.present,
              derived: derived,
              roomName: displayRoomName,
              settings: settings,
              walk: walk,
              view: sceneView,
              viewToken: sceneViewToken,
              walkStart: walkStart,
              walkFloor: floorIndex,
              selected: scenePicked,
              outsideLabel: tr('室外', 'Сыртта'),
              inWallLabel: tr('墙内', 'Қабырға ішінде'),
              areaUnit: unitM2,
              onPick: walk
                  ? null
                  : (source) => update(() => scenePicked = source))),
      if (scenePicked != null && !walk)
        Positioned(left: 10, top: 10, right: 10, child: pickedChip()),
    ]));
    final controls = walk ? walkControls() : orbitControls();
    if (compact)
      return Padding(
          padding: const EdgeInsets.all(8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: stage),
            const SizedBox(width: 8),
            SizedBox(
                width: 230,
                child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: controls))),
          ]));
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: stage),
          const SizedBox(height: 8),
          ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.38),
              child: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: controls))),
        ]));
  }

  String pickedName(SourceRef source) {
    final doc = history.present;
    switch (source) {
      case RoomSource(:final roomId):
        final room = doc.floors
            .expand((f) => f.rooms)
            .where((r) => r.id == roomId)
            .firstOrNull;
        return room == null ? '' : displayRoomName(room);
      case OpeningSource(:final openingId):
        for (var f = 0; f < derived.floors.length; f++) {
          final p = derived.floors[f].openings
              .where((p) => p.opening.id == openingId)
              .firstOrNull;
          if (p != null) return openingLabel(p, f);
        }
        return '';
      case FurnitureSource(:final furnitureId):
        final item = doc.extras.furniture
            .where((i) => i.id == furnitureId)
            .firstOrNull;
        return item == null ? '' : item.label ?? furnitureName(item.kind);
      case WallSource():
        return tr('墙体', 'Қабырға');
      case StairSource():
        return tr('楼梯', 'Баспалдақ');
    }
  }

  Widget pickedChip() {
    final t = Tokens.of(context);
    final source = scenePicked!;
    return Align(
        alignment: Alignment.topLeft,
        child: Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
                color: t.panel.withValues(alpha: 0.94),
                border: Border.all(color: t.line),
                borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text(pickedName(source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              TextButton.icon(
                  onPressed: () => openInPlan(source),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(tr('在 2D 中编辑', '2D-де өзгерту'))),
              IconButton(
                  tooltip: tr('关闭', 'Жабу'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => update(() => scenePicked = null),
                  icon: const Icon(Icons.close, size: 16)),
            ])));
  }

  /// Jump from a picked 3D object to its card on the plan.
  void openInPlan(SourceRef source) {
    switch (source) {
      case RoomSource(:final roomId):
        final f = history.present.floors
            .indexWhere((f) => f.rooms.any((r) => r.id == roomId));
        update(() {
          if (f >= 0) floorIndex = f;
          derive();
          tab = 'plan';
          clearSelection();
          selectedRoomId = roomId;
          scenePicked = null;
        });
      case FurnitureSource(:final furnitureId):
        final item = history.present.extras.furniture
            .where((i) => i.id == furnitureId)
            .firstOrNull;
        final f = history.present.floors.indexWhere((f) => f.id == item?.floorId);
        update(() {
          if (f >= 0) floorIndex = f;
          derive();
          tab = 'plan';
          clearSelection();
          showFurniture = true;
          selectedFurnitureId = furnitureId;
          scenePicked = null;
        });
      case OpeningSource(:final openingId):
        final f = history.present.floors
            .indexWhere((f) => f.openings.any((o) => o.id == openingId));
        update(() {
          if (f >= 0) floorIndex = f;
          derive();
          tab = 'plan';
          clearSelection();
          selectedOpeningId = openingId;
          scenePicked = null;
        });
      default:
        update(() => scenePicked = null);
        pick3d(source);
    }
  }

  List<Widget> orbitControls() {
    final t = Tokens.of(context);
    final s = sceneSettings;
    void set(SceneSettings v) => update(() => sceneSettings = v);
    final hour = s.hour;
    final hh = '${hour.floor().toString().padLeft(2, '0')}:${((hour % 1) * 60).round().toString().padLeft(2, '0')}';
    final north = (360 - history.present.footprint.northAngleDeg) % 360;
    final floors = history.present.floors;
    Widget labelled(String text, Widget child) => Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(text, style: TextStyle(fontSize: 13, color: t.muted)),
              child,
            ]);
    return [
      Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PillToggle(
                label: tr('屋顶', 'Шатыр'),
                selected: s.roof,
                onChanged: (v) => set(s.copyWith(roof: v))),
            PillToggle(
                label: tr('家具', 'Жиһаз'),
                selected: s.furniture,
                onChanged: (v) => set(s.copyWith(furniture: v))),
            PillToggle(
                label: tr('地基', 'Іргетас'),
                selected: s.foundation,
                onChanged: (v) => set(s.copyWith(foundation: v))),
            PillToggle(
                label: tr('剖切', 'Кесу'),
                selected: s.cut,
                onChanged: (v) => set(s.copyWith(cut: v))),
            labelled(
                tr('剖切高度', 'Кесу биіктігі'),
                SizedBox(
                    width: 150,
                    child: Slider(
                        min: 0.3,
                        max: math.max(3.0, derived.height / 1000),
                        value: s.cutHeight.clamp(
                            0.3, math.max(3.0, derived.height / 1000)),
                        onChanged: (v) =>
                            set(s.copyWith(cutHeight: v, cut: true))))),
            Text('${dec(s.cutHeight.toStringAsFixed(2))} $unitM',
                style: mono(size: 12)),
          ]),
      const SizedBox(height: 6),
      Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tr('视角', 'Көрініс'),
                style: TextStyle(fontSize: 13, color: t.muted)),
            for (final (key, zh, kk) in const [
              ('iso', '鸟瞰', 'Жоғарыдан'),
              ('front', '正面(入口)', 'Алдынан (кіреберіс)'),
              ('back', '背面', 'Артынан'),
              ('side', '侧面', 'Бүйірінен'),
              ('top', '顶视', 'Үстінен'),
            ])
              Btn(
                  label: tr(zh, kk),
                  primary: sceneView == key,
                  onPressed: () => update(() {
                        sceneView = key;
                        sceneViewToken++;
                      })),
            IconButton(
                tooltip: '恢复视角'.trKey('Көріністі қалпына келтіру'),
                visualDensity: VisualDensity.compact,
                onPressed: () => update(() {
                      sceneView = 'iso';
                      sceneViewToken++;
                    }),
                icon: const Icon(Icons.center_focus_strong, size: 20)),
          ]),
      const SizedBox(height: 6),
      Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            labelled(
                tr('日照时间', 'Күн уақыты'),
                SizedBox(
                    width: 170,
                    child: Slider(
                        min: 5,
                        max: 23,
                        divisions: 72,
                        value: hour,
                        onChanged: (v) => set(s.copyWith(hour: v))))),
            Text(hh, style: mono(size: 12)),
            labelled(
                tr('图纸上方朝向', 'Сызбаның жоғарғы жағы'),
                DropdownButton<int>(
                    value: north,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final (deg, zh, kk) in const [
                        (0, '北', 'Солтүстік'),
                        (90, '东', 'Шығыс'),
                        (180, '南', 'Оңтүстік'),
                        (270, '西', 'Батыс'),
                      ])
                        DropdownMenuItem(value: deg, child: Text(tr(zh, kk)))
                    ],
                    onChanged: (v) {
                      if (v != null)
                        action('SetNorthAngle', {'value': (360 - v) % 360});
                    })),
            if (floors.length > 1)
              labelled(
                  tr('显示到', 'Көрсету'),
                  Seg<int>(
                      value: math.min(s.maxFloor, floors.length - 1),
                      items: [
                        for (var i = 0; i < floors.length; i++)
                          (i, displayFloorName(floors[i].name))
                      ],
                      onChanged: (v) => set(s.copyWith(maxFloor: v)))),
          ]),
      Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              tr('单指拖动旋转 · 双指缩放/平移 · 打开“地基”时地面变透明 · 剖切可看墙内门窗关系 · 点物体可回到 2D 编辑',
                  'Бір саусақпен айналдырыңыз · екі саусақпен үлкейтіңіз/жылжытыңыз · «Іргетас» қосылғанда жер мөлдір болады · кесу арқылы есік-терезе орнын көруге болады · нысанды басып 2D-де өзгертіңіз'),
              style: TextStyle(fontSize: 12, color: t.muted))),
    ];
  }

  List<Widget> walkControls() {
    final t = Tokens.of(context);
    final floors = history.present.floors;
    final g = derived.floors[floorIndex];
    void go(double x, double y, double yaw) => update(() {
          walkStart = (
            floorIndex: floorIndex,
            x: x,
            y: y,
            yaw: yaw,
            token: (walkStart?.token ?? 0) + 1
          );
        });
    final w = history.present.footprint.width.toDouble(),
        d = history.present.footprint.depth.toDouble();
    return [
      Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tr('去往', 'Бару:'),
                style: TextStyle(fontSize: 13, color: t.muted)),
            Btn(
                label: tr('门外', 'Есік алды'),
                icon: Icons.door_front_door_outlined,
                onPressed: () => update(() => walkStart = null)),
            for (final room in floor.rooms)
              if (g.base.roomGeometry
                  .any((r) => r.id == room.id && r.clearRects.isNotEmpty))
                Btn(
                    label: displayRoomName(room),
                    onPressed: () {
                      final spot = roomSpot(
                          g.base.roomGeometry.firstWhere((r) => r.id == room.id),
                          floorIndex);
                      go(spot.x, spot.y, spot.yaw);
                    }),
            Btn(
                label: tr('后院', 'Аула'),
                icon: Icons.park_outlined,
                // Behind the house, looking back at it.
                onPressed: () => go(w / 2, d + 4000, math.pi)),
          ]),
      if (floors.length > 1)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Seg<int>(
                value: floorIndex,
                items: [
                  for (var i = 0; i < floors.length; i++) (i, displayFloorName(floors[i].name))
                ],
                onChanged: (v) => update(() {
                      floorIndex = v;
                      derive();
                      walkStart = null;
                    }))),
      Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              tr('左下摇杆移动，拖动画面转头。电脑上可用 W A S D / 方向键。墙会挡住你，门洞可以穿过。',
                  'Сол жақ төмендегі джойстикпен жүріңіз, экранды сүйреп бұрылыңыз. Компьютерде W A S D / бағыт пернелері. Қабырғадан өтпейсіз, есік ойығынан өтуге болады.'),
              style: TextStyle(fontSize: 12, color: t.muted))),
    ];
  }
}
