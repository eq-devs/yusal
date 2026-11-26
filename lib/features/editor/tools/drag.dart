part of '../page.dart';

/// Dragging rooms, objects and openings on the plan.
extension _DragTool on _HouseEditorState {
  void beginDrag(Offset point, Size size) {
    if (tool == EditorTool.selectWall) return;
    draggingAxis = null;
    draggingOpening = null;
    dragArguments = null;
    dragKind = null;
    dragged = false;
    dragAttempted = false;
    dragValid = false;
    final painter = interactionPainter();
    final mm = mmPerPixel(painter, size);
    dragCoordinatePainter = painter;
    final x = painter.worldPoint(point, size).x;
    final y = painter.worldPoint(point, size).y;
    final tolerance = 12 * mm;
    if (tool == EditorTool.wall && selectedWall != null) {
      final wall = selectedWall!;
      final along = (wall.start.pos + wall.end.pos) / 2;
      final center = wall.axis.dir == AxisDir.V
          ? painter.point(wall.axis.pos.toDouble(), along, size)
          : painter.point(along, wall.axis.pos.toDouble(), size);
      if ((point - center).distance * canvasZoom <= 24) {
        draggingAxis = wall.axis;
      }
    } else if (tool == EditorTool.resize) {
      final width = history.present.footprint.width.toDouble();
      final depth = history.present.footprint.depth.toDouble();
      final reach = 28 / canvasZoom;
      if ((point - painter.point(width, depth / 2, size)).distance <= reach) {
        draggingAxis = base.axes.v.last;
      } else if ((point - painter.point(width / 2, depth, size)).distance <=
          reach) {
        draggingAxis = base.axes.h.last;
      }
    } else if (tool == EditorTool.grid) {
      final axes = base.axes.all
          .where((a) =>
              a.kind != 'boundary' &&
              ((a.dir == AxisDir.V ? x : y) - a.pos).abs() <= tolerance)
          .toList()
        ..sort((a, b) => ((a.dir == AxisDir.V ? x : y) - a.pos)
            .abs()
            .compareTo(((b.dir == AxisDir.V ? x : y) - b.pos).abs()));
      draggingAxis = axes.firstOrNull;
    } else if (tool == EditorTool.opening || browse) {
      draggingOpening = openingAt(point, size);
    }
  }

  /// The finger left every wall the opening could go on: show it back
  /// where it was, and let a release there change nothing.
  void abandonOpeningPreview() {
    dragArguments = null;
    dragKind = null;
    dragValid = false;
    spatialDocument = null;
    spatialBase = null;
  }

  void previewDrag(Offset point, Size size) {
    if (downPoint == null ||
        (downPoint! - point).distance * canvasZoom < 8 && !dragged) {
      return;
    }
    dragAttempted = true;
    final previous = dragValid ? (dragKind, dragArguments) : null;
    dragValid = false;
    final painter = dragCoordinatePainter ?? interactionPainter();
    final x = painter.worldPoint(point, size).x;
    final y = painter.worldPoint(point, size).y;
    if (draggingAxis != null) {
      final axis = draggingAxis!;
      if (tool == EditorTool.wall && selectedWall != null) {
        final originalAxes = resolveFloorAxes(history.present, floor.id)!;
        final originalList =
            axis.dir == AxisDir.V ? originalAxes.v : originalAxes.h;
        final original = lookupAxis(originalAxes, axis.id).axis!;
        dragKind = 'MoveLocalWall';
        dragArguments = {
          'floorId': floor.id,
          'anchor': selectedWall!.ref.anchor,
          'pos': (((axis.dir == AxisDir.V ? x : y) / 100).round() * 100).clamp(
              originalList[original.index - 1].pos + 300,
              originalList[original.index + 1].pos - 300)
        };
      } else if (axis.kind == 'boundary') {
        dragKind = 'SetFootprintSize';
        dragArguments = {
          axis.dir == AxisDir.V ? 'width' : 'depth':
              ((axis.dir == AxisDir.V ? x : y) / 100).round().clamp(30, 1000) *
                  100
        };
      } else {
        var low = 0;
        var high = axis.dir == AxisDir.V
            ? history.present.footprint.width
            : history.present.footprint.depth;
        for (final floor in history.present.floors) {
          final axes = resolveFloorAxes(history.present, floor.id)!;
          final resolved = lookupAxis(axes, axis.id).axis;
          if (resolved == null) continue;
          final list = axis.dir == AxisDir.V ? axes.v : axes.h;
          low = math.max(low, list[resolved.index - 1].pos + 300);
          high = math.min(high, list[resolved.index + 1].pos - 300);
        }
        dragKind = 'MoveAxis';
        dragArguments = {
          'axisId': axis.id,
          // To the centimetre: finer is not buildable, and every pixel of
          // the finger would otherwise be a new command.
          'pos': (((axis.dir == AxisDir.V ? x : y) / 10).round() * 10)
              .clamp(low, high)
        };
      }
    } else if (draggingOpening != null) {
      final opening = draggingOpening!;
      final originalBase = deriveFloorBase(history.present, floor.id);
      final tolerance = 28 * mmPerPixel(painter, size);
      final candidates = originalBase.wallSegments.where((wall) {
        final along = wall.axis.dir == AxisDir.H ? x : y;
        final cross = wall.axis.dir == AxisDir.H ? y : x;
        return along >= wall.start.pos &&
            along <= wall.end.pos &&
            (cross - wall.axis.pos).abs() <= tolerance;
      }).toList()
        ..sort((a, b) => ((a.axis.dir == AxisDir.H ? y : x) - a.axis.pos)
            .abs()
            .compareTo(((b.axis.dir == AxisDir.H ? y : x) - b.axis.pos).abs()));
      final wall = candidates.firstOrNull;
      if (wall == null) {
        abandonOpeningPreview();
        placementHint = tr3(
            '拖到另一面墙，门窗会自动贴合',
            'Басқа қабырғаға апарыңыз, есік-терезе өзі орнығады',
            'Перетащите на другую стену — окно или дверь встанет на место',
            'Drag onto another wall and the window or door snaps into place',
            ky: 'Башка дубалга сүйрөңүз, терезе же эшик өз ордуна түшөт',
            uz: 'Boshqa devorga suring, deraza yoki eshik oʻz joyiga tushadi');
        return;
      }
      final along = wall.axis.dir == AxisDir.H ? x : y;
      final available = wall.end.pos - wall.start.pos - opening.opening.width;
      if (available < 0) {
        abandonOpeningPreview();
        placementHint = tr3(
            '这段墙放不下这个门窗',
            'Бұл қабырғаға есік-терезе сыймайды',
            'Окно или дверь не помещается на этой стене',
            "The window or door doesn't fit on this wall",
            ky: 'Терезе же эшик бул дубалга батпайт',
            uz: 'Deraza yoki eshik bu devorga sigʻmaydi');
        return;
      }
      dragKind = 'MoveOpening';
      dragArguments = {
        'openingId': opening.opening.id,
        'anchor': wall.ref.anchor,
        'position': {
          'type': 'fromStart',
          'd': (along - wall.start.pos - opening.opening.width / 2)
              .round()
              .clamp(0, available)
        }
      };
    } else {
      return;
    }
    // The same command as the last move shows the same preview.
    if (previous != null &&
        previous.$1 == dragKind &&
        sameArguments(previous.$2, dragArguments)) {
      dragValid = true;
      return;
    }
    final result = executeCommand(
        presentState,
        DesignCommand(dragKind!, dragArguments!),
        CommandContext(
            newId: () => const Uuid().v4(), now: () => '1970-01-01T00:00:00Z'));
    if (result is Applied) {
      placementHint = null;
      dragged = true;
      dragValid = true;
      // Only this floor's plan is shown while the finger moves: the house
      // is derived once, on release.
      final preview = spatialDocument =
          composeDocument(history.present.meta, result.newState);
      final previewBase = spatialBase = deriveFloorBase(preview, floor.id);
      if (dragKind == 'MoveLocalWall' && selectedWall != null) {
        // The selected wall may have acquired a new axis. Locate the two
        // rooms on the preview wall at its current position.
        final moved = previewBase.wallSegments
            .where((w) =>
                w.axis.dir == selectedWall!.axis.dir &&
                w.axis.pos == dragArguments!['pos'] &&
                w.start.pos == selectedWall!.start.pos &&
                w.end.pos == selectedWall!.end.pos)
            .firstOrNull;
        if (moved != null) {
          final pair = wallRooms(moved);
          if (pair != null) {
            placementHint = floor.rooms
                .where((r) => r.id == pair.$1 || r.id == pair.$2)
                .map((r) =>
                    '${r.name} ${(previewBase.roomsById[r.id]!.clearArea / 1e6).toStringAsFixed(2)} m²')
                .join(' · ');
          }
        }
      }
    } else if (result is Rejected) {
      spatialDocument = null;
      spatialBase = null;
      placementHint = result.message;
    }
  }

  /// Whether two command arguments say the same: maps and lists by
  /// content, everything else by `==`.
  static bool sameArguments(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && sameArguments(a[k], b[k]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!sameArguments(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  void updateSpatial(Offset point, Size size) {
    final painter = interactionPainter();
    final world = painter.worldPoint(point, size);
    if (stamping) {
      setStamp(world.x - stampGrab.dx, world.y - stampGrab.dy,
          reach: math.min(14 * mmPerPixel(painter, size), 250));
      return;
    }
    int snap(double value, List<ResolvedAxis> axes) {
      final clamped = value.round().clamp(axes.first.pos, axes.last.pos);
      for (final axis in axes) {
        if ((axis.pos - clamped).abs() <
            math.min(12 * mmPerPixel(painter, size), 250)) {
          return axis.pos;
        }
      }
      return (clamped / 100).round() * 100;
    }

    spatialEnd = Offset(snap(world.x, base.axes.v).toDouble(),
        snap(world.y, base.axes.h).toDouble());
    spatialStart ??= spatialEnd;
    if (tool == EditorTool.split) {
      final vertical = (spatialEnd!.dy - spatialStart!.dy).abs() >=
          (spatialEnd!.dx - spatialStart!.dx).abs();
      spatialPreview = vertical
          ? PlanRect(
              spatialStart!.dx,
              math.min(spatialStart!.dy, spatialEnd!.dy),
              spatialStart!.dx,
              math.max(spatialStart!.dy, spatialEnd!.dy))
          : PlanRect(
              math.min(spatialStart!.dx, spatialEnd!.dx),
              spatialStart!.dy,
              math.max(spatialStart!.dx, spatialEnd!.dx),
              spatialStart!.dy);
      validateSpatialPreview();
      return;
    }

    spatialPreview = PlanRect(
        math.min(spatialStart!.dx, spatialEnd!.dx),
        math.min(spatialStart!.dy, spatialEnd!.dy),
        math.max(spatialStart!.dx, spatialEnd!.dx),
        math.max(spatialStart!.dy, spatialEnd!.dy));
    validateSpatialPreview();
  }

  void validateSpatialPreview() {
    final rect = spatialPreview;
    if (rect == null || spatialStart == null || spatialEnd == null) return;
    if ((spatialStart! - spatialEnd!).distance < 300 ||
        tool == EditorTool.box &&
            (rect.right - rect.left < 300 || rect.top - rect.bottom < 300)) {
      spatialError = null;
      spatialDocument = null;
      spatialBase = null;
      placementHint = null;
      return;
    }
    final vertical = (spatialEnd!.dy - spatialStart!.dy).abs() >=
        (spatialEnd!.dx - spatialStart!.dx).abs();
    final midpoint = (spatialStart! + spatialEnd!) / 2;
    final arguments = tool == EditorTool.split
        ? <String, dynamic>{
            'floorId': floor.id,
            'dir': vertical ? AxisDir.V : AxisDir.H,
            'pos': (vertical ? spatialStart!.dx : spatialStart!.dy).round(),
            'x': midpoint.dx
                .round()
                .clamp(1, history.present.footprint.width - 1),
            'y': midpoint.dy
                .round()
                .clamp(1, history.present.footprint.depth - 1)
          }
        : <String, dynamic>{
            'floorId': floor.id,
            'left': rect.left.round(),
            'bottom': rect.bottom.round(),
            'right': rect.right.round(),
            'top': rect.top.round(),
            'roomType': brush
          };
    if (stairStamping) {
      arguments.remove('roomType');
      if (movingStairId != null) arguments['stairId'] = movingStairId;
    }
    final result = executeCommand(
        presentState,
        DesignCommand(
            tool == EditorTool.split
                ? 'SplitSpace'
                : stairStamping
                    ? 'PlaceStair'
                    : 'CarveRoom',
            arguments),
        CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
    spatialError = result is Rejected ? result.message : null;
    if (result is Applied) {
      spatialDocument = composeDocument(history.present.meta, result.newState);
      spatialBase = deriveFloorBase(spatialDocument!, floor.id);
      final count = spatialDocument!.floors
          .firstWhere((f) => f.id == floor.id)
          .rooms
          .length;
      placementHint = count > floor.rooms.length + 1
          ? tr3(
              '分房后会得到 $count 个独立空间，松手完成',
              'Бөлгенде $count бөлек кеңістік шығады, жіберіңіз',
              'Получится отдельных помещений: $count, отпустите',
              'Makes $count separate spaces, release',
              ky: '$count өзүнчө мейкиндик пайда болот, коё бериңиз',
              uz: '$count ta alohida boʻshliq hosil boʻladi, qoʻyib yuboring')
          : null;
    } else {
      spatialDocument = null;
      spatialBase = null;
      placementHint = spatialError;
    }
  }

  void finishSpatial() {
    spatialDocument = null;
    spatialBase = null;
    final message = spatialError;
    spatialError = null;
    placementHint = null;
    if (message != null) {
      spatialStart = null;
      spatialEnd = null;
      spatialPreview = null;
      update(() {});
      notify(message);
      return;
    }
    final rectangle = spatialPreview;
    if (tool == EditorTool.split &&
        spatialStart != null &&
        spatialEnd != null &&
        (spatialStart! - spatialEnd!).distance >= 300) {
      final vertical = (spatialEnd!.dy - spatialStart!.dy).abs() >=
          (spatialEnd!.dx - spatialStart!.dx).abs();
      final midpoint = (spatialStart! + spatialEnd!) / 2;
      final args = <String, dynamic>{
        'floorId': floor.id,
        'dir': vertical ? AxisDir.V : AxisDir.H,
        'pos': (vertical ? spatialStart!.dx : spatialStart!.dy).round(),
        'x': midpoint.dx.round().clamp(1, history.present.footprint.width - 1),
        'y': midpoint.dy.round().clamp(1, history.present.footprint.depth - 1)
      };
      spatialStart = null;
      spatialEnd = null;
      spatialPreview = null;
      action('SplitSpace', args);
      return;
    }
    spatialStart = null;
    spatialEnd = null;
    spatialPreview = null;
    if (rectangle == null ||
        rectangle.right - rectangle.left < 300 ||
        rectangle.top - rectangle.bottom < 300) {
      update(() {});
      return;
    }
    action('CarveRoom', {
      'floorId': floor.id,
      'left': rectangle.left.round(),
      'bottom': rectangle.bottom.round(),
      'right': rectangle.right.round(),
      'top': rectangle.top.round(),
      'roomType': brush
    });
  }

  void previewOpening(OpeningKind kind, Offset global) {
    final box = canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final painter = interactionPainter();
    final world = painter.worldPoint(box.globalToLocal(global), box.size);
    final tolerance = 28 / painter.scale(box.size);
    final walls = base.wallSegments.where((wall) {
      final along = wall.axis.dir == AxisDir.H ? world.x : world.y;
      final cross = wall.axis.dir == AxisDir.H ? world.y : world.x;
      return along >= wall.start.pos &&
          along <= wall.end.pos &&
          (cross - wall.axis.pos).abs() <= tolerance &&
          wall.kind != 'open';
    }).toList()
      ..sort((a, b) =>
          ((a.axis.dir == AxisDir.H ? world.y : world.x) - a.axis.pos)
              .abs()
              .compareTo(
                  ((b.axis.dir == AxisDir.H ? world.y : world.x) - b.axis.pos)
                      .abs()));
    final wall = walls.firstOrNull;
    openingDrop = null;
    derive();
    if (wall == null) {
      placementHint = tr3(
          '拖到墙上，门窗会自动贴合',
          'Қабырғаға апарыңыз, есік-терезе өзі орнығады',
          'Перетащите на стену — окно или дверь встанет на место',
          'Drag onto a wall and the window or door snaps into place',
          ky: 'Дубалга сүйрөп келиңиз, терезе же эшик өз ордуна түшөт',
          uz: 'Devorga sudrab keling, deraza yoki eshik oʻz joyiga tushadi');
      return;
    }
    final arguments = <String, dynamic>{
      'floorId': floor.id,
      'anchor': wall.ref.anchor,
      'kind': kind,
      'centerAtTap': true,
      'tapT': (wall.axis.dir == AxisDir.H ? world.x : world.y) - wall.start.pos
    };
    final result = executeCommand(
        presentState,
        DesignCommand('AddOpening', arguments),
        CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
    if (result is Applied) {
      openingDrop = arguments;
      derived =
          deriveHouse(composeDocument(history.present.meta, result.newState));
      base = derived.floors[floorIndex].base;
      placementHint = tr3('已贴合墙面，松手放置', 'Қабырғаға орнықты, жіберіңіз',
          'Привязано к стене, отпустите', 'Snapped to the wall, release',
          ky: 'Дубалга жабышты, коё бериңиз',
          uz: 'Devorga yopishdi, qoʻyib yuboring');
    } else {
      placementHint = result is Rejected
          ? result.message
          : tr3('此处无法放置', 'Мұнда қоюға болмайды', 'Здесь поставить нельзя',
              "Can't place it here",
              ky: 'Бул жерге коюуга болбойт', uz: 'Bu yerga qoʻyib boʻlmaydi');
    }
  }
}
