part of '../house_editor.dart';

/// Furniture: pick from a grouped palette, tap the plan to place, then drag
/// the selected piece, its corner grip (size) or its turn grip (90°).
/// The tape measure lives here too: two taps, distance in millimetres.
extension _FurnitureTool on _HouseEditorState {
  Future<FurnitureKind?> pickFurnitureKind() => showModalBottomSheet<FurnitureKind>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final t = Tokens.of(context);
        return SafeArea(
            child: SizedBox(
                height: math.min(MediaQuery.sizeOf(context).height * 0.75, 560),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Text(tr('选择家具', 'Жиһаз таңдау'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      for (final (group, kinds) in furnitureGroups()) ...[
                        Padding(
                            padding: const EdgeInsets.only(top: 14, bottom: 6),
                            child: Text(group,
                                style: TextStyle(fontSize: 12, color: t.muted))),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final kind in kinds)
                            Btn(
                                label: furnitureName(kind),
                                icon: furnitureIcon(kind),
                                onPressed: () => Navigator.pop(context, kind)),
                        ]),
                      ],
                    ])));
      });

  Future<void> chooseFurniture() async {
    final kind = await pickFurnitureKind();
    if (kind == null || !mounted) return;
    update(() {
      cancelDrag();
      clearWallSelection();
      clearSelection();
      showFurniture = true;
      placingFurniture = kind;
      tool = 'placeFurniture';
      browse = false;
      placementHint = tr('点平面放置「${furnitureName(kind)}」，可连续放置',
          '«${furnitureName(kind)}» қою үшін жоспарды басыңыз, бірнеше рет қоюға болады');
    });
  }

  Offset worldAt(Offset local, Size size) {
    final w = interactionPainter().worldPoint(local, size);
    return Offset(w.x, w.y);
  }

  static int snap50(double v) => (v / 50).round() * 50;

  void placeFurnitureAt(Offset local, Size size) {
    final kind = placingFurniture;
    if (kind == null) return;
    final p = worldAt(local, size);
    final d = furnitureDefaults[kind]!;
    final id = const Uuid().v4();
    final before = history.present;
    action('AddFurniture', {
      'id': id,
      'floorId': floor.id,
      'kind': kind,
      'x': snap50(p.dx - d.$1 / 2),
      'y': snap50(p.dy - d.$2 / 2),
    });
    if (history.present != before)
      update(() {
        selectedFurnitureId = id;
        panelCollapsed = false;
      });
  }

  List<FurnitureItem> get floorFurniture => [
        for (final f in history.present.extras.furniture)
          if (f.floorId == floor.id) f
      ];

  /// The piece under [world], raised furniture before rugs.
  FurnitureItem? furnitureAtWorld(Offset world) {
    if (!showFurniture) return null;
    final items = floorFurniture
      ..sort((a, b) => (isFlatFurniture(a.kind) ? 0 : 1)
          .compareTo(isFlatFurniture(b.kind) ? 0 : 1));
    for (final f in items.reversed) {
      if (world.dx >= f.x &&
          world.dx <= f.right &&
          world.dy >= f.y &&
          world.dy <= f.top) return f;
    }
    return null;
  }

  /// Start moving, sizing or turning the selected piece under [local].
  bool beginFurnitureGesture(Offset local, Size size) {
    final f = floorFurniture
        .where((f) => f.id == selectedFurnitureId)
        .firstOrNull;
    if (f == null || !showFurniture) return false;
    final painter = interactionPainter();
    final r = painter.rectangle(
        PlanRect(f.x.toDouble(), f.y.toDouble(), f.right.toDouble(),
            f.top.toDouble()),
        size);
    final zoom = canvasZoom;
    final corner = r.bottomRight, turn = Offset(r.center.dx, r.top - 18 / zoom);
    String? grip;
    if ((local - turn).distance * zoom <= 22) {
      grip = 'rotate';
    } else if ((local - corner).distance * zoom <= 22) {
      grip = 'resize';
    } else if (r.inflate(4 / zoom).contains(local)) {
      grip = 'move';
    }
    if (grip == null) return false;
    furnitureGrip = grip;
    furnitureDown = worldAt(local, size);
    furnitureDraft = null;
    return true;
  }

  void previewFurniture(Offset local, Size size) {
    final f = floorFurniture
        .where((f) => f.id == selectedFurnitureId)
        .firstOrNull;
    if (f == null || furnitureGrip == null || furnitureDown == null) return;
    if (furnitureDraft == null &&
        downPoint != null &&
        (local - downPoint!).distance * canvasZoom < 6) return;
    final p = worldAt(local, size);
    final delta = p - furnitureDown!;
    switch (furnitureGrip) {
      case 'move':
        furnitureDraft = f.copyWith(
            x: snap50(f.x + delta.dx), y: snap50(f.y + delta.dy));
        placementHint = tr('松手放下', 'Жіберіп қойыңыз');
      case 'resize':
        final right = math.max(f.x + 100, snap50(p.dx)),
            bottom = math.min(f.top - 100, snap50(p.dy));
        furnitureDraft = f.copyWith(
            width: right - f.x, y: bottom, depth: f.top - bottom);
        placementHint =
            '${furnitureDraft!.width} × ${furnitureDraft!.depth} $unitMm';
      default:
        furnitureDraft = f;
    }
  }

  void finishFurniture() {
    final f = floorFurniture
        .where((f) => f.id == selectedFurnitureId)
        .firstOrNull;
    final draft = furnitureDraft, grip = furnitureGrip;
    furnitureDraft = null;
    furnitureGrip = null;
    furnitureDown = null;
    placementHint = null;
    if (f == null) return;
    if (grip == 'rotate') {
      action('RotateFurniture', {'furnitureId': f.id});
      return;
    }
    if (draft == null ||
        (draft.x == f.x &&
            draft.y == f.y &&
            draft.width == f.width &&
            draft.depth == f.depth)) {
      update(() {});
      return;
    }
    action('UpdateFurniture', {
      'furnitureId': f.id,
      'x': draft.x,
      'y': draft.y,
      'width': draft.width,
      'depth': draft.depth
    });
  }

  void addMeasurePoint(Offset local, Size size) {
    final p = worldAt(local, size);
    final q = Offset(snap50(p.dx).toDouble(), snap50(p.dy).toDouble());
    update(() {
      if (measurePoints.length >= 2) measurePoints = [];
      measurePoints = [...measurePoints, q];
      placementHint = measurePoints.length == 1
          ? tr('再点第二个点', 'Екінші нүктені басыңыз')
          : '${(measurePoints[1] - measurePoints[0]).distance.round()} $unitMm · ${tr('再点一次重新开始', 'Қайта бастау үшін тағы басыңыз')}';
    });
  }

  /// Where to stand in a room for the walk-through: clear of furniture,
  /// off-centre, looking across the room (plan mm, walker yaw).
  ({double x, double y, double yaw}) roomSpot(SpaceGeometry room, int floorIdx) {
    final rects = room.clearRects;
    final r = rects.isEmpty
        ? PlanRect(room.labelAnchor.x, room.labelAnchor.y, room.labelAnchor.x,
            room.labelAnchor.y)
        : rects.reduce((a, b) => a.area >= b.area ? a : b);
    final cx = (r.left + r.right) / 2, cy = (r.bottom + r.top) / 2;
    final floorId = history.present.floors[floorIdx].id;
    final obstacles = [
      for (final f in history.present.extras.furniture)
        if (f.floorId == floorId &&
            !isFlatFurniture(f.kind) &&
            f.kind != FurnitureKind.wallRug &&
            f.kind != FurnitureKind.korpe &&
            f.kind != FurnitureKind.cushion)
          PlanRect(f.x - 300.0, f.y - 300.0, f.right + 300.0, f.top + 300.0)
    ];
    const inset = 450.0, steps = 8;
    var best = (x: cx, y: cy), bestScore = -double.infinity;
    final w = math.max(0.0, r.right - r.left - 2 * inset),
        h = math.max(0.0, r.top - r.bottom - 2 * inset);
    for (var i = 0; i <= steps; i++)
      for (var j = 0; j <= steps; j++) {
        final x = r.left + inset + w * i / steps,
            y = r.bottom + inset + h * j / steps;
        if (obstacles.any((o) => o.contains(x, y))) continue;
        var clearance = 800.0;
        for (final o in obstacles) {
          final dx = math.max(0.0, math.max(o.left - x, x - o.right)),
              dy = math.max(0.0, math.max(o.bottom - y, y - o.top));
          clearance = math.min(clearance, math.sqrt(dx * dx + dy * dy));
        }
        final score = clearance * 2 +
            math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) * 0.6;
        if (score > bestScore) {
          bestScore = score;
          best = (x: x, y: y);
        }
      }
    // Face the middle of the room (yaw 0 looks up the drawing).
    final yaw = (best.x - cx).abs() + (best.y - cy).abs() < 1
        ? 0.0
        : math.atan2(-(cx - best.x), cy - best.y);
    return (x: best.x, y: best.y, yaw: yaw);
  }

  /// Go to the walk-through, standing in [roomId].
  void walkInto(String roomId) {
    final g = derived.floors[floorIndex].base.roomGeometry
        .where((r) => r.id == roomId)
        .firstOrNull;
    if (g == null) return;
    final spot = roomSpot(g, floorIndex);
    update(() {
      walkStart = (
        floorIndex: floorIndex,
        x: spot.x,
        y: spot.y,
        yaw: spot.yaw,
        token: (walkStart?.token ?? 0) + 1
      );
      cancelDrag();
      clearWallSelection();
      tab = 'walk';
    });
  }
}
