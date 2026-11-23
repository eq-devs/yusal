part of '../page.dart';

/// Picking what was tapped, in 2D and in 3D.
extension _Picking on _HouseEditorState {
  Future<void> tapObject(Offset point, Size size) async {
    final painter = interactionPainter();
    if (showDimensions && (browse || tool == EditorTool.drawWall)) {
      final span = FloorPlanPainter(base, {}, {},
              viewportInsets: canvasInsets, handleScale: canvasZoom)
          .dimensionAt(point, size);
      if (span != null) {
        await editDimension(span);
        return;
      }
    }
    // Tolerances are screen pixels, so they stay finger-sized at any zoom.
    final x = painter.worldPoint(point, size).x;
    final y = painter.worldPoint(point, size).y;
    final tolerance = 14 / (painter.scale(size) * canvasZoom);
    final placements = derived.floors[floorIndex].openings.where((p) {
      final along = p.axis.dir == AxisDir.H ? x : y;
      final cross = p.axis.dir == AxisDir.H ? y : x;
      return along >= p.start - tolerance &&
          along <= p.end + tolerance &&
          (cross - p.axis.pos).abs() < tolerance;
    }).toList()
      ..sort((a, b) => ((a.axis.dir == AxisDir.H ? y : x) - a.axis.pos)
          .abs()
          .compareTo(((b.axis.dir == AxisDir.H ? y : x) - b.axis.pos).abs()));
    final utility = utilityAt(point, size);
    if (utility != null && tool != EditorTool.selectWall) {
      update(() {
        clearSelection();
        clearWallSelection();
        selectedUtilityId = utility.id;
        panelCollapsed = false;
        placementHint = null;
      });
      return;
    }
    final opening = placements.firstOrNull;
    if (opening != null && tool != EditorTool.selectWall) {
      selectOpening(opening.opening);
      return;
    }
    final cellI = base.axes.v.indexWhere((a) => a.pos > x) - 1;
    final cellJ = base.axes.h.indexWhere((a) => a.pos > y) - 1;
    final roomHere = base.owners[Cell(cellI, cellJ)];
    final piece = furnitureAtWorld(Offset(x, y));
    // Rugs cover rooms: the first tap picks the room, the next the rug.
    if (piece != null &&
        tool != EditorTool.selectWall &&
        (!isFlatFurniture(piece.kind) ||
            (roomHere != null && roomHere == selectedRoomId) ||
            roomHere == null)) {
      update(() {
        clearSelection();
        clearWallSelection();
        selectedFurnitureId = piece.id;
        // Phones: the card starts folded to its name and actions, so the
        // piece stays in view; details unfold on demand.
        panelCollapsed = phoneTools;
        placementHint = null;
      });
      return;
    }
    final wall = wallAtPoint(point, size, radius: 16);
    if (wall != null) {
      update(clearSelection);
      if (wall.axis.kind != 'boundary') {
        update(
            () => showWallContext(wall, attachmentOnWall(wall, point, size)));
        return;
      }
      // Tapping an outside wall: add an opening right here, or change the
      // wall itself. Two labelled groups instead of one mixed list.
      final t = Tokens.of(context);
      Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: t.muted)));
      Widget item(String key, IconData icon, String label) => ListTile(
          key: ValueKey('wall-sheet-$key'),
          leading: Icon(icon),
          title: Text(label),
          onTap: () => Navigator.pop(context, key));
      final choice = await showMotionSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                        '${tr3('外墙', 'Сыртқы қабырға', 'Толщина наружной стены', 'Outer wall thickness')} · ${dec(((wall.end.pos - wall.start.pos) / 1000).toStringAsFixed(2))} $unitM',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700))),
                heading(tr3('在点的位置加', 'Осы жерге қосу', 'Добавить здесь', 'Add here')),
                item('door', Icons.door_front_door_outlined,
                    tr3('门', 'Есік', 'Дверь', 'Door')),
                item('window', Icons.window_outlined,
                    tr3('窗', 'Терезе', 'Окно', 'Window')),
                item('sliding', Icons.door_sliding_outlined,
                    tr3('推拉门', 'Сырғымалы есік', 'Раздвижная дверь', 'Sliding door')),
                heading(tr3('这段墙', 'Осы қабырға', 'Эта стена', 'This wall')),
                item('thickness', Icons.straighten,
                    tr3('调整墙厚', 'Қалыңдығын өзгерту', 'Изменить толщину', 'Change thickness')),
                item(
                    'open',
                    Icons.crop_free,
                    tr3('去掉这段墙（开放）', 'Қабырғасыз (ашық)',
                        'Без стены (открыто)',
                        'No wall (open)')),
                item(
                    'default',
                    Icons.restart_alt,
                    tr3('恢复默认墙', 'Әдепкі қабырғаны қайтару',
                        'Вернуть стену по умолчанию',
                        'Restore the default wall')),
              ])));
      if (choice == null) return;
      if (choice == 'move') {
        update(() {
          selectedWall = wall;
          tool = EditorTool.wall;
          placementHint = null;
        });
        return;
      }
      if (choice == 'position') {
        final value = await length(
            wall.axis.dir == AxisDir.V
                ? tr3('距左侧外墙', 'Сол жақ сыртқы қабырғадан',
                    'От левой наружной стены',
                    'From the left outer wall')
                : tr3('距下侧外墙', 'Төменгі сыртқы қабырғадан',
                    'От нижней наружной стены',
                    'From the bottom outer wall'),
            wall.axis.pos);
        if (value != null) {
          action('MoveLocalWall',
              {'floorId': floor.id, 'anchor': wall.ref.anchor, 'pos': value});
        }
        return;
      }
      if (['door', 'window', 'sliding'].contains(choice)) {
        final before = {for (final o in floor.openings) o.id};
        action('AddOpening', {
          'floorId': floor.id,
          'anchor': wall.ref.anchor,
          'kind': OpeningKind.values.firstWhere((k) => k.name == choice),
          // Where the finger was, not 200 mm from a corner.
          'centerAtTap': true,
          'tapT': ((wall.axis.dir == AxisDir.H ? x : y) - wall.start.pos)
              .clamp(0, wall.end.pos - wall.start.pos)
        });
        // Select what was just added: its card offers change and delete.
        final added =
            floor.openings.where((o) => !before.contains(o.id)).firstOrNull;
        if (added != null) selectOpening(added);
      } else {
        int? thickness;
        if (choice == 'thickness') {
          thickness = await length(
              tr3('墙厚', 'Қабырға қалыңдығы', 'Толщина стены', 'Wall thickness'),
              wall.thickness.round());
        }
        if (choice != 'thickness' || thickness != null) {
          action('SetWallOverride', {
            'floorId': floor.id,
            'anchor': wall.ref.anchor,
            'type': choice,
            'value': thickness
          });
        }
      }
      return;
    }
    if (tool == EditorTool.editWall || menuWall != null) {
      // A tap beside the selected wall just ends the selection.
      update(() {
        clearWallSelection();
        if (tool == EditorTool.editWall) {
          tool = EditorTool.browse;
        }
        placementHint = null;
      });
      return;
    }
    final i = base.axes.v.indexWhere((a) => a.pos > x) - 1;
    final j = base.axes.h.indexWhere((a) => a.pos > y) - 1;
    final id = base.owners[Cell(i, j)];
    final room = floor.rooms.where((r) => r.id == id).firstOrNull;
    if (room != null) {
      update(() {
        clearSelection();
        selectedRoomId = room.id;
        // Phones: one line, so the room stays in view (see [panel]).
        panelCollapsed = phoneTools;
        if (highlights.isNotEmpty) flash(const []);
      });
      revealRoom(room.id);
      return;
    }
    if (id == null) {
      update(() {
        clearSelection();
        if (highlights.isNotEmpty) flash(const []);
      });
    }
    final stair = floor.stairs.where((s) => s.id == id).firstOrNull;
    if (stair != null) {
      final choice = await showMotionSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final e in {
                  'move': tr3('挪位置', 'Орнын ауыстыру', 'Передвинуть', 'Move'),
                  'size': tr3('改尺寸', 'Өлшемін өзгерту', 'Изменить размер', 'Resize'),
                  'straight': tr3('直梯', 'Тік баспалдақ', 'Прямая лестница', 'Straight stairs'),
                  'L': tr3(
                      'L 型楼梯', 'L тәрізді баспалдақ', 'Г-образная лестница', 'L-shaped stairs'),
                  'U': tr3(
                      'U 型楼梯', 'U тәрізді баспалдақ', 'П-образная лестница', 'U-shaped stairs'),
                  'turn': tr3('切换转向', 'Бұрылысын ауыстыру',
                      'Сменить направление поворота',
                      'Switch the turn direction'),
                  'start': tr3('切换起步边', 'Басталатын жағын ауыстыру',
                      'Сменить сторону начала',
                      'Switch the starting side'),
                  'delete': tr3('删除楼梯', 'Баспалдақты жою', 'Удалить лестницу', 'Delete the stairs')
                }.entries)
                  ListTile(
                      key: Key('stair-${e.key}'),
                      title: Text(e.value),
                      onTap: () => Navigator.pop(context, e.key))
              ])));
      if (choice == null || !mounted) return;
      if (choice == 'move') {
        startStairStamp(moving: stair);
      } else if (choice == 'size') {
        await resizeStair(stair);
      } else if (choice == 'delete') {
        action('RemoveStair', {'stairId': stair.id});
      } else if (choice == 'turn') {
        action('UpdateStair', {
          'stairId': stair.id,
          'turn': stair is TurnStair && stair.turn == StairTurn.left
              ? 'right'
              : 'left'
        });
      } else if (choice == 'start') {
        action('UpdateStair', {
          'stairId': stair.id,
          'startEdge': StairEdge.values[(stair.startEdge.index + 1) % 4].name
        });
      } else {
        action('UpdateStair', {'stairId': stair.id, 'type': choice});
      }
    }
  }

  void pick3d(SourceRef? source) {
    PlanRect? selected;
    int? index;
    if (source is WallSource) {
      final wallRef = source.wall;
      index = history.present.floors.indexWhere((f) => f.id == wallRef.floorId);
      if (index >= 0) {
        final b = derived.floors[index].base;
        final w = b.wallSegments.indexWhere((w) => w.ref == wallRef);
        if (w >= 0) selected = b.wallRects[w];
      }
    } else if (source is OpeningSource || source is StairSource) {
      for (var i = 0; i < derived.floors.length; i++) {
        final g = derived.floors[i];
        if (source is OpeningSource) {
          final p = g.openings
              .where((p) => p.opening.id == source.openingId)
              .firstOrNull;
          if (p != null) {
            final cross = p.axis.pos.toDouble();
            selected = p.axis.dir == AxisDir.H
                ? PlanRect(p.start, cross, p.end, cross)
                : PlanRect(cross, p.start, cross, p.end);
            index = i;
          }
        } else if (source is StairSource) {
          final stair =
              g.stairs.where((s) => s.stairId == source.stairId).firstOrNull;
          if (stair != null) {
            selected = stair.opening;
            index = i;
          }
        }
      }
    }
    if (selected != null && index != null && index >= 0) {
      update(() {
        floorIndex = index!;
        view3d = false;
        tool = EditorTool.browse;
        derive();
        focus = selected;
      });
    }
  }
}
