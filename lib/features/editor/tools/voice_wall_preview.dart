part of '../page.dart';

class _WallTrial {
  const _WallTrial(
      this.token,
      this.floorId,
      this.original,
      this.candidate,
      this.line,
      this.distanceLabel,
      this.areaLabel,
      this.budgetLabel,
      this.budgetDetails);
  final String token;
  final String floorId;
  final String distanceLabel;
  final String areaLabel;
  final String budgetLabel;
  final String budgetDetails;
  final HouseDocument original;
  final HouseDocument candidate;
  final PlanRect line;
}

extension _VoiceWallPreview on _HouseEditorState {
  ActionResult prepareWallTrial(
      String grow, String shrink, int? requestedDistance, double? minArea,
      {double? target, bool targetShrinking = false}) {
    // Supersede the old proposal even if this new request cannot be built.
    if (_wallTrial != null) update(() => _wallTrial = null);
    var distance = requestedDistance;
    if ((distance == null) == (target == null) ||
        (distance != null && distance <= 0) ||
        (target != null && (!target.isFinite || target <= 0)) ||
        grow == shrink ||
        (minArea != null && minArea < 0)) {
      return const ActionResult.fail(ActionCodes.badArgs);
    }
    final walls = base.wallsBetween(grow, shrink).toList();
    if (walls.isEmpty) return const ActionResult.fail('no_shared_wall');
    if (walls.length != 1) {
      return const ActionResult.fail('multiple_shared_segments');
    }
    final wall = walls.single;
    final sign = base.owners[wall.edges.first.negative] == grow ? 1 : -1;
    final oldGrow = base.roomsById[grow]!.clearArea;
    final oldShrink = base.roomsById[shrink]!.clearArea;
    final context = CommandContext(
        newId: () => const Uuid().v4(),
        now: () => DateTime.now().toUtc().toIso8601String());
    final state = presentState;
    CommandResult move(int mm) => executeCommand(
        state,
        DesignCommand('MoveLocalWall', {
          'floorId': floor.id,
          'anchor': wall.ref.anchor,
          'pos': wall.axis.pos + sign * mm
        }),
        context);
    if (target != null) {
      final originalArea = targetShrinking ? oldShrink : oldGrow;
      final gain = (target * 1e6 - originalArea) * (targetShrinking ? -1 : 1);
      if (gain <= 0 || !gain.isFinite || gain >= oldShrink) {
        return const ActionResult.fail('target_area_out_of_range');
      }
      // Measure the effective clear span on a real candidate. Wall centreline
      // length includes junctions and would overshoot the requested area.
      final axes = wall.axis.dir == AxisDir.V ? base.axes.v : base.axes.h;
      final limit =
          (axes[wall.axis.index + sign].pos - wall.axis.pos).abs() - 300;
      if (limit <= 0) {
        return const ActionResult.fail('target_area_out_of_range');
      }
      final probe = math.min(300, limit);
      final sample = move(probe);
      if (sample is! Applied) {
        return sample is Rejected
            ? ActionResult.fail(sample.reason, say: {'message': sample.message})
            : const ActionResult.fail(needsResolution);
      }
      final sampleBase = deriveFloorBase(
          composeDocument(document.meta, sample.newState), floor.id);
      final measured =
          sampleBase.roomsById[targetShrinking ? shrink : grow]?.clearArea;
      if (measured == null || measured == originalArea) {
        return const ActionResult.fail('target_area_out_of_range');
      }
      distance = (gain * probe / (measured - originalArea).abs()).round();
      if (distance <= 0 || distance > limit) {
        return const ActionResult.fail('target_area_out_of_range');
      }
    }
    final position = wall.axis.pos + sign * distance!;
    final result = move(distance);
    if (result is! Applied) {
      return result is Rejected
          ? ActionResult.fail(result.reason, say: {'message': result.message})
          : const ActionResult.fail(needsResolution);
    }
    final next = composeDocument(document.meta, result.newState);
    final nextBase = deriveFloorBase(next, floor.id);
    final newGrow = nextBase.roomsById[grow]?.clearArea;
    final newShrink = nextBase.roomsById[shrink]?.clearArea;
    if (newGrow == null ||
        newShrink == null ||
        newGrow <= oldGrow ||
        newShrink >= oldShrink ||
        !nextBase.wallsBetween(grow, shrink).any((w) =>
            w.axis.dir == wall.axis.dir &&
            w.axis.pos == position &&
            w.start.pos == wall.start.pos &&
            w.end.pos == wall.end.pos)) {
      return const ActionResult.fail('wall_move_not_verified');
    }
    if (target != null &&
        ((targetShrinking ? newShrink : newGrow) / 1e6 - target).abs() > 0.01) {
      return const ActionResult.fail('target_area_out_of_range');
    }
    double m2(double area) => (area / 10000).round() / 100;
    if (minArea != null && newShrink < minArea * 1e6) {
      return ActionResult.fail('minimum_area_conflict',
          say: {'remaining_m2': m2(newShrink), 'required_m2': minArea});
    }
    final areas = <String>[];
    for (final r in floor.rooms.where((r) => r.id == grow || r.id == shrink)) {
      areas.add(
          '${r.name}  ${m2(base.roomsById[r.id]!.clearArea)} → ${m2(nextBase.roomsById[r.id]!.clearArea)} m²');
    }
    final p = position.toDouble();
    final lo = wall.start.pos.toDouble();
    final hi = wall.end.pos.toDouble();
    final before = estimate;
    final after = estimateCost(next, deriveHouse(next),
        currency: before.currency, book: priceBook);
    final delta = after.total.round() - before.total.round();
    final symbol = currencySymbol(before.currency);
    final caption = tr3('预计总价变化', 'Сметаның өзгерісі', 'Изменение сметы',
        'Estimated budget change',
        ky: 'Сметанын өзгөрүшү', uz: 'Smeta farqi');
    final budgetLabel =
        '$caption  ${delta > 0 ? '+' : ''}${money(delta)} $symbol';
    final details = <String>[
      '${money(before.total)} → ${money(after.total)} $symbol'
    ];
    final finishChanges = <String, Object?>{};
    for (final key in ['finishArea', 'finishTileArea']) {
      final previous =
          before.lines.where((l) => l.key == key && !l.custom).firstOrNull;
      final proposed =
          after.lines.where((l) => l.key == key && !l.custom).firstOrNull;
      final areaChange = (proposed?.quantity ?? 0) - (previous?.quantity ?? 0);
      if (areaChange.abs() < 0.000001) continue;
      final price = (proposed ?? previous)!.price;
      final label = costLineName(key);
      final signed =
          '${areaChange > 0 ? '+' : ''}${dec(areaChange.toStringAsFixed(2))}';
      details.add('$label  $signed m² × ${money(price)} $symbol/m²');
      finishChanges[key] = {
        'area_change_m2': areaChange,
        'unit_price': price,
      };
    }
    final trial = _WallTrial(
        const Uuid().v4(),
        floor.id,
        document,
        next,
        wall.axis.dir == AxisDir.V
            ? PlanRect(p, lo, p, hi)
            : PlanRect(lo, p, hi, p),
        '${m2dp(distance)} $unitM',
        areas.join('   ·   '),
        budgetLabel,
        details.join('\n'));
    showSharedWall(wall);
    update(() => _wallTrial = trial);
    return ActionResult.ok(say: {
      'preview_id': trial.token,
      'applied': false,
      'distance_mm': distance,
      'estimate': {
        'currency': before.currency.name,
        'before': before.total.round(),
        'after': after.total.round(),
        'delta': delta,
        'finish_changes': finishChanges,
      },
      'grow_before_m2': m2(oldGrow),
      'grow_after_m2': m2(newGrow),
      'shrink_before_m2': m2(oldShrink),
      'shrink_after_m2': m2(newShrink),
    });
  }

  (String, String)? wallRooms(WallSegment wall) {
    if (wall.edges.isEmpty) return null;
    final a = base.owners[wall.edges.first.negative];
    final b = base.owners[wall.edges.first.positive];
    if (a == null ||
        b == null ||
        a == b ||
        !base.roomsById.containsKey(a) ||
        !base.roomsById.containsKey(b)) {
      return null;
    }
    final shared = base.wallsBetween(a, b);
    return shared.length == 1 &&
            shared.first.axis.id == wall.axis.id &&
            shared.first.start.id == wall.start.id &&
            shared.first.end.id == wall.end.id
        ? (a, b)
        : null;
  }

  Future<void> chooseWallTarget(WallSegment wall) async {
    final pair = wallRooms(wall);
    if (pair == null) return;
    final original = document;
    final originalFloor = floor.id;
    bool current() =>
        mounted && identical(document, original) && floor.id == originalFloor;
    final rooms =
        floor.rooms.where((r) => r.id == pair.$1 || r.id == pair.$2).toList();
    final areas = {
      for (final r in rooms) r.id: base.roomsById[r.id]!.clearArea / 1e6
    };
    final title = tr3('目标净面积', 'Мақсатты таза аудан',
        'Целевая полезная площадь', 'Target clear area',
        ky: 'Максаттуу таза аянт', uz: 'Maqsadli sof maydon');
    final room = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(title: Text(title), children: [
              for (final r in rooms)
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, r.id),
                    child: Text(
                        '${r.name} · ${areas[r.id]!.toStringAsFixed(2)} m²')),
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: Text(tr3('手动拖墙', 'Қабырғаны сүйреу',
                      'Перетащить стену', 'Drag wall',
                      ky: 'Дубалды сүйрөө', uz: 'Devorni surish')))
            ]));
    if (!mounted || !current() || room == null) return;
    if (room.isEmpty) {
      showSharedWall(wall);
      return;
    }
    final area = areas[room]!;
    final value = await promptText(context,
        title: '$title · ${rooms.firstWhere((r) => r.id == room).name}',
        initial: area.toStringAsFixed(2),
        cancel: tr3('取消', 'Бас тарту', 'Отмена', 'Cancel',
            ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
        ok: tr3('预览', 'Алдын ала көру', 'Предпросмотр', 'Preview',
            ky: 'Алдын ала көрүү', uz: 'Oldindan koʻrish'),
        number: true,
        suffix: 'm²');
    if (!current() || value == null) return;
    final target = double.tryParse(value.trim().replaceAll(',', '.'));
    if (target == area || target == double.parse(area.toStringAsFixed(2))) {
      return;
    }
    final other = room == pair.$1 ? pair.$2 : pair.$1;
    final grows = target != null && target > area;
    final result = prepareWallTrial(
        grows ? room : other, grows ? other : room, null, null,
        target: target, targetShrinking: !grows);
    if (!result.ok) {
      notify(tr3('这面墙无法达到该面积，请调整目标', 'Бұл ауданға жету мүмкін емес',
          'Такая площадь недостижима', 'This wall cannot reach that area',
          ky: 'Бул аянтка жетүү мүмкүн эмес',
          uz: 'Bu maydonga yetib boʻlmaydi'));
    }
  }

  ActionResult resolveWallTrial(String token, bool apply) {
    final trial = _wallTrial;
    if (trial == null ||
        trial.token != token ||
        trial.floorId != floor.id ||
        !identical(trial.original, document)) {
      return const ActionResult.fail('stale_preview');
    }
    update(() {
      _wallTrial = null;
      clearWallSelection();
      tool = EditorTool.browse;
      if (apply && history.commit(trial.candidate)) changed();
    });
    return ActionResult.ok(say: {'applied': apply});
  }

  Widget wallTrialBar(_WallTrial trial) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(trial.areaLabel),
                TextButton.icon(
                    icon: const Icon(YIcons.contract, size: 18),
                    label: Text(trial.budgetLabel),
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                                title: Text(trial.budgetLabel),
                                content: Text(trial.budgetDetails),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text(tr3(
                                          '关闭', 'Жабу', 'Закрыть', 'Close',
                                          ky: 'Жабуу', uz: 'Yopish')))
                                ]))),
                TextButton(
                    onPressed: () => resolveWallTrial(trial.token, false),
                    child: Text(tr3('取消试改', 'Бас тарту', 'Отменить', 'Cancel',
                        ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                FilledButton(
                    key: const ValueKey('apply-wall-preview'),
                    onPressed: () => resolveWallTrial(trial.token, true),
                    child: Text(tr3(
                        '应用移墙', 'Қолдану', 'Применить', 'Apply move',
                        ky: 'Колдонуу', uz: 'Qoʻllash'))),
              ])));
}
