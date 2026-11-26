part of '../page.dart';

/// Cards for the current selection, after the room card of the drafting
/// page: name, the other language, a grid of figures, a note — every value
/// can be tapped to edit.
extension _SelectionCards on _HouseEditorState {
  Widget? selectionCard() {
    if (view3d) return null;
    final g = derived.floors[floorIndex];
    if (selectedUtilityId != null) {
      final u =
          floorUtilities.where((u) => u.id == selectedUtilityId).firstOrNull;
      if (u != null) return utilityCard(u);
    }
    if (selectedFurnitureId != null) {
      final f = history.present.extras.furniture
          .where((f) => f.id == selectedFurnitureId)
          .firstOrNull;
      if (f != null) return furnitureCard(f);
    }
    if (selectedOpeningId != null) {
      final p = g.openings
          .where((p) => p.opening.id == selectedOpeningId)
          .firstOrNull;
      if (p != null) return openingCard(p);
    }
    if (selectedRoomId != null) {
      final room = floor.rooms.where((r) => r.id == selectedRoomId).firstOrNull;
      if (room != null) return roomCard(room);
    }
    return null;
  }

  /// What the selection card is about; a new value is a new selection.
  String get selectionIdentity =>
      selectedUtilityId ??
      selectedFurnitureId ??
      selectedOpeningId ??
      selectedRoomId ??
      '';

  bool get wideLayout => !compact && MediaQuery.sizeOf(context).width >= 1000;

  /// Card chrome: on phones it floats over the bottom of the plan, can fold
  /// to one line and scrolls when tall.
  Widget panel(
      {required Widget title,
      String? subtitle,
      required List<Widget> children,
      String? summary,
      List<Widget> actions = const [],
      String? deleteLabel,
      VoidCallback? onDelete}) {
    final t = Tokens.of(context);
    final wide = wideLayout;
    // Delete sits in the header, where it is always in reach, like the
    // trash can of a selection toolbar; the common actions sit right under
    // it in one row, so neither hides below the fold of a folded card.
    final head = Row(children: [
      Expanded(child: title),
      if (onDelete != null)
        IconButton(
            key: const ValueKey('selection-delete'),
            tooltip: deleteLabel ?? tr3('删除', 'Жою', 'Удалить', 'Delete', ky: 'Өчүрүү', uz: 'Oʻchirish'),
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: t.crit)),
      if (!wide)
        IconButton(
            tooltip: panelCollapsed
                ? tr3('展开', 'Ашу', 'Развернуть', 'Expand', ky: 'Жайып көрсөтүү', uz: 'Yoyish')
                : tr3('收起', 'Жию', 'Свернуть', 'Collapse', ky: 'Жыйноо', uz: 'Yigʻish'),
            visualDensity: VisualDensity.compact,
            onPressed: () => update(() {
                  panelCollapsed = !panelCollapsed;
                  panelFull = false;
                }),
            icon: Icon(panelCollapsed ? Icons.expand_less : Icons.expand_more,
                size: 20)),
      IconButton(
          tooltip: tr3('关闭', 'Жабу', 'Закрыть', 'Close', ky: 'Жабуу', uz: 'Yopish'),
          visualDensity: VisualDensity.compact,
          onPressed: () => update(clearSelection),
          icon: const Icon(Icons.close, size: 18)),
    ]);
    // Phones: a grip to pull the card open or push it shut, as on any
    // bottom sheet.
    final grip = GestureDetector(
        key: const Key('selection-grip'),
        behavior: HitTestBehavior.opaque,
        onTap: () => update(() {
              panelCollapsed = !panelCollapsed;
              panelFull = false;
            }),
        // Three stops, as on a map's sheet: one line, the usual card,
        // and nearly the whole drawing.
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 40) return;
          HapticFeedback.selectionClick();
          update(() {
            if (v > 0) {
              if (panelFull) {
                panelFull = false;
              } else {
                panelCollapsed = true;
              }
            } else if (panelCollapsed) {
              panelCollapsed = false;
            } else {
              panelFull = true;
            }
          });
        },
        child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Center(
                child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                        color: t.line,
                        borderRadius: BorderRadius.circular(3))))));
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!wide) grip,
          head,
          if (subtitle != null && (wide || !panelCollapsed))
            Text(subtitle, style: TextStyle(fontSize: 12, color: t.muted)),
          if (!wide && panelCollapsed && summary != null)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(size: 12, color: t.muted))),
          if (actions.isNotEmpty && !wide)
            Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: fadeRow(actions)),
          if (wide || !panelCollapsed) ...children,
          if (actions.isNotEmpty && wide)
            Wrap(spacing: 8, runSpacing: 8, children: actions),
        ]);
    final sheet = Container(
        // On a phone the sheet runs down under the home indicator.
        padding: EdgeInsets.fromLTRB(
            16, 8, 8, 12 + (phone ? safeInsets.bottom : 0)),
        decoration: BoxDecoration(
            color: t.panel,
            // A card beside the drawing; on a phone a sheet that rises
            // from the bottom edge.
            border: wide ? Border.all(color: t.line) : null,
            borderRadius: phone
                ? const BorderRadius.vertical(top: Radius.circular(24))
                : BorderRadius.circular(20),
            boxShadow: wide
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, -2))
                  ]),
        child: wide
            ? body
            : ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: math.max(
                        140, canvasSize.height * (panelFull ? 0.88 : 0.5))),
                child: SingleChildScrollView(child: body)));
    return sheet;
  }

  Widget titleText(String text, {VoidCallback? onTap, Widget? tag}) {
    final t = Tokens.of(context);
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(text,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.ink)),
                  if (tag != null) tag,
                  if (onTap != null)
                    Icon(Icons.edit_outlined, size: 14, color: t.muted),
                ])));
  }

  Future<int?> askMm(String title, num value) async {
    final text = await promptText(context,
        title: title,
        initial: '${value.round()}',
        cancel: tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
        ok: tr3('确定', 'Жарайды', 'ОК', 'OK', ky: 'OK', uz: 'OK'),
        number: true,
        suffix: unitMm);
    final parsed = parseNumber(text ?? '');
    if (parsed == null || !parsed.isFinite) return null;
    return parsed.round();
  }

  Future<String?> askText(String title, String value,
          {bool multiline = false}) =>
      promptText(context,
          title: title,
          initial: value,
          cancel: tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
          ok: tr3('确定', 'Жарайды', 'ОК', 'OK', ky: 'OK', uz: 'OK'),
          multiline: multiline);

  Widget roomCard(Room room) {
    final t = Tokens.of(context);
    final stats = roomStats(room, derived.floors[floorIndex], floor.height);
    final info = history.present.extras.rooms[room.id] ?? const RoomInfo();
    final name = displayRoomName(room);
    final other = isWestern
        ? otherLanguageType(room.type, zh: true)
        : otherLanguageType(room.type, zh: false);
    final ratio = stats.floorPerWindow;
    final habitable = room.type == RoomType.bedroom ||
        room.type == RoomType.living ||
        room.type == RoomType.dining;
    final area = stats.area / 1e6;
    final label = info.labelArea == null ? null : info.labelArea! / 100;
    return panel(
        title: titleText(name, onTap: () async {
          final value = await askText(
              tr3('房间名称', 'Бөлме атауы', 'Название комнаты', 'Room name', ky: 'Бөлмөнүн аталышы', uz: 'Xona nomi'), name);
          if (value != null && value.trim().isNotEmpty) {
            action('RenameRoom', {'roomId': room.id, 'value': value.trim()});
          }
        }, tag: TagPill(roomTypeName(room.type), t.chk)),
        subtitle: other,
        summary:
            '${stats.clearWidth.round()} × ${stats.clearDepth.round()} · ${dec(area.toStringAsFixed(1))} $unitM2',
        // The three things done to a room most, in reach while folded.
        actions: [
          Btn(
              key: const Key('room-use'),
              label: tr3('改用途', 'Түрін өзгерту', 'Назначение', 'Use', ky: 'Колдонулушу', uz: 'Vazifasi'),
              icon: Icons.label_outline,
              onPressed: () => update(() => panelCollapsed = false)),
          Btn(
              key: const Key('room-door'),
              label: tr3('加门', 'Есік қосу', 'Дверь', 'Door', ky: 'Эшик', uz: 'Eshik'),
              icon: Icons.door_front_door_outlined,
              onPressed: () => update(() {
                    clearSelection();
                    placingOpening = OpeningKind.door;
                    tool = EditorTool.placeOpening;
                    placementHint = tr3(
                        '点这间房的一面墙，门就放在那里',
                        'Осы бөлменің қабырғасын басыңыз, есік сонда қойылады',
                        'Нажмите на стену этой комнаты, дверь встанет там',
                        'Tap a wall of this room and the door goes there', ky: 'Бул бөлмөнүн дубалын басыңыз, эшик ошол жерге коюлат', uz: 'Bu xonaning devoriga bosing, eshik oʻsha yerga qoʻyiladi');
                  })),
          Btn(
              key: const Key('room-furniture'),
              label: tr3('放家具', 'Жиһаз қою', 'Мебель', 'Furniture', ky: 'Эмерек', uz: 'Mebel'),
              icon: Icons.chair_outlined,
              onPressed: chooseFurniture),
        ],
        children: [
          KvGrid([
            Kv('${stats.clearWidth.round()} × ${stats.clearDepth.round()}',
                tr3('净尺寸 mm', 'Таза өлшем, мм', 'Размеры в свету, мм', 'Clear dimensions, mm', ky: 'Таза өлчөмдөр, мм', uz: 'Sof oʻlchamlar, mm')),
            Kv('${dec(area.toStringAsFixed(1))} $unitM2',
                tr3('按尺寸计算', 'Өлшем бойынша есеп', 'Расчёт по размерам', 'Calculated from dimensions', ky: 'Өлчөмдөрдөн эсептелди', uz: 'Oʻlchamlardan hisoblandi')),
            Kv(
                label == null
                    ? '—'
                    : '${dec(label.toStringAsFixed(label % 1 == 0 ? 0 : 1))} $unitM2',
                tr3('图纸标注', 'Сызбадағы белгі', 'Подпись на чертеже', 'Label on the drawing', ky: 'Чиймедеги жазуу', uz: 'Chizmadagi yozuv'),
                onTap: () async {
              final text = await promptText(context,
                  title: tr3('图纸标注面积', 'Сызбадағы аудан', 'Площадь по чертежу', 'Drawing area', ky: 'Чийме аянты', uz: 'Chizma maydoni'),
                  initial: label == null ? '' : '$label',
                  cancel: tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
                  ok: tr3('确定', 'Жарайды', 'ОК', 'OK', ky: 'OK', uz: 'OK'),
                  number: true,
                  suffix: unitM2);
              if (text == null) return;
              final v = parseNumber(text);
              action('SetRoomInfo', {
                'roomId': room.id,
                'labelArea':
                    v == null || text.trim().isEmpty ? null : (v * 100).round()
              });
            }),
            Kv('${stats.windows.length} ${tr3('扇', 'дана', 'шт.', 'pcs', ky: 'даана', uz: 'dona')} · ${dec((stats.windowArea / 1e6).toStringAsFixed(2))} $unitM2',
                tr3('窗面积', 'Терезе ауданы', 'Площадь окон', 'Window area', ky: 'Терезелердин аянты', uz: 'Derazalar maydoni')),
            Kv(
                ratio == null
                    ? '1 : ∞'
                    : '1 : ${dec(ratio.toStringAsFixed(1))}',
                tr3('窗地比 (居室宜 ≥ 1:7)', 'Терезе/еден (тұрғын ≥ 1:7)',
                    'Окна/пол (жилая ≥ 1:7)',
                    'Windows/floor (living ≥ 1:7)', ky: 'Терезе/пол (турак жай ≥ 1:7)', uz: 'Deraza/pol (turar joy ≥ 1:7)'),
                color:
                    habitable && (ratio == null || ratio > 7) ? t.warn : null),
            Kv('${dec((stats.volume / 1e9).toStringAsFixed(1))} $unitM3',
                '${tr3('房间容积 (层高', 'Бөлме көлемі (биіктігі', 'Объём комнаты (высота', 'Room volume (height', ky: 'Бөлмөнүн көлөмү (бийиктиги', uz: 'Xona hajmi (balandligi')} ${m2dp(floor.height)})'),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final type in RoomType.values)
              ChoiceChip(
                  label: Text(roomTypeName(type),
                      style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  selected: room.type == type,
                  onSelected: (_) => action(
                      'SetRoomType', {'roomId': room.id, 'value': type})),
          ]),
          const SizedBox(height: 8),
          InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final value = await askText(
                    tr3('房间说明', 'Бөлме туралы жазба', 'Заметка о комнате', 'Room note', ky: 'Бөлмө жөнүндө эскертме', uz: 'Xona haqida izoh'),
                    info.note,
                    multiline: true);
                if (value != null) {
                  action('SetRoomInfo', {'roomId': room.id, 'note': value});
                }
              },
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                      info.note.isEmpty
                          ? tr3(
                              '＋ 添加说明（布置、采光、注意事项…）',
                              '＋ Жазба қосу (жиһаз, жарық, ескерту…)',
                              '＋ Добавить заметку (мебель, свет, примечания…)',
                              '＋ Add a note (furniture, lighting, remarks…)', ky: '＋ Эскертме кошуу (эмерек, жарык, эскертүүлөр…)', uz: '＋ Izoh qoʻshish (mebel, yoritish, mulohazalar…)')
                          : info.note,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: info.note.isEmpty ? t.ink : t.muted)))),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr3('走进去看看', 'Ішіне кіріп көру', 'Войти и осмотреться', 'Walk in and look around', ky: 'Кирип, айланага көз чаптыруу', uz: 'Kirib, atrofni koʻrish'),
                icon: Icons.directions_walk,
                onPressed: () => walkInto(room.id)),
            Btn(
                label: tr3(
                    '与相邻房间合并', 'Көршімен біріктіру', 'Объединить с соседней', 'Merge with the next room', ky: 'Кийинки бөлмө менен бириктирүү', uz: 'Keyingi xona bilan birlashtirish'),
                icon: Icons.join_inner,
                onPressed: () => mergeRoom(room)),
            Btn(
                label: tr3('删除房间', 'Бөлмені жою', 'Удалить комнату', 'Delete the room', ky: 'Бөлмөнү өчүрүү', uz: 'Xonani oʻchirish'),
                icon: Icons.delete_outline,
                danger: true,
                onPressed: () {
                  final updated = paintCells(
                      history.present,
                      floor.id,
                      regionCells(base.axes, room.regions).cells.toList(),
                      room.type,
                      () => const Uuid().v4(),
                      erase: true);
                  update(() {
                    clearSelection();
                    if (history
                        .commit(withExtras(updated, history.present.extras))) {
                      changed();
                    }
                  });
                }),
          ]),
        ]);
  }

  String? otherLanguageType(RoomType type, {required bool zh}) {
    final names = {
      RoomType.living: ('客厅', 'Қонақ бөлме'),
      RoomType.bedroom: ('卧室', 'Жатын бөлме'),
      RoomType.kitchen: ('厨房', 'Ас үй'),
      RoomType.bathroom: ('卫生间', 'Жуыну бөлмесі'),
      RoomType.dining: ('餐厅', 'Асхана'),
      RoomType.hall: ('门厅', 'Кіреберіс'),
      RoomType.corridor: ('走廊', 'Дәліз'),
      RoomType.storage: ('储藏间', 'Қойма'),
      RoomType.boiler: ('锅炉房', 'Қазандық'),
      RoomType.custom: ('房间', 'Бөлме'),
    }[type]!;
    return zh ? names.$1 : names.$2;
  }

  Future<void> mergeRoom(Room room) async {
    final adjacent = floor.rooms
        .where((r) =>
            r.id != room.id &&
            isConnected({
              ...regionCells(base.axes, room.regions).cells,
              ...regionCells(base.axes, r.regions).cells
            }))
        .toList();
    if (adjacent.isEmpty) {
      notify(tr3('没有可以合并的相邻房间', 'Біріктіретін көрші бөлме жоқ',
          'Нет соседней комнаты для объединения',
          'No neighbouring room to merge with', ky: 'Бириктире турган коңшу бөлмө жок', uz: 'Birlashtirish uchun qoʻshni xona yoʻq'));
      return;
    }
    final target = await showMotionSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final other in adjacent)
                ListTile(contentPadding: tilePad, 
                    title: Text(displayRoomName(other)),
                    onTap: () => Navigator.pop(context, other.id)),
            ])));
    if (target == null || !mounted) return;
    final arguments = <String, dynamic>{'roomIdA': room.id, 'roomIdB': target};
    final preview = executeCommand(
        presentState,
        DesignCommand('MergeRooms', arguments),
        CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
    if (preview is NeedsResolution && mounted) {
      final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(tr3('合并这两个房间？', 'Екі бөлмені біріктіру керек пе?',
                      'Объединить две комнаты?',
                      'Merge the two rooms?', ky: 'Эки бөлмөнү бириктиресизби?', uz: 'Ikki xona birlashtirilsinmi?')),
                  content: Text(coreMessage(preview.conflict.message)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr3(
                            '合并并移除这些门窗',
                            'Біріктіріп, есік-терезелерді алып тастау',
                            'Объединить и убрать окна и двери',
                            'Merge and remove windows and doors', ky: 'Бириктирип, терезе-эшиктерди алып салуу', uz: 'Birlashtirib, deraza va eshiklarni olib tashlash')))
                  ]));
      if (proceed != true) return;
      arguments['deleteHostedObjects'] = true;
    }
    action('MergeRooms', arguments);
  }

  String openingKindName(Opening o) => switch (o) {
        DoorOpening() => tr3('门', 'Есік', 'Дверь', 'Door', ky: 'Эшик', uz: 'Eshik'),
        WindowOpening() => tr3('窗', 'Терезе', 'Окно', 'Window', ky: 'Терезе', uz: 'Deraza'),
        SlidingOpening() => tr3('推拉门', 'Сырғымалы есік', 'Раздвижная дверь', 'Sliding door', ky: 'Жылма эшик', uz: 'Surma eshik'),
      };

  String facingName(Facing f) => switch (f) {
        Facing.north => tr3('北', 'солтүстік', 'север', 'north', ky: 'түндүк', uz: 'shimol'),
        Facing.east => tr3('东', 'шығыс', 'восток', 'east', ky: 'чыгыш', uz: 'sharq'),
        Facing.south => tr3('南', 'оңтүстік', 'юг', 'south', ky: 'түштүк', uz: 'janub'),
        Facing.west => tr3('西', 'батыс', 'запад', 'west', ky: 'батыш', uz: 'gʻarb'),
      };

  /// "Bedroom 1 · north window", unless the user named it.
  String openingLabel(OpeningPlacement p, int floorIdx) {
    final custom = history.present.extras.openingLabels[p.opening.id];
    if (custom != null) return custom;
    final g = derived.floors[floorIdx];
    final f = history.present.floors[floorIdx];
    final (a, b) = roomsBeside(p, g.base);
    final rooms = [a, b]
        .whereType<String>()
        .map((id) => f.rooms.where((r) => r.id == id).firstOrNull)
        .whereType<Room>()
        .toList()
      ..sort((x, y) {
        double area(Room r) =>
            g.base.roomGeometry.firstWhere((s) => s.id == r.id).clearArea;
        return area(x).compareTo(area(y));
      });
    final kind = openingKindName(p.opening);
    if (p.opening.id == history.present.mainEntranceOpeningId) {
      return tr3('入户门', 'Кіреберіс есігі', 'Входная дверь', 'Front door', ky: 'Кире бериш эшик', uz: 'Kirish eshigi');
    }
    final facing = facingOf(p, g.base, history.present.footprint.northAngleDeg);
    final room = rooms.isEmpty ? null : displayRoomName(rooms.first);
    if (facing != null) {
      return room == null
          ? '${facingName(facing)} $kind'
          : isWestern
              ? '$room · ${facingName(facing)} ${kind.toLowerCase()}'
              : '$room ${facingName(facing)}$kind';
    }
    if (rooms.length == 2) {
      return isWestern
          ? '${displayRoomName(rooms[0])} – ${displayRoomName(rooms[1])} ${kind.toLowerCase()}'
          : '${displayRoomName(rooms[0])}-${displayRoomName(rooms[1])} $kind';
    }
    return room == null
        ? kind
        : (isWestern ? '$room ${kind.toLowerCase()}' : '$room $kind');
  }

  Widget openingCard(OpeningPlacement p) {
    final t = Tokens.of(context);
    final o = p.opening;
    final chain = resolveAnchor(base.axes, o.anchor).chain;
    final offset = chain == null ? null : (p.start - chain.startPos).round();
    final vertical = chain?.carrier.dir == AxisDir.V;
    final facing = facingOf(p, base, history.present.footprint.northAngleDeg);
    final isDoor = o is DoorOpening;
    Future<void> resize(String field, String title, int value) async {
      final v = await askMm(title, value);
      if (v != null) action('ResizeOpening', {'openingId': o.id, field: v});
    }

    return panel(
        title: titleText(openingLabel(p, floorIndex), onTap: () async {
          final value = await askText(
              tr3('名称 / 位置', 'Атауы / орны', 'Название / расположение', 'Name / location', ky: 'Аталышы / жайгашкан жери', uz: 'Nomi / joylashuvi'),
              history.present.extras.openingLabels[o.id] ?? '');
          if (value != null) {
            action('SetOpeningLabel', {'openingId': o.id, 'value': value});
          }
        }, tag: TagPill(openingKindName(o), isDoor ? t.accent : t.chk)),
        subtitle: tr3(
            '也可以直接在图上拖动它，换位置或换到别的墙上',
            'Сызбада сүйреп, орнын не қабырғасын ауыстыруға болады',
            'Можно перетащить на чертеже, чтобы сменить место или стену',
            'Drag on the drawing to change its place or wall', ky: 'Ордун же дубалын өзгөртүү үчүн чиймеде сүйрөңүз', uz: 'Joyini yoki devorini oʻzgartirish uchun chizmada suring'),
        summary: '${o.width} × ${o.height} $unitMm',
        deleteLabel: tr3('删除${openingKindName(o)}', '${openingKindName(o)} жою',
            'Удалить: ${openingKindName(o)}',
            'Delete: ${openingKindName(o)}', ky: 'Өчүрүү: ${openingKindName(o)}', uz: 'Oʻchirish: ${openingKindName(o)}'),
        onDelete: () {
          final before = history.present;
          update(clearSelection);
          action('DeleteOpening', {'openingId': o.id});
          if (history.present != before) {
            notify(
                tr3('已删除${openingKindName(o)}', '${openingKindName(o)} жойылды',
                    'Удалено: ${openingKindName(o)}',
                    'Deleted: ${openingKindName(o)}', ky: 'Өчүрүлдү: ${openingKindName(o)}', uz: 'Oʻchirildi: ${openingKindName(o)}'),
                undo: undo);
          }
        },
        actions: [
          for (final kind in OpeningKind.values)
            if (kind != o.kind)
              Btn(
                  label: '${tr3('换成', '→', '→', '→', ky: '→', uz: '→')} ${switch (kind) {
                    OpeningKind.door => tr3('门', 'есік', 'дверь', 'door', ky: 'эшик', uz: 'eshik'),
                    OpeningKind.window => tr3('窗', 'терезе', 'окно', 'window', ky: 'терезе', uz: 'deraza'),
                    OpeningKind.sliding =>
                      tr3('推拉门', 'сырғымалы есік', 'раздвижная дверь', 'sliding door', ky: 'жылма эшик', uz: 'surma eshik'),
                  }}',
                  icon: Icons.swap_horiz,
                  onPressed: () => action(
                      'SetOpeningKind', {'openingId': o.id, 'kind': kind})),
          if (o is DoorOpening) ...[
            Btn(
                label: tr3('门轴换边', 'Топсаны ауыстыру', 'Перевесить петли', 'Swap the hinges', ky: 'Илгичтерди алмаштыруу', uz: 'Ilgaklarni almashtirish'),
                icon: Icons.flip,
                onPressed: () => action('FlipDoor', {
                      'openingId': o.id,
                      'hinge': o.hinge == Hinge.start ? 'end' : 'start'
                    })),
            Btn(
                label: tr3(
                    '换开门方向', 'Ашылу бағыты', 'Сменить направление открывания', 'Switch the swing direction', ky: 'Ачылуу багытын алмаштыруу', uz: 'Ochilish yoʻnalishini almashtirish'),
                icon: Icons.swap_vert,
                onPressed: () => action('FlipDoor', {
                      'openingId': o.id,
                      'opensTo': o.opensTo == OpeningSide.positiveSide
                          ? 'negativeSide'
                          : 'positiveSide'
                    })),
            if (history.present.mainEntranceOpeningId != o.id)
              Btn(
                  label:
                      tr3('设为大门', 'Басты кіреберіс', 'Сделать главным входом', 'Make it the main entrance', ky: 'Негизги кире бериш кылуу', uz: 'Asosiy kirish qilish'),
                  icon: Icons.home_outlined,
                  onPressed: () =>
                      action('SetMainEntrance', {'openingId': o.id})),
          ],
          Btn(
              label: tr3('放到墙中间', 'Қабырға ортасына', 'По центру стены', 'Centre on the wall', ky: 'Дубалдын ортосуна коюу', uz: 'Devor oʻrtasiga joylash'),
              icon: Icons.format_align_center,
              onPressed: () => action('MoveOpening', {
                    'openingId': o.id,
                    'position': {'type': 'center'}
                  })),
        ],
        children: [
          KvGrid([
            Kv('${o.width}', tr3('宽 mm', 'Ені, мм', 'Ширина, мм', 'Width, mm', ky: 'Туурасы, мм', uz: 'Eni, mm'),
                onTap: () =>
                    resize('width', tr3('宽度', 'Ені', 'Ширина', 'Width', ky: 'Туурасы', uz: 'Eni'), o.width)),
            Kv('${o.height}', tr3('高 mm', 'Биіктігі, мм', 'Высота, мм', 'Height, mm', ky: 'Бийиктиги, мм', uz: 'Balandligi, mm'),
                onTap: () => resize(
                    'height', tr3('高度', 'Биіктігі', 'Высота', 'Height', ky: 'Бийиктиги', uz: 'Balandligi'), o.height)),
            if (!isDoor)
              Kv('${o.sill}', tr3('窗台 mm', 'Терезе алды, мм', 'Подоконник, мм', 'Sill, mm', ky: 'Терезе алды, мм', uz: 'Deraza tokchasi, mm'),
                  onTap: () => resize(
                      'sill',
                      tr3('窗台高度', 'Терезе алды', 'Высота подоконника', 'Sill height', ky: 'Терезе алдынын бийиктиги', uz: 'Deraza tokchasi balandligi'),
                      o.sill)),
            Kv(
                offset == null ? '—' : '$offset',
                vertical
                    ? tr3(
                        '距墙下端 mm', 'Төменгі шетінен, мм', 'От нижнего края, мм', 'From the bottom edge, mm', ky: 'Ылдыйкы четинен, мм', uz: 'Pastki chetidan, mm')
                    : tr3('距墙左端 mm', 'Сол шетінен, мм', 'От левого края, мм', 'From the left edge, mm', ky: 'Сол четинен, мм', uz: 'Chap chetidan, mm'),
                onTap: () async {
              final v = await askMm(
                  vertical
                      ? tr3('距墙下端', 'Төменгі шетінен', 'От нижнего конца стены', 'From the bottom end of the wall', ky: 'Дубалдын ылдыйкы учунан', uz: 'Devorning pastki uchidan')
                      : tr3('距墙左端', 'Сол шетінен', 'От левого края', 'From the left edge', ky: 'Сол четинен', uz: 'Chap chetidan'),
                  offset ?? 0);
              if (v != null) {
                action('MoveOpening', {
                  'openingId': o.id,
                  'position': {'type': 'fromStart', 'd': v}
                });
              }
            }),
            Kv(
                facing == null
                    ? tr3('室内', 'Ішкі', 'Внутри', 'Inside', ky: 'Ичи', uz: 'Ichkari')
                    : facingName(facing),
                tr3('朝向', 'Бағыты', 'Ориентация', 'Orientation', ky: 'Багыты', uz: 'Yoʻnalishi')),
            Kv(dec((o.width * o.height / 1e6).toStringAsFixed(2)),
                '${tr3('面积', 'Ауданы', 'Площадь', 'Area', ky: 'Аянт', uz: 'Maydon')} $unitM2'),
          ]),
        ]);
  }

  Widget furnitureCard(FurnitureItem f) {
    final t = Tokens.of(context);
    final name = f.label ?? furnitureName(f.kind);
    Future<void> edit(String field, String title, int value) async {
      final v = await askMm(title, value);
      if (v != null) action('UpdateFurniture', {'furnitureId': f.id, field: v});
    }

    final textile = const {
      FurnitureKind.rug,
      FurnitureKind.wallRug,
      FurnitureKind.korpe,
      FurnitureKind.cushion,
      FurnitureKind.sandyq,
    }.contains(f.kind);
    return panel(
        title: titleText(name, onTap: () async {
          final value =
              await askText(tr3('名称', 'Атауы', 'Наименование', 'Name', ky: 'Аталышы', uz: 'Nomi'), f.label ?? '');
          if (value != null) {
            action('UpdateFurniture', {'furnitureId': f.id, 'label': value});
          }
        }, tag: TagPill(furnitureName(f.kind), t.rug)),
        subtitle: tr3(
            '拖动移动 · 拖右下角圆点改大小 · 拖上方圆圈旋转',
            'Сүйреп жылжытыңыз · оң төменгі нүкте — өлшем · жоғарғы шеңбер — бұру',
            'Перетащите, чтобы переместить · правая нижняя точка — размер · верхний кружок — поворот',
            'Drag to move · bottom-right dot resizes · top circle rotates', ky: 'Жылдыруу үчүн сүйрөңүз · оң ылдыйкы чекит өлчөмүн өзгөртөт · үстүнкү тегерек бурат', uz: 'Surish uchun suring · oʻng pastki nuqta oʻlchamni oʻzgartiradi · tepadagi doira aylantiradi'),
        summary: '${f.width} × ${f.depth} × ${f.height} $unitMm',
        deleteLabel: tr3('删除$name', '$name жою', 'Удалить: $name', 'Delete: $name', ky: 'Өчүрүү: $name', uz: 'Oʻchirish: $name'),
        onDelete: () {
          update(clearSelection);
          if (action('DeleteFurniture', {'furnitureId': f.id}) is! Applied) {
            return;
          }
          notify(tr3('已删除$name', '$name жойылды', 'Удалено: $name', 'Deleted: $name', ky: 'Өчүрүлдү: $name', uz: 'Oʻchirildi: $name'),
              undo: undo);
        },
        actions: [
          Btn(
              label: tr3('旋转 90°', '90° бұру', 'Повернуть на 90°', 'Rotate 90°', ky: '90° буруу', uz: '90° burish'),
              icon: Icons.rotate_90_degrees_ccw,
              onPressed: () =>
                  action('RotateFurniture', {'furnitureId': f.id})),
          Btn(
              label: tr3('复制', 'Көшіру', 'Копировать', 'Copy', ky: 'Көчүрүү', uz: 'Nusxalash'),
              icon: Icons.copy_all_outlined,
              onPressed: () {
                final id = const Uuid().v4();
                action('AddFurniture', {
                  'id': id,
                  'floorId': f.floorId,
                  'kind': f.kind,
                  'x': f.x + 300,
                  'y': f.y - 300,
                  'width': f.width,
                  'depth': f.depth,
                  'height': f.height,
                  'elevation': f.elevation,
                  'variant': f.variant,
                  if (f.label != null) 'label': f.label,
                });
                update(() => selectedFurnitureId = id);
              }),
          Btn(
              label: tr3('换类型', 'Түрін ауыстыру', 'Сменить тип', 'Change the type', ky: 'Түрүн өзгөртүү', uz: 'Turini oʻzgartirish'),
              icon: Icons.category_outlined,
              onPressed: () async {
                final kind = await pickFurnitureKind();
                if (kind != null) {
                  action(
                      'UpdateFurniture', {'furnitureId': f.id, 'kind': kind});
                }
              }),
        ],
        children: [
          KvGrid([
            Kv('${f.width}', tr3('宽 mm', 'Ені, мм', 'Ширина, мм', 'Width, mm', ky: 'Туурасы, мм', uz: 'Eni, mm'),
                onTap: () =>
                    edit('width', tr3('宽度', 'Ені', 'Ширина', 'Width', ky: 'Туурасы', uz: 'Eni'), f.width)),
            Kv('${f.depth}', tr3('深 mm', 'Тереңдігі, мм', 'Глубина, мм', 'Depth, mm', ky: 'Тереңдиги, мм', uz: 'Chuqurligi, mm'),
                onTap: () =>
                    edit('depth', tr3('深度', 'Тереңдігі', 'Глубина', 'Depth', ky: 'Тереңдиги', uz: 'Chuqurligi'), f.depth)),
            Kv('${f.height}', tr3('高 mm', 'Биіктігі, мм', 'Высота, мм', 'Height, mm', ky: 'Бийиктиги, мм', uz: 'Balandligi, mm'),
                onTap: () =>
                    edit('height', tr3('高度', 'Биіктігі', 'Высота', 'Height', ky: 'Бийиктиги', uz: 'Balandligi'), f.height)),
            Kv('${f.elevation}', tr3('离地 mm', 'Еденнен, мм', 'От пола, мм', 'From the floor, mm', ky: 'Полдон, мм', uz: 'Poldan, mm'),
                onTap: () => edit(
                    'elevation',
                    tr3('离地高度', 'Еденнен биіктігі', 'Высота от пола', 'Height from the floor', ky: 'Полдон бийиктиги', uz: 'Poldan balandligi'),
                    f.elevation)),
            Kv('${f.x}', tr3('距左墙 mm', 'Сол жақтан, мм', 'Отступ слева, мм', 'Left offset, mm', ky: 'Солдон аралыгы, мм', uz: 'Chapdan masofa, mm'),
                onTap: () =>
                    edit('x', tr3('距左侧外边', 'Сол жақтан', 'Отступ слева', 'Left offset', ky: 'Солдон аралыгы', uz: 'Chapdan masofa'), f.x)),
            Kv('${f.y}', tr3('距下墙 mm', 'Төменнен, мм', 'Отступ снизу, мм', 'Bottom offset, mm', ky: 'Ылдыйдан аралыгы, мм', uz: 'Pastdan masofa, mm'),
                onTap: () =>
                    edit('y', tr3('距下侧外边', 'Төменнен', 'Отступ снизу', 'Bottom offset', ky: 'Ылдыйдан аралыгы', uz: 'Pastdan masofa'), f.y)),
          ]),
          if (textile)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 6, children: [
                  Text(tr3('花色', 'Өрнек', 'Узор', 'Pattern', ky: 'Оюм-чийим', uz: 'Naqsh'),
                      style: TextStyle(fontSize: 12, color: t.muted)),
                  for (var v = 0; v < 3; v++)
                    ChoiceChip(
                        label: Text('${v + 1}'),
                        visualDensity: VisualDensity.compact,
                        selected: f.variant == v,
                        onSelected: (_) => action('UpdateFurniture',
                            {'furnitureId': f.id, 'variant': v})),
                ])),
        ]);
  }

  /// Asks where room areas are measured to, for the whole project.
  Future<void> chooseAreaBasis() async {
    final now = history.present.extras.areaBasis;
    final picked = await showDialog<AreaBasis>(
        context: context,
        builder: (context) => SimpleDialog(
                title: Text(tr3(
                    '房间面积怎么算', 'Бөлме ауданын есептеу', 'Как считать площадь', 'How to measure room area', ky: 'Аянтты кантип эсептөө', uz: 'Maydonni qanday hisoblash')),
                children: [
                  for (final b in AreaBasis.values)
                    SimpleDialogOption(
                        key: ValueKey('area-basis-${b.name}'),
                        onPressed: () => Navigator.pop(context, b),
                        child: Row(children: [
                          Icon(
                              b == now
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(areaBasisName(b)),
                                Text(areaBasisHint(b),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Tokens.of(context).muted)),
                              ]))
                        ])),
                ]));
    if (picked == null || picked == now || !mounted) return;
    action('SetAreaBasis', {'basis': picked});
  }

  /// Summary of the whole design when nothing is selected.
  Widget houseCard() {
    final t = Tokens.of(context);
    final doc = history.present;
    final g = derived.floors[floorIndex];
    final basis = doc.extras.areaBasis;
    final interior = g.base.roomGeometry.fold(0.0, (s, r) => s + r.area(basis));
    final openings = g.openings.length;
    return InfoCard(
        title: tr3('整栋房屋', 'Бүкіл үй', 'Весь дом', 'Whole house', ky: 'Бүт үй', uz: 'Butun uy'),
        subtitle: tr3(
            '点房间、门窗或家具查看和修改',
            'Бөлмені, есік-терезені не жиһазды басып өзгертіңіз',
            'Нажмите на комнату, окно, дверь или мебель, чтобы изменить',
            'Tap a room, window, door or furniture to edit it', ky: 'Түзөтүү үчүн бөлмөнү, терезени, эшикти же эмеректи басыңыз', uz: 'Tahrirlash uchun xona, deraza, eshik yoki mebelga bosing'),
        children: [
          KvGrid([
            Kv('${dec((doc.footprint.width * doc.footprint.depth / 1e6).toStringAsFixed(1))} $unitM2',
                tr3('建筑面积', 'Құрылыс ауданы', 'Общая площадь', 'Total area', ky: 'Жалпы аянт', uz: 'Umumiy maydon'),
                onTap: footprintOptions),
            Kv('${dec((interior / 1e6).toStringAsFixed(1))} $unitM2',
                '${displayFloorName(floor.name)} · ${areaBasisName(basis)}',
                onTap: chooseAreaBasis),
            Kv('${floor.rooms.length}', tr3('房间', 'Бөлмелер', 'Комнаты', 'Rooms', ky: 'Бөлмөлөр', uz: 'Xonalar')),
            Kv('$openings', tr3('门窗', 'Есік-терезе', 'Окна и двери', 'Windows and doors', ky: 'Терезелер жана эшиктер', uz: 'Derazalar va eshiklar')),
            Kv('${floor.height}',
                tr3('层高 mm', 'Қабат биіктігі, мм', 'Высота этажа, мм', 'Floor height, mm', ky: 'Кабаттын бийиктиги, мм', uz: 'Qavat balandligi, mm'),
                onTap: () async {
              final v = await askMm(
                  tr3('层高', 'Қабат биіктігі', 'Высота этажа', 'Floor height', ky: 'Кабаттын бийиктиги', uz: 'Qavat balandligi'), floor.height);
              if (v != null) {
                action('SetFloorHeight', {'floorId': floor.id, 'value': v});
              }
            }),
            Kv('${doc.defaults.outerWallThickness}',
                tr3('外墙厚 mm', 'Сыртқы қабырға, мм', 'Наружная стена, мм', 'Outer wall, mm', ky: 'Сырткы дубал, мм', uz: 'Tashqi devor, mm'),
                onTap: () async {
              final v = await askMm(
                  tr3('外墙厚度', 'Сыртқы қабырға қалыңдығы',
                      'Толщина наружной стены',
                      'Outer wall thickness', ky: 'Сырткы дубалдын калыңдыгы', uz: 'Tashqi devor qalinligi'),
                  doc.defaults.outerWallThickness);
              if (v != null) {
                action(
                    'SetDefault', {'field': 'outerWallThickness', 'value': v});
              }
            }),
            Kv(roofStyleName(roofStyle), tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom'),
                onTap: chooseRoof),
          ]),
          if (showUtilities) utilitySummary(),
          for (final room in floor.rooms)
            InkWell(
                onTap: () => update(() {
                      clearSelection();
                      clearWallSelection();
                      selectedRoomId = room.id;
                      panelCollapsed = false;
                    }),
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(
                          child: Text(displayRoomName(room),
                              style: const TextStyle(fontSize: 13))),
                      Text(
                          '${dec((g.base.roomGeometry.firstWhere((r) => r.id == room.id).area(doc.extras.areaBasis) / 1e6).toStringAsFixed(1))} $unitM2',
                          style: mono(color: t.muted)),
                    ]))),
        ]);
  }
}

String areaBasisName(AreaBasis b) => switch (b) {
      AreaBasis.clear => tr3('室内净面积', 'ішкі таза аудан', 'чистая площадь', 'net interior area', ky: 'ички таза аянт', uz: 'ichki sof maydon'),
      AreaBasis.centre =>
        tr3('墙中线面积', 'қабырға осі бойынша аудан', 'площадь по осям стен', 'area to wall centrelines', ky: 'дубалдардын огу боюнча аянт', uz: 'devor oʻqlari boʻyicha maydon'),
      AreaBasis.outer =>
        tr3('含外墙面积', 'сыртқы қабырғамен аудан', 'площадь с наружными стенами', 'area including outer walls', ky: 'сырткы дубалдар менен аянт', uz: 'tashqi devorlar bilan maydon'),
    };

String areaBasisHint(AreaBasis b) => switch (b) {
      AreaBasis.clear => tr3('量到墙的完成面，是能用的地面',
          'Қабырғаның әрленген бетіне дейін', 'До чистовой поверхности стен', 'To the finished wall surface', ky: 'Дубалдын бүткөн бетине чейин', uz: 'Devorning pardozlangan yuzasigacha'),
      AreaBasis.centre =>
        tr3('量到四周墙的中线', 'Қабырғалардың осіне дейін', 'До осей окружающих стен', 'To the centrelines of the surrounding walls', ky: 'Айланадагы дубалдардын огуна чейин', uz: 'Atrofdagi devorlar oʻqigacha'),
      AreaBasis.outer => tr3(
          '内墙量到中线，外墙量到外皮',
          'Ішкі қабырға осіне, сыртқы қабырғаның сыртына дейін',
          'До осей внутренних и наружной грани наружных стен', 'To inner wall centrelines and the outer face of outer walls', ky: 'Ички дубалдардын огуна жана сырткы дубалдардын сырткы бетине чейин', uz: 'Ichki devorlar oʻqigacha va tashqi devorlarning tashqi yuzasigacha'),
    };
