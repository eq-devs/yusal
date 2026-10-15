part of '../house_editor.dart';

/// Cards for the current selection, after the room card of the drafting
/// page: name, the other language, a grid of figures, a note — every value
/// can be tapped to edit.
extension _SelectionCards on _HouseEditorState {
  Widget? selectionCard() {
    if (view3d) return null;
    final g = derived.floors[floorIndex];
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

  bool get wideLayout => !compact && MediaQuery.sizeOf(context).width >= 1000;

  /// Card chrome: on phones it floats over the bottom of the plan, can fold
  /// to one line and scrolls when tall.
  Widget panel(
      {required Widget title,
      String? subtitle,
      required List<Widget> children,
      String? summary}) {
    final t = Tokens.of(context);
    final wide = wideLayout;
    final head = Row(children: [
      Expanded(child: title),
      if (!wide)
        IconButton(
            tooltip: panelCollapsed ? tr('展开', 'Ашу') : tr('收起', 'Жию'),
            visualDensity: VisualDensity.compact,
            onPressed: () => update(() => panelCollapsed = !panelCollapsed),
            icon: Icon(
                panelCollapsed ? Icons.expand_less : Icons.expand_more,
                size: 20)),
      IconButton(
          tooltip: tr('关闭', 'Жабу'),
          visualDensity: VisualDensity.compact,
          onPressed: () => update(clearSelection),
          icon: const Icon(Icons.close, size: 18)),
    ]);
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          if (subtitle != null)
            Text(subtitle, style: TextStyle(fontSize: 12, color: t.muted)),
          if (!wide && panelCollapsed && summary != null)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(size: 12, color: t.muted))),
          if (wide || !panelCollapsed) ...children,
        ]);
    final sheet = Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(10),
            boxShadow: wide
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12)
                  ]),
        child: wide
            ? body
            : ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: math.max(140, canvasSize.height * 0.58)),
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
        cancel: tr('取消', 'Болдырмау'),
        ok: tr('确定', 'Жарайды'),
        number: true,
        suffix: unitMm);
    final parsed = double.tryParse((text ?? '').replaceAll(',', '.'));
    if (parsed == null || !parsed.isFinite) return null;
    return parsed.round();
  }

  Future<String?> askText(String title, String value,
          {bool multiline = false}) =>
      promptText(context,
          title: title,
          initial: value,
          cancel: tr('取消', 'Болдырмау'),
          ok: tr('确定', 'Жарайды'),
          multiline: multiline);

  Widget roomCard(Room room) {
    final t = Tokens.of(context);
    final stats = roomStats(room, derived.floors[floorIndex], floor.height);
    final info = history.present.extras.rooms[room.id] ?? const RoomInfo();
    final name = displayRoomName(room);
    final other = isKk
        ? otherLanguageType(room.type, zh: true)
        : otherLanguageType(room.type, zh: false);
    final ratio = stats.floorPerWindow;
    final habitable = room.type == RoomType.bedroom ||
        room.type == RoomType.living ||
        room.type == RoomType.dining;
    final area = stats.area / 1e6;
    final label = info.labelArea == null ? null : info.labelArea! / 100;
    return panel(
        title: titleText(name,
            onTap: () async {
              final value = await askText(tr('房间名称', 'Бөлме атауы'), name);
              if (value != null && value.trim().isNotEmpty)
                action('RenameRoom', {'roomId': room.id, 'value': value.trim()});
            },
            tag: TagPill(roomTypeName(room.type), t.chk)),
        subtitle: other,
        summary:
            '${stats.clearWidth.round()} × ${stats.clearDepth.round()} · ${dec(area.toStringAsFixed(1))} $unitM2',
        children: [
          KvGrid([
            Kv('${stats.clearWidth.round()} × ${stats.clearDepth.round()}',
                tr('净尺寸 mm', 'Таза өлшем, мм')),
            Kv('${dec(area.toStringAsFixed(1))} $unitM2',
                tr('按尺寸计算', 'Өлшем бойынша есеп')),
            Kv(label == null ? '—' : '${dec(label.toStringAsFixed(label % 1 == 0 ? 0 : 1))} $unitM2',
                tr('图纸标注', 'Сызбадағы белгі'), onTap: () async {
              final text = await promptText(context,
                  title: tr('图纸标注面积', 'Сызбадағы аудан'),
                  initial: label == null ? '' : '$label',
                  cancel: tr('取消', 'Болдырмау'),
                  ok: tr('确定', 'Жарайды'),
                  number: true,
                  suffix: unitM2);
              if (text == null) return;
              final v = double.tryParse(text.replaceAll(',', '.'));
              action('SetRoomInfo', {
                'roomId': room.id,
                'labelArea': v == null || text.trim().isEmpty
                    ? null
                    : (v * 100).round()
              });
            }),
            Kv(
                '${stats.windows.length} ${tr('扇', 'дана')} · ${dec((stats.windowArea / 1e6).toStringAsFixed(2))} $unitM2',
                tr('窗面积', 'Терезе ауданы')),
            Kv(
                ratio == null ? '1 : ∞' : '1 : ${dec(ratio.toStringAsFixed(1))}',
                tr('窗地比 (居室宜 ≥ 1:7)', 'Терезе/еден (тұрғын ≥ 1:7)'),
                color: habitable && (ratio == null || ratio > 7) ? t.warn : null),
            Kv('${dec((stats.volume / 1e9).toStringAsFixed(1))} $unitM3',
                '${tr('房间容积 (层高', 'Бөлме көлемі (биіктігі')} ${m2dp(floor.height)})'),
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
                    tr('房间说明', 'Бөлме туралы жазба'), info.note,
                    multiline: true);
                if (value != null)
                  action('SetRoomInfo', {'roomId': room.id, 'note': value});
              },
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                      info.note.isEmpty
                          ? tr('＋ 添加说明（布置、采光、注意事项…）',
                              '＋ Жазба қосу (жиһаз, жарық, ескерту…)')
                          : info.note,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: info.note.isEmpty ? t.accent : t.muted)))),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr('走进去看看', 'Ішіне кіріп көру'),
                icon: Icons.directions_walk,
                onPressed: () => walkInto(room.id)),
            Btn(
                label: tr('与相邻房间合并', 'Көршімен біріктіру'),
                icon: Icons.join_inner,
                onPressed: () => mergeRoom(room)),
            Btn(
                label: tr('删除房间', 'Бөлмені жою'),
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
                    if (history.commit(
                        withExtras(updated, history.present.extras))) changed();
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
      notify(tr('没有可以合并的相邻房间', 'Біріктіретін көрші бөлме жоқ'));
      return;
    }
    final target = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final other in adjacent)
                ListTile(
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
                  title: Text(tr('合并这两个房间？', 'Екі бөлмені біріктіру керек пе?')),
                  content: Text(coreMessage(preview.conflict.message)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('取消', 'Болдырмау'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr('合并并移除这些门窗',
                            'Біріктіріп, есік-терезелерді алып тастау')))
                  ]));
      if (proceed != true) return;
      arguments['deleteHostedObjects'] = true;
    }
    action('MergeRooms', arguments);
  }

  String openingKindName(Opening o) => switch (o) {
        DoorOpening() => tr('门', 'Есік'),
        WindowOpening() => tr('窗', 'Терезе'),
        SlidingOpening() => tr('推拉门', 'Сырғымалы есік'),
      };

  String facingName(Facing f) => switch (f) {
        Facing.north => tr('北', 'солтүстік'),
        Facing.east => tr('东', 'шығыс'),
        Facing.south => tr('南', 'оңтүстік'),
        Facing.west => tr('西', 'батыс'),
      };

  /// "Bedroom 1 · north window", unless the user named it.
  String openingLabel(OpeningPlacement p, int floorIdx) {
    final custom = history.present.extras.openingLabels[p.opening.id];
    if (custom != null) return custom;
    final g = derived.floors[floorIdx], f = history.present.floors[floorIdx];
    final (a, b) = roomsBeside(p, g.base);
    final rooms = [a, b]
        .whereType<String>()
        .map((id) => f.rooms.where((r) => r.id == id).firstOrNull)
        .whereType<Room>()
        .toList()
      ..sort((x, y) {
        double area(Room r) => g.base.roomGeometry
            .firstWhere((s) => s.id == r.id)
            .clearArea;
        return area(x).compareTo(area(y));
      });
    final kind = openingKindName(p.opening);
    if (p.opening.id == history.present.mainEntranceOpeningId)
      return tr('入户门', 'Кіреберіс есігі');
    final facing = facingOf(p, g.base, history.present.footprint.northAngleDeg);
    final room = rooms.isEmpty ? null : displayRoomName(rooms.first);
    if (facing != null)
      return room == null
          ? '${facingName(facing)} $kind'
          : isKk
              ? '$room · ${facingName(facing)} ${kind.toLowerCase()}'
              : '$room ${facingName(facing)}$kind';
    if (rooms.length == 2)
      return isKk
          ? '${displayRoomName(rooms[0])} – ${displayRoomName(rooms[1])} ${kind.toLowerCase()}'
          : '${displayRoomName(rooms[0])}-${displayRoomName(rooms[1])} $kind';
    return room == null ? kind : (isKk ? '$room ${kind.toLowerCase()}' : '$room $kind');
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
        title: titleText(openingLabel(p, floorIndex),
            onTap: () async {
              final value = await askText(tr('名称 / 位置', 'Атауы / орны'),
                  history.present.extras.openingLabels[o.id] ?? '');
              if (value != null)
                action('SetOpeningLabel', {'openingId': o.id, 'value': value});
            },
            tag: TagPill(openingKindName(o), isDoor ? t.accent : t.chk)),
        subtitle: tr('也可以直接在图上拖动它，换位置或换到别的墙上',
            'Сызбада сүйреп, орнын не қабырғасын ауыстыруға болады'),
        summary: '${o.width} × ${o.height} $unitMm',
        children: [
          KvGrid([
            Kv('${o.width}', tr('宽 mm', 'Ені, мм'),
                onTap: () => resize('width', tr('宽度', 'Ені'), o.width)),
            Kv('${o.height}', tr('高 mm', 'Биіктігі, мм'),
                onTap: () => resize('height', tr('高度', 'Биіктігі'), o.height)),
            if (!isDoor)
              Kv('${o.sill}', tr('窗台 mm', 'Терезе алды, мм'),
                  onTap: () => resize('sill', tr('窗台高度', 'Терезе алды'), o.sill)),
            Kv(offset == null ? '—' : '$offset',
                vertical ? tr('距墙下端 mm', 'Төменгі шетінен, мм') : tr('距墙左端 mm', 'Сол шетінен, мм'),
                onTap: () async {
              final v = await askMm(
                  vertical ? tr('距墙下端', 'Төменгі шетінен') : tr('距墙左端', 'Сол шетінен'),
                  offset ?? 0);
              if (v != null)
                action('MoveOpening', {
                  'openingId': o.id,
                  'position': {'type': 'fromStart', 'd': v}
                });
            }),
            Kv(facing == null ? tr('室内', 'Ішкі') : facingName(facing),
                tr('朝向', 'Бағыты')),
            Kv(dec((o.width * o.height / 1e6).toStringAsFixed(2)),
                '${tr('面积', 'Ауданы')} $unitM2'),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr('放到墙中间', 'Қабырға ортасына'),
                icon: Icons.format_align_center,
                onPressed: () => action('MoveOpening', {
                      'openingId': o.id,
                      'position': {'type': 'center'}
                    })),
            for (final kind in OpeningKind.values)
              if (kind != o.kind)
                Btn(
                    label: '${tr('换成', '→')} ${switch (kind) {
                      OpeningKind.door => tr('门', 'есік'),
                      OpeningKind.window => tr('窗', 'терезе'),
                      OpeningKind.sliding => tr('推拉门', 'сырғымалы есік'),
                    }}',
                    icon: Icons.swap_horiz,
                    onPressed: () => action(
                        'SetOpeningKind', {'openingId': o.id, 'kind': kind})),
            if (o is DoorOpening) ...[
              Btn(
                  label: tr('门轴换边', 'Топсаны ауыстыру'),
                  icon: Icons.flip,
                  onPressed: () => action('FlipDoor', {
                        'openingId': o.id,
                        'hinge': o.hinge == Hinge.start ? 'end' : 'start'
                      })),
              Btn(
                  label: tr('换开门方向', 'Ашылу бағыты'),
                  icon: Icons.swap_vert,
                  onPressed: () => action('FlipDoor', {
                        'openingId': o.id,
                        'opensTo': o.opensTo == OpeningSide.positiveSide
                            ? 'negativeSide'
                            : 'positiveSide'
                      })),
              if (history.present.mainEntranceOpeningId != o.id)
                Btn(
                    label: tr('设为大门', 'Басты кіреберіс'),
                    icon: Icons.home_outlined,
                    onPressed: () =>
                        action('SetMainEntrance', {'openingId': o.id})),
            ],
            Btn(
                label: tr('删除', 'Жою'),
                icon: Icons.delete_outline,
                danger: true,
                onPressed: () {
                  final before = history.present;
                  update(clearSelection);
                  action('DeleteOpening', {'openingId': o.id});
                  if (history.present != before)
                    notify(tr('已删除${openingKindName(o)}', '${openingKindName(o)} жойылды'),
                        undo: undo);
                }),
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
        title: titleText(name,
            onTap: () async {
              final value = await askText(tr('名称', 'Атауы'), f.label ?? '');
              if (value != null)
                action('UpdateFurniture', {'furnitureId': f.id, 'label': value});
            },
            tag: TagPill(furnitureName(f.kind), t.rug)),
        subtitle: tr('拖动移动 · 拖右下角圆点改大小 · 拖上方圆圈旋转',
            'Сүйреп жылжытыңыз · оң төменгі нүкте — өлшем · жоғарғы шеңбер — бұру'),
        summary: '${f.width} × ${f.depth} × ${f.height} $unitMm',
        children: [
          KvGrid([
            Kv('${f.width}', tr('宽 mm', 'Ені, мм'),
                onTap: () => edit('width', tr('宽度', 'Ені'), f.width)),
            Kv('${f.depth}', tr('深 mm', 'Тереңдігі, мм'),
                onTap: () => edit('depth', tr('深度', 'Тереңдігі'), f.depth)),
            Kv('${f.height}', tr('高 mm', 'Биіктігі, мм'),
                onTap: () => edit('height', tr('高度', 'Биіктігі'), f.height)),
            Kv('${f.elevation}', tr('离地 mm', 'Еденнен, мм'),
                onTap: () => edit('elevation', tr('离地高度', 'Еденнен биіктігі'),
                    f.elevation)),
            Kv('${f.x}', tr('距左墙 mm', 'Сол жақтан, мм'),
                onTap: () => edit('x', tr('距左侧外边', 'Сол жақтан'), f.x)),
            Kv('${f.y}', tr('距下墙 mm', 'Төменнен, мм'),
                onTap: () => edit('y', tr('距下侧外边', 'Төменнен'), f.y)),
          ]),
          if (textile)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 6, children: [
                  Text(tr('花色', 'Өрнек'),
                      style: TextStyle(fontSize: 12, color: t.muted)),
                  for (var v = 0; v < 3; v++)
                    ChoiceChip(
                        label: Text('${v + 1}'),
                        visualDensity: VisualDensity.compact,
                        selected: f.variant == v,
                        onSelected: (_) => action('UpdateFurniture',
                            {'furnitureId': f.id, 'variant': v})),
                ])),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr('旋转 90°', '90° бұру'),
                icon: Icons.rotate_90_degrees_ccw,
                onPressed: () =>
                    action('RotateFurniture', {'furnitureId': f.id})),
            Btn(
                label: tr('复制', 'Көшіру'),
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
                label: tr('换类型', 'Түрін ауыстыру'),
                icon: Icons.category_outlined,
                onPressed: () async {
                  final kind = await pickFurnitureKind();
                  if (kind != null)
                    action('UpdateFurniture',
                        {'furnitureId': f.id, 'kind': kind});
                }),
            Btn(
                label: tr('删除', 'Жою'),
                icon: Icons.delete_outline,
                danger: true,
                onPressed: () {
                  update(clearSelection);
                  action('DeleteFurniture', {'furnitureId': f.id});
                  notify(tr('已删除$name', '$name жойылды'), undo: undo);
                }),
          ]),
        ]);
  }

  /// Summary of the whole design when nothing is selected.
  Widget houseCard() {
    final t = Tokens.of(context);
    final doc = history.present;
    final g = derived.floors[floorIndex];
    final interior = g.base.roomGeometry.fold(0.0, (s, r) => s + r.clearArea);
    final openings = g.openings.length;
    return InfoCard(
        title: tr('整栋房屋', 'Бүкіл үй'),
        subtitle: tr('点房间、门窗或家具查看和修改', 'Бөлмені, есік-терезені не жиһазды басып өзгертіңіз'),
        children: [
          KvGrid([
            Kv('${dec((doc.footprint.width * doc.footprint.depth / 1e6).toStringAsFixed(1))} $unitM2',
                tr('建筑面积', 'Құрылыс ауданы'),
                onTap: footprintOptions),
            Kv('${dec((interior / 1e6).toStringAsFixed(1))} $unitM2',
                '${displayFloorName(floor.name)} · ${tr('室内净面积', 'ішкі таза аудан')}'),
            Kv('${floor.rooms.length}', tr('房间', 'Бөлмелер')),
            Kv('$openings', tr('门窗', 'Есік-терезе')),
            Kv('${floor.height}', tr('层高 mm', 'Қабат биіктігі, мм'),
                onTap: () async {
              final v = await askMm(tr('层高', 'Қабат биіктігі'), floor.height);
              if (v != null)
                action('SetFloorHeight', {'floorId': floor.id, 'value': v});
            }),
            Kv('${doc.defaults.outerWallThickness}', tr('外墙厚 mm', 'Сыртқы қабырға, мм'),
                onTap: () async {
              final v = await askMm(tr('外墙厚度', 'Сыртқы қабырға қалыңдығы'),
                  doc.defaults.outerWallThickness);
              if (v != null)
                action('SetDefault', {'field': 'outerWallThickness', 'value': v});
            }),
          ]),
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
                          '${dec((g.base.roomGeometry.firstWhere((r) => r.id == room.id).clearArea / 1e6).toStringAsFixed(1))} $unitM2',
                          style: mono(size: 13, color: t.muted)),
                    ]))),
        ]);
  }
}
