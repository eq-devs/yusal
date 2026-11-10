part of '../house_editor.dart';

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
            tooltip: deleteLabel ?? tr3('删除', 'Жою', 'Удалить'),
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: t.crit)),
      if (!wide)
        IconButton(
            tooltip: panelCollapsed ? tr3('展开', 'Ашу', 'Развернуть') : tr3('收起', 'Жию', 'Свернуть'),
            visualDensity: VisualDensity.compact,
            onPressed: () => update(() => panelCollapsed = !panelCollapsed),
            icon: Icon(panelCollapsed ? Icons.expand_less : Icons.expand_more,
                size: 20)),
      IconButton(
          tooltip: tr3('关闭', 'Жабу', 'Закрыть'),
          visualDensity: VisualDensity.compact,
          onPressed: () => update(clearSelection),
          icon: const Icon(Icons.close, size: 18)),
    ]);
    final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
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
        cancel: tr3('取消', 'Болдырмау', 'Отмена'),
        ok: tr3('确定', 'Жарайды', 'ОК'),
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
          cancel: tr3('取消', 'Болдырмау', 'Отмена'),
          ok: tr3('确定', 'Жарайды', 'ОК'),
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
        title: titleText(name, onTap: () async {
          final value = await askText(tr3('房间名称', 'Бөлме атауы', 'Название комнаты'), name);
          if (value != null && value.trim().isNotEmpty)
            action('RenameRoom', {'roomId': room.id, 'value': value.trim()});
        }, tag: TagPill(roomTypeName(room.type), t.chk)),
        subtitle: other,
        summary:
            '${stats.clearWidth.round()} × ${stats.clearDepth.round()} · ${dec(area.toStringAsFixed(1))} $unitM2',
        children: [
          KvGrid([
            Kv('${stats.clearWidth.round()} × ${stats.clearDepth.round()}',
                tr3('净尺寸 mm', 'Таза өлшем, мм', 'Размеры в свету, мм')),
            Kv('${dec(area.toStringAsFixed(1))} $unitM2',
                tr3('按尺寸计算', 'Өлшем бойынша есеп', 'Расчёт по размерам')),
            Kv(
                label == null
                    ? '—'
                    : '${dec(label.toStringAsFixed(label % 1 == 0 ? 0 : 1))} $unitM2',
                tr3('图纸标注', 'Сызбадағы белгі', 'Подпись на чертеже'), onTap: () async {
              final text = await promptText(context,
                  title: tr3('图纸标注面积', 'Сызбадағы аудан', 'Площадь по чертежу'),
                  initial: label == null ? '' : '$label',
                  cancel: tr3('取消', 'Болдырмау', 'Отмена'),
                  ok: tr3('确定', 'Жарайды', 'ОК'),
                  number: true,
                  suffix: unitM2);
              if (text == null) return;
              final v = double.tryParse(text.replaceAll(',', '.'));
              action('SetRoomInfo', {
                'roomId': room.id,
                'labelArea':
                    v == null || text.trim().isEmpty ? null : (v * 100).round()
              });
            }),
            Kv('${stats.windows.length} ${tr3('扇', 'дана', 'шт.')} · ${dec((stats.windowArea / 1e6).toStringAsFixed(2))} $unitM2',
                tr3('窗面积', 'Терезе ауданы', 'Площадь окон')),
            Kv(ratio == null ? '1 : ∞' : '1 : ${dec(ratio.toStringAsFixed(1))}',
                tr3('窗地比 (居室宜 ≥ 1:7)', 'Терезе/еден (тұрғын ≥ 1:7)', 'Окна/пол (жилая ≥ 1:7)'),
                color:
                    habitable && (ratio == null || ratio > 7) ? t.warn : null),
            Kv('${dec((stats.volume / 1e9).toStringAsFixed(1))} $unitM3',
                '${tr3('房间容积 (层高', 'Бөлме көлемі (биіктігі', 'Объём комнаты (высота')} ${m2dp(floor.height)})'),
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
                    tr3('房间说明', 'Бөлме туралы жазба', 'Заметка о комнате'), info.note,
                    multiline: true);
                if (value != null)
                  action('SetRoomInfo', {'roomId': room.id, 'note': value});
              },
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                      info.note.isEmpty
                          ? tr3('＋ 添加说明（布置、采光、注意事项…）',
                              '＋ Жазба қосу (жиһаз, жарық, ескерту…)', '＋ Добавить заметку (мебель, свет, примечания…)')
                          : info.note,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: info.note.isEmpty ? t.accent : t.muted)))),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr3('走进去看看', 'Ішіне кіріп көру', 'Войти и осмотреться'),
                icon: Icons.directions_walk,
                onPressed: () => walkInto(room.id)),
            Btn(
                label: tr3('与相邻房间合并', 'Көршімен біріктіру', 'Объединить с соседней'),
                icon: Icons.join_inner,
                onPressed: () => mergeRoom(room)),
            Btn(
                label: tr3('删除房间', 'Бөлмені жою', 'Удалить комнату'),
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
      notify(tr3('没有可以合并的相邻房间', 'Біріктіретін көрші бөлме жоқ', 'Нет соседней комнаты для объединения'));
      return;
    }
    final target = await showMotionSheet<String>(
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
                  title:
                      Text(tr3('合并这两个房间？', 'Екі бөлмені біріктіру керек пе?', 'Объединить две комнаты?')),
                  content: Text(coreMessage(preview.conflict.message)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr3('合并并移除这些门窗',
                            'Біріктіріп, есік-терезелерді алып тастау', 'Объединить и убрать окна и двери')))
                  ]));
      if (proceed != true) return;
      arguments['deleteHostedObjects'] = true;
    }
    action('MergeRooms', arguments);
  }

  String openingKindName(Opening o) => switch (o) {
        DoorOpening() => tr3('门', 'Есік', 'Дверь'),
        WindowOpening() => tr3('窗', 'Терезе', 'Окно'),
        SlidingOpening() => tr3('推拉门', 'Сырғымалы есік', 'Раздвижная дверь'),
      };

  String facingName(Facing f) => switch (f) {
        Facing.north => tr3('北', 'солтүстік', 'север'),
        Facing.east => tr3('东', 'шығыс', 'восток'),
        Facing.south => tr3('南', 'оңтүстік', 'юг'),
        Facing.west => tr3('西', 'батыс', 'запад'),
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
        double area(Room r) =>
            g.base.roomGeometry.firstWhere((s) => s.id == r.id).clearArea;
        return area(x).compareTo(area(y));
      });
    final kind = openingKindName(p.opening);
    if (p.opening.id == history.present.mainEntranceOpeningId)
      return tr3('入户门', 'Кіреберіс есігі', 'Входная дверь');
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
    return room == null
        ? kind
        : (isKk ? '$room ${kind.toLowerCase()}' : '$room $kind');
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
          final value = await askText(tr3('名称 / 位置', 'Атауы / орны', 'Название / расположение'),
              history.present.extras.openingLabels[o.id] ?? '');
          if (value != null)
            action('SetOpeningLabel', {'openingId': o.id, 'value': value});
        }, tag: TagPill(openingKindName(o), isDoor ? t.accent : t.chk)),
        subtitle: tr3('也可以直接在图上拖动它，换位置或换到别的墙上',
            'Сызбада сүйреп, орнын не қабырғасын ауыстыруға болады', 'Можно перетащить на чертеже, чтобы сменить место или стену'),
        summary: '${o.width} × ${o.height} $unitMm',
        deleteLabel: tr3('删除${openingKindName(o)}', '${openingKindName(o)} жою', 'Удалить: ${openingKindName(o)}'),
        onDelete: () {
          final before = history.present;
          update(clearSelection);
          action('DeleteOpening', {'openingId': o.id});
          if (history.present != before)
            notify(
                tr3('已删除${openingKindName(o)}', '${openingKindName(o)} жойылды', 'Удалено: ${openingKindName(o)}'),
                undo: undo);
        },
        actions: [
          for (final kind in OpeningKind.values)
            if (kind != o.kind)
              Btn(
                  label: '${tr3('换成', '→', '→')} ${switch (kind) {
                    OpeningKind.door => tr3('门', 'есік', 'дверь'),
                    OpeningKind.window => tr3('窗', 'терезе', 'окно'),
                    OpeningKind.sliding => tr3('推拉门', 'сырғымалы есік', 'раздвижная дверь'),
                  }}',
                  icon: Icons.swap_horiz,
                  onPressed: () => action(
                      'SetOpeningKind', {'openingId': o.id, 'kind': kind})),
          if (o is DoorOpening) ...[
            Btn(
                label: tr3('门轴换边', 'Топсаны ауыстыру', 'Перевесить петли'),
                icon: Icons.flip,
                onPressed: () => action('FlipDoor', {
                      'openingId': o.id,
                      'hinge': o.hinge == Hinge.start ? 'end' : 'start'
                    })),
            Btn(
                label: tr3('换开门方向', 'Ашылу бағыты', 'Сменить направление открывания'),
                icon: Icons.swap_vert,
                onPressed: () => action('FlipDoor', {
                      'openingId': o.id,
                      'opensTo': o.opensTo == OpeningSide.positiveSide
                          ? 'negativeSide'
                          : 'positiveSide'
                    })),
            if (history.present.mainEntranceOpeningId != o.id)
              Btn(
                  label: tr3('设为大门', 'Басты кіреберіс', 'Сделать главным входом'),
                  icon: Icons.home_outlined,
                  onPressed: () =>
                      action('SetMainEntrance', {'openingId': o.id})),
          ],
          Btn(
              label: tr3('放到墙中间', 'Қабырға ортасына', 'По центру стены'),
              icon: Icons.format_align_center,
              onPressed: () => action('MoveOpening', {
                    'openingId': o.id,
                    'position': {'type': 'center'}
                  })),
        ],
        children: [
          KvGrid([
            Kv('${o.width}', tr3('宽 mm', 'Ені, мм', 'Ширина, мм'),
                onTap: () => resize('width', tr3('宽度', 'Ені', 'Ширина'), o.width)),
            Kv('${o.height}', tr3('高 mm', 'Биіктігі, мм', 'Высота, мм'),
                onTap: () => resize('height', tr3('高度', 'Биіктігі', 'Высота'), o.height)),
            if (!isDoor)
              Kv('${o.sill}', tr3('窗台 mm', 'Терезе алды, мм', 'Подоконник, мм'),
                  onTap: () =>
                      resize('sill', tr3('窗台高度', 'Терезе алды', 'Высота подоконника'), o.sill)),
            Kv(
                offset == null ? '—' : '$offset',
                vertical
                    ? tr3('距墙下端 mm', 'Төменгі шетінен, мм', 'От нижнего края, мм')
                    : tr3('距墙左端 mm', 'Сол шетінен, мм', 'От левого края, мм'), onTap: () async {
              final v = await askMm(
                  vertical
                      ? tr3('距墙下端', 'Төменгі шетінен', 'От нижнего конца стены')
                      : tr3('距墙左端', 'Сол шетінен', 'От левого края'),
                  offset ?? 0);
              if (v != null)
                action('MoveOpening', {
                  'openingId': o.id,
                  'position': {'type': 'fromStart', 'd': v}
                });
            }),
            Kv(facing == null ? tr3('室内', 'Ішкі', 'Внутри') : facingName(facing),
                tr3('朝向', 'Бағыты', 'Ориентация')),
            Kv(dec((o.width * o.height / 1e6).toStringAsFixed(2)),
                '${tr3('面积', 'Ауданы', 'Площадь')} $unitM2'),
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
          final value = await askText(tr3('名称', 'Атауы', 'Наименование'), f.label ?? '');
          if (value != null)
            action('UpdateFurniture', {'furnitureId': f.id, 'label': value});
        }, tag: TagPill(furnitureName(f.kind), t.rug)),
        subtitle: tr3('拖动移动 · 拖右下角圆点改大小 · 拖上方圆圈旋转',
            'Сүйреп жылжытыңыз · оң төменгі нүкте — өлшем · жоғарғы шеңбер — бұру', 'Перетащите, чтобы переместить · правая нижняя точка — размер · верхний кружок — поворот'),
        summary: '${f.width} × ${f.depth} × ${f.height} $unitMm',
        deleteLabel: tr3('删除$name', '$name жою', 'Удалить: $name'),
        onDelete: () {
          update(clearSelection);
          action('DeleteFurniture', {'furnitureId': f.id});
          notify(tr3('已删除$name', '$name жойылды', 'Удалено: $name'), undo: undo);
        },
        actions: [
          Btn(
              label: tr3('旋转 90°', '90° бұру', 'Повернуть на 90°'),
              icon: Icons.rotate_90_degrees_ccw,
              onPressed: () =>
                  action('RotateFurniture', {'furnitureId': f.id})),
          Btn(
              label: tr3('复制', 'Көшіру', 'Копировать'),
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
              label: tr3('换类型', 'Түрін ауыстыру', 'Сменить тип'),
              icon: Icons.category_outlined,
              onPressed: () async {
                final kind = await pickFurnitureKind();
                if (kind != null)
                  action(
                      'UpdateFurniture', {'furnitureId': f.id, 'kind': kind});
              }),
        ],
        children: [
          KvGrid([
            Kv('${f.width}', tr3('宽 mm', 'Ені, мм', 'Ширина, мм'),
                onTap: () => edit('width', tr3('宽度', 'Ені', 'Ширина'), f.width)),
            Kv('${f.depth}', tr3('深 mm', 'Тереңдігі, мм', 'Глубина, мм'),
                onTap: () => edit('depth', tr3('深度', 'Тереңдігі', 'Глубина'), f.depth)),
            Kv('${f.height}', tr3('高 mm', 'Биіктігі, мм', 'Высота, мм'),
                onTap: () => edit('height', tr3('高度', 'Биіктігі', 'Высота'), f.height)),
            Kv('${f.elevation}', tr3('离地 mm', 'Еденнен, мм', 'От пола, мм'),
                onTap: () => edit(
                    'elevation', tr3('离地高度', 'Еденнен биіктігі', 'Высота от пола'), f.elevation)),
            Kv('${f.x}', tr3('距左墙 mm', 'Сол жақтан, мм', 'Отступ слева, мм'),
                onTap: () => edit('x', tr3('距左侧外边', 'Сол жақтан', 'Отступ слева'), f.x)),
            Kv('${f.y}', tr3('距下墙 mm', 'Төменнен, мм', 'Отступ снизу, мм'),
                onTap: () => edit('y', tr3('距下侧外边', 'Төменнен', 'Отступ снизу'), f.y)),
          ]),
          if (textile)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 6, children: [
                  Text(tr3('花色', 'Өрнек', 'Узор'),
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

  /// Summary of the whole design when nothing is selected.
  Widget houseCard() {
    final t = Tokens.of(context);
    final doc = history.present;
    final g = derived.floors[floorIndex];
    final interior = g.base.roomGeometry.fold(0.0, (s, r) => s + r.clearArea);
    final openings = g.openings.length;
    return InfoCard(
        title: tr3('整栋房屋', 'Бүкіл үй', 'Весь дом'),
        subtitle: tr3('点房间、门窗或家具查看和修改',
            'Бөлмені, есік-терезені не жиһазды басып өзгертіңіз', 'Нажмите на комнату, окно, дверь или мебель, чтобы изменить'),
        children: [
          KvGrid([
            Kv('${dec((doc.footprint.width * doc.footprint.depth / 1e6).toStringAsFixed(1))} $unitM2',
                tr3('建筑面积', 'Құрылыс ауданы', 'Общая площадь'),
                onTap: footprintOptions),
            Kv('${dec((interior / 1e6).toStringAsFixed(1))} $unitM2',
                '${displayFloorName(floor.name)} · ${tr3('室内净面积', 'ішкі таза аудан', 'чистая внутренняя площадь')}'),
            Kv('${floor.rooms.length}', tr3('房间', 'Бөлмелер', 'Комнаты')),
            Kv('$openings', tr3('门窗', 'Есік-терезе', 'Окна и двери')),
            Kv('${floor.height}', tr3('层高 mm', 'Қабат биіктігі, мм', 'Высота этажа, мм'),
                onTap: () async {
              final v = await askMm(tr3('层高', 'Қабат биіктігі', 'Высота этажа'), floor.height);
              if (v != null)
                action('SetFloorHeight', {'floorId': floor.id, 'value': v});
            }),
            Kv('${doc.defaults.outerWallThickness}',
                tr3('外墙厚 mm', 'Сыртқы қабырға, мм', 'Наружная стена, мм'), onTap: () async {
              final v = await askMm(tr3('外墙厚度', 'Сыртқы қабырға қалыңдығы', 'Толщина наружной стены'),
                  doc.defaults.outerWallThickness);
              if (v != null)
                action(
                    'SetDefault', {'field': 'outerWallThickness', 'value': v});
            }),
            Kv(roofStyleName(roofStyle), tr3('屋顶', 'Шатыр', 'Крыша'),
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
                          '${dec((g.base.roomGeometry.firstWhere((r) => r.id == room.id).clearArea / 1e6).toStringAsFixed(1))} $unitM2',
                          style: mono(size: 13, color: t.muted)),
                    ]))),
        ]);
  }
}
