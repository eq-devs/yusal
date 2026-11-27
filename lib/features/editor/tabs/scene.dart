part of '../page.dart';

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
              outsideLabel: tr3('室外', 'Сыртта', 'Снаружи', 'Outside', ky: 'Сырты', uz: 'Tashqari'),
              inWallLabel: tr3('墙内', 'Қабырға ішінде', 'Внутри стены', 'Inside the wall', ky: 'Дубалдын ичи', uz: 'Devor ichi'),
              areaUnit: unitM2,
              adjusting: sceneAdjusting,
              still: sceneStill,
              onPick: walk
                  ? null
                  : (source) => update(() => scenePicked = source))),
      if (scenePicked != null && !walk)
        Positioned(left: 10, top: 10, right: 10, child: pickedChip()),
      if (!walk)
        Positioned(
            right: 8,
            bottom: 62,
            child: Material(
                color: t.panel.withValues(alpha: 0.92),
                shape: CircleBorder(side: BorderSide(color: t.line)),
                child: IconButton(
                    key: const ValueKey('scene-still'),
                    tooltip:
                        tr3('导出图片', 'Суретті сақтау', 'Сохранить картинку', 'Save picture', ky: 'Сүрөттү сактоо', uz: 'Rasmni saqlash'),
                    onPressed: shareSceneImage,
                    icon: const Icon(YIcons.camera, size: 22)))),
      // Within thumb reach on the stage itself: frame the house again
      // after turning or zooming away (CAD viewers' "zoom to fit").
      if (!walk)
        Positioned(
            right: 8,
            bottom: 8,
            child: Material(
                color: t.panel.withValues(alpha: 0.92),
                shape: CircleBorder(side: BorderSide(color: t.line)),
                child: IconButton(
                    key: const ValueKey('scene-fit'),
                    tooltip: tr3('适配画面', 'Экранға сыйғызу', 'Вписать в экран', 'Fit to screen', ky: 'Экранга батыруу', uz: 'Ekranga sigʻdirish'),
                    onPressed: refitScene,
                    icon: const Icon(YIcons.fit, size: 22)))),
    ]));
    if (phoneTools) {
      return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: stage),
            const SizedBox(height: 6),
            ...(walk ? phoneWalkControls() : phoneOrbitControls()),
          ]));
    }
    final controls = walk ? walkControls() : orbitControls();
    if (compact) {
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
    }
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        final item =
            doc.extras.furniture.where((i) => i.id == furnitureId).firstOrNull;
        return item == null ? '' : item.label ?? furnitureName(item.kind);
      case WallSource():
        return tr3('墙体', 'Қабырға', 'Стена', 'Wall', ky: 'Дубал', uz: 'Devor');
      case StairSource():
        return tr3('楼梯', 'Баспалдақ', 'Лестница', 'Stairs', ky: 'Тепкич', uz: 'Zinapoya');
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
                  icon: const Icon(YIcons.edit, size: 16),
                  label:
                      Text(tr3('在 2D 中编辑', '2D-де өзгерту', 'Изменить в 2D', 'Edit in 2D', ky: '2D форматта түзөтүү', uz: '2D da tahrirlash'))),
              IconButton(
                  tooltip: tr3('关闭', 'Жабу', 'Закрыть', 'Close', ky: 'Жабуу', uz: 'Yopish'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => update(() => scenePicked = null),
                  icon: const Icon(YIcons.close, size: 16)),
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
        final f =
            history.present.floors.indexWhere((f) => f.id == item?.floorId);
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

  void setScene(SceneSettings v) => update(() => sceneSettings = v);

  /// Frame the current preset view again.
  void refitScene() => update(() => sceneViewToken++);

  String sceneStyleName(SceneStyle style) => switch (style) {
        SceneStyle.shaded ||
        SceneStyle.plain =>
          tr3('着色', 'Түрлі түсті', 'Цвет', 'Colour', ky: 'Түстүү', uz: 'Rangli'),
        SceneStyle.white => tr3('白模', 'Ақ макет', 'Белый макет', 'White model', ky: 'Ак макет', uz: 'Oq maket'),
        SceneStyle.lines => tr3('线稿', 'Сызба', 'Линии', 'Lines', ky: 'Сызыктар', uz: 'Chiziqlar'),
      };

  /// The 3D view as a large picture, to save or send.
  Future<void> shareSceneImage() async {
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
                content: Row(children: [
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(tr3(
                      '正在生成图片…', 'Сурет жасалуда…', 'Создаётся картинка…', 'Making the picture…', ky: 'Сүрөт жасалууда…', uz: 'Rasm tayyorlanmoqda…'))),
            ]))));
    Uint8List? bytes;
    try {
      // A frame first, so the dialog shows before the work starts.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      bytes = await sceneStill.png();
    } catch (_) {
      bytes = null;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr3('图片没有生成，请再试一次', 'Сурет жасалмады, қайталап көріңіз',
              'Картинка не создана, попробуйте ещё раз', "The picture wasn't made; try again", ky: 'Сүрөт жасалган жок, кайра аракет кылыңыз', uz: 'Rasm yaratilmadi, qaytadan urinib koʻring'))));
      return;
    }
    final cleaned = history.present.meta.name
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '')
        .trim();
    final base =
        cleaned.isEmpty ? tr3('房屋设计', 'Үй жобасы', 'Проект дома', 'House design', ky: 'Үй долбоору', uz: 'Uy loyihasi') : cleaned;
    final filename = '$base 3D.png';
    final file = XFile.fromData(bytes, mimeType: 'image/png', name: filename);
    if (kIsWeb) {
      await file.saveTo(filename);
    } else {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
          files: [file],
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size));
    }
  }

  List<Widget> sceneToggles() {
    final s = sceneSettings;
    final set = setScene;
    return [
      PillToggle(
          label: tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom'),
          selected: s.roof,
          onChanged: (v) => set(s.copyWith(roof: v))),
      PillToggle(
          label: tr3('家具', 'Жиһаз', 'Мебель', 'Furniture', ky: 'Эмерек', uz: 'Mebel'),
          selected: s.furniture,
          onChanged: (v) => set(s.copyWith(furniture: v))),
      PillToggle(
          label: tr3('地基', 'Іргетас', 'Фундамент', 'Foundation', ky: 'Пайдубал', uz: 'Poydevor'),
          selected: s.foundation,
          onChanged: (v) => set(s.copyWith(foundation: v))),
      if (history.present.extras.site != null)
        PillToggle(
            label: tr3('院子', 'Аула', 'Двор', 'Yard', ky: 'Короо', uz: 'Hovli'),
            selected: s.site,
            onChanged: (v) => set(s.copyWith(site: v))),
      PillToggle(
          label: tr3('剖切', 'Кесу', 'Разрез', 'Section', ky: 'Кесилиш', uz: 'Kesim'),
          selected: s.cut,
          onChanged: (v) => set(s.copyWith(cut: v))),
      // The look of the model, as the visual styles of a CAD viewport:
      // each tap moves on to the next.
      ActionChip(
          key: const ValueKey('scene-style'),
          avatar: Icon(
              switch (s.style) {
                SceneStyle.white => YIcons.cube,
                SceneStyle.lines => YIcons.design,
                _ => Icons.palette_outlined,
              },
              size: 16),
          label: Text(sceneStyleName(s.style)),
          onPressed: () => set(s.copyWith(
                  style: switch (s.style) {
                SceneStyle.shaded || SceneStyle.plain => SceneStyle.white,
                SceneStyle.white => SceneStyle.lines,
                SceneStyle.lines => SceneStyle.shaded,
              }))),
      ActionChip(
          key: const ValueKey('scene-roof-style'),
          avatar: RoofIcon(roofStyle, size: 16),
          label: Text(roofStyleName(roofStyle)),
          onPressed: chooseRoof),
    ];
  }

  List<Widget> viewButtons() => [
        for (final (key, zh, kk) in const [
          ('iso', '鸟瞰', 'Жоғарыдан'),
          ('front', '正面', 'Алдынан'),
          ('back', '背面', 'Артынан'),
          ('side', '侧面', 'Бүйірінен'),
          ('top', '顶视', 'Үстінен'),
        ])
          Btn(
              label: tr(zh, kk),
              selected: sceneView == key,
              onPressed: () => update(() {
                    sceneView = key;
                    sceneViewToken++;
                  })),
      ];

  /// Cut height; shown only while the cut is on, so it never reads as a
  /// setting that does something with the cut off.
  Widget cutSlider(double width) {
    final t = Tokens.of(context);
    final s = sceneSettings;
    final top = math.max(3.0, derived.height / 1000);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(tr3('剖切高度', 'Кесу биіктігі', 'Высота разреза', 'Section height', ky: 'Кесилиштин бийиктиги', uz: 'Kesim balandligi'),
          style: TextStyle(fontSize: 13, color: t.muted)),
      SizedBox(
          width: width,
          child: Slider(
              key: const ValueKey('cut-height'),
              min: 0.3,
              max: top,
              value: s.cutHeight.clamp(0.3, top),
              onChangeStart: (_) => update(() => sceneAdjusting = true),
              onChangeEnd: (_) => update(() => sceneAdjusting = false),
              onChanged: (v) => setScene(s.copyWith(cutHeight: v, cut: true)))),
      Text('${dec(s.cutHeight.toStringAsFixed(2))} $unitM',
          style: mono(size: 12)),
    ]);
  }

  /// Sun time, north and floors shown: set once, rarely touched.
  List<Widget> lightControls(void Function(SceneSettings) set) {
    final t = Tokens.of(context);
    final s = sceneSettings;
    final hour = s.hour;
    final hh =
        '${hour.floor().toString().padLeft(2, '0')}:${((hour % 1) * 60).round().toString().padLeft(2, '0')}';
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
      labelled(
          tr3('日照时间', 'Күн уақыты', 'Время суток', 'Time of day', ky: 'Күндүн убагы', uz: 'Kun vaqti'),
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
          tr3('图纸上方朝向', 'Сызбаның жоғарғы жағы', 'Верх чертежа', 'Top of drawing', ky: 'Чийменин үстү', uz: 'Chizma tepasi'),
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
                if (v != null) {
                  action('SetNorthAngle', {'value': (360 - v) % 360});
                }
              })),
      if (floors.length > 1)
        labelled(
            tr3('显示到', 'Көрсету', 'Показывать до', 'Show up to', ky: 'Көрсөтүү чеги', uz: 'Koʻrsatish chegarasi'),
            Seg<int>(
                value: math.min(s.maxFloor, floors.length - 1),
                items: [
                  for (var i = 0; i < floors.length; i++)
                    (i, displayFloorName(floors[i].name))
                ],
                onChanged: (v) => set(s.copyWith(maxFloor: v)))),
    ];
  }

  /// Phones: the stage takes the screen; under it one row of views and
  /// one row of switches (Hick: two short choices instead of a page of
  /// controls). Sun, north and floors move to a sheet.
  List<Widget> phoneOrbitControls() {
    final s = sceneSettings;
    return [
      fadeRow(viewButtons()),
      const SizedBox(height: 6),
      // "更多" stays in place at the end, never scrolled out of reach.
      Row(children: [
        Expanded(child: fadeRow(sceneToggles())),
        const SizedBox(width: 4),
        IconButton.outlined(
            key: const ValueKey('scene-more'),
            tooltip: tr3('更多设置', 'Басқа баптаулар', 'Другие настройки', 'More settings', ky: 'Дагы жөндөөлөр', uz: 'Qoʻshimcha sozlamalar'),
            onPressed: sceneMoreSheet,
            icon: const YusalIcon(YIcon.settings, size: 20)),
        // The phone's bottom bar keeps the assistant's place.
        if (!phone) const VoiceSlot(),
      ]),
      if (s.cut) cutSlider(170),
    ];
  }

  /// Phones walking: one row of places to go and the floor switch.
  List<Widget> phoneWalkControls() {
    final c = walkControls();
    final go = c.first as Wrap;
    return [
      Row(children: [
        Expanded(child: fadeRow(go.children.skip(1).toList())),
        if (!phone) const VoiceSlot(),
      ]),
      if (history.present.floors.length > 1) c[1],
    ];
  }

  void sceneMoreSheet() {
    final t = Tokens.of(context);
    showMotionSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => StatefulBuilder(builder: (context, setSheet) {
              void set(SceneSettings v) {
                setScene(v);
                setSheet(() {});
              }

              return SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: lightControls(set)),
                            const SizedBox(height: 10),
                            Text(
                                tr3(
                                    '单指拖动旋转 · 双指缩放/平移/扭转 · 剖切可看墙内门窗 · 点物体可回到 2D 编辑',
                                    'Бір саусақпен айналдырыңыз · екі саусақпен үлкейтіңіз/жылжытыңыз · кесу арқылы есік-терезені көріңіз · нысанды басып 2D-де өзгертіңіз',
                                    'Вращайте одним пальцем · масштабируйте и двигайте двумя · разрез показывает окна и двери внутри · нажмите на объект, чтобы изменить его в 2D',
                                    'Rotate with one finger · zoom and pan with two · the section shows windows and doors inside · tap an item to edit it in 2D', ky: 'Бир манжа менен буруңуз · эки манжа менен чоңойтуп жылдырыңыз · кесилиш ичиндеги терезе менен эшиктерди көрсөтөт · 2D форматта түзөтүү үчүн нерсени басыңыз', uz: 'Bir barmoq bilan aylantiring · ikki barmoq bilan kattalashtiring va suring · kesim ichidagi deraza va eshiklarni koʻrsatadi · 2D da tahrirlash uchun elementga bosing'),
                                style: TextStyle(fontSize: 12, color: t.muted)),
                          ])));
            }));
  }

  List<Widget> orbitControls() {
    final t = Tokens.of(context);
    final s = sceneSettings;
    final set = setScene;
    return [
      Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...sceneToggles(),
            if (s.cut) cutSlider(150),
          ]),
      const SizedBox(height: 6),
      Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tr3('视角', 'Көрініс', 'Вид', 'View', ky: 'Көрүнүш', uz: 'Koʻrinish'),
                style: TextStyle(fontSize: 13, color: t.muted)),
            ...viewButtons(),
          ]),
      const SizedBox(height: 6),
      Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: lightControls(set)),
      Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              tr3(
                  '单指拖动旋转 · 双指缩放/平移 · 打开“地基”时地面变透明 · 剖切可看墙内门窗关系 · 点物体可回到 2D 编辑',
                  'Бір саусақпен айналдырыңыз · екі саусақпен үлкейтіңіз/жылжытыңыз · «Іргетас» қосылғанда жер мөлдір болады · кесу арқылы есік-терезе орнын көруге болады · нысанды басып 2D-де өзгертіңіз',
                  'Вращайте одним пальцем · масштабируйте и сдвигайте двумя · при включённом «Фундаменте» земля становится прозрачной · разрез показывает расположение окон и дверей · нажмите на объект, чтобы изменить его в 2D',
                  'Rotate with one finger · zoom and pan with two · with “Foundation” on, the ground turns transparent · the section shows where windows and doors are · tap an item to edit it in 2D', ky: 'Бир манжа менен буруңуз · эки манжа менен чоңойтуп жылдырыңыз · «Пайдубал» күйгүзүлгөндө жер тунук болот · кесилиш терезе менен эшиктердин ордун көрсөтөт · 2D форматта түзөтүү үчүн нерсени басыңыз', uz: 'Bir barmoq bilan aylantiring · ikki barmoq bilan kattalashtiring va suring · “Poydevor” yoqilganda yer shaffof boʻladi · kesim deraza va eshiklar joyini koʻrsatadi · 2D da tahrirlash uchun elementga bosing'),
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
    final w = history.present.footprint.width.toDouble();
    final d = history.present.footprint.depth.toDouble();
    return [
      Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tr3('去往', 'Бару:', 'Перейти:', 'Go to:', ky: 'Өтүү:', uz: 'Oʻtish:'),
                style: TextStyle(fontSize: 13, color: t.muted)),
            Btn(
                label: tr3('门外', 'Есік алды', 'Перед входом', 'In front of the entrance', ky: 'Кире бериштин алдында', uz: 'Kirish oldida'),
                icon: YIcons.door,
                onPressed: () => update(() => walkStart = null)),
            for (final room in floor.rooms)
              if (g.base.roomGeometry
                  .any((r) => r.id == room.id && r.clearRects.isNotEmpty))
                Btn(
                    label: displayRoomName(room),
                    onPressed: () {
                      final spot = roomSpot(
                          g.base.roomGeometry
                              .firstWhere((r) => r.id == room.id),
                          floorIndex);
                      go(spot.x, spot.y, spot.yaw);
                    }),
            Btn(
                label: tr3('后院', 'Аула', 'Задний двор', 'Backyard', ky: 'Арткы короо', uz: 'Orqa hovli'),
                icon: YIcons.tree,
                // Behind the house, looking back at it.
                onPressed: () => go(w / 2, d + 4000, math.pi)),
          ]),
      if (floors.length > 1)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Seg<int>(
                value: floorIndex,
                items: [
                  for (var i = 0; i < floors.length; i++)
                    (i, displayFloorName(floors[i].name))
                ],
                onChanged: (v) => update(() {
                      floorIndex = v;
                      derive();
                      walkStart = null;
                    }))),
      Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              tr3(
                  '左下摇杆移动，拖动画面转头。电脑上可用 W A S D / 方向键。墙会挡住你，门洞可以穿过。',
                  'Сол жақ төмендегі джойстикпен жүріңіз, экранды сүйреп бұрылыңыз. Компьютерде W A S D / бағыт пернелері. Қабырғадан өтпейсіз, есік ойығынан өтуге болады.',
                  'Двигайтесь джойстиком слева внизу, поворачивайтесь, проводя по экрану. На компьютере — W A S D / стрелки. Сквозь стены пройти нельзя, через дверной проём — можно.',
                  "Move with the joystick at the bottom left and turn by swiping the screen. On a computer use W A S D / arrow keys. You can't walk through walls, but you can through doorways.", ky: 'Сол ылдыйдагы джойстик менен жүрүп, экранды сүрүп бурулуңуз. Компьютерде W A S D / жебе баскычтарын колдонуңуз. Дубалдан өтүүгө болбойт, эшиктен өтсө болот.', uz: 'Chap pastdagi joystik bilan yuring, ekranni surib buriling. Kompyuterda W A S D / strelka tugmalaridan foydalaning. Devordan oʻtib boʻlmaydi, eshikdan oʻtsa boʻladi.'),
              style: TextStyle(fontSize: 12, color: t.muted))),
    ];
  }
}
