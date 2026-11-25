part of '../page.dart';

class _WallTrial {
  const _WallTrial(this.token, this.floorId, this.original, this.candidate,
      this.line, this.distanceLabel, this.areaLabel, this.budgetLabel, this.budgetDetails);
  final String token, floorId, distanceLabel, areaLabel, budgetLabel, budgetDetails;
  final HouseDocument original, candidate;
  final PlanRect line;
}

extension _VoiceWallPreview on _HouseEditorState {
  ActionResult prepareWallTrial(
      String grow, String shrink, int distance, double? minArea) {
    // Supersede the old proposal even if this new request cannot be built.
    if (_wallTrial != null) update(() => _wallTrial = null);
    if (distance <= 0 || grow == shrink || (minArea != null && minArea < 0)) {
      return const ActionResult.fail(ActionCodes.badArgs);
    }
    final walls = base.wallsBetween(grow, shrink).toList();
    if (walls.isEmpty) return const ActionResult.fail('no_shared_wall');
    if (walls.length != 1) {
      return const ActionResult.fail('multiple_shared_segments');
    }
    final wall = walls.single;
    final sign = base.owners[wall.edges.first.negative] == grow ? 1 : -1;
    final position = wall.axis.pos + sign * distance;
    final result = executeCommand(
        presentState,
        DesignCommand('MoveLocalWall', {
          'floorId': floor.id,
          'anchor': wall.ref.anchor,
          'pos': position,
        }),
        CommandContext(
            newId: () => const Uuid().v4(),
            now: () => DateTime.now().toUtc().toIso8601String()));
    if (result is! Applied) {
      return result is Rejected
          ? ActionResult.fail(result.reason, say: {'message': result.message})
          : const ActionResult.fail(needsResolution);
    }
    final next = composeDocument(document.meta, result.newState);
    final nextBase = deriveFloorBase(next, floor.id);
    final newGrow = nextBase.roomsById[grow]?.clearArea;
    final newShrink = nextBase.roomsById[shrink]?.clearArea;
    final oldGrow = base.roomsById[grow]!.clearArea;
    final oldShrink = base.roomsById[shrink]!.clearArea;
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
    final p = position.toDouble(),
        lo = wall.start.pos.toDouble(),
        hi = wall.end.pos.toDouble();
    final before = estimate;
    final after = estimateCost(next, deriveHouse(next),
        currency: before.currency, book: priceBook);
    final delta = after.total.round() - before.total.round();
    final symbol = currencySymbol(before.currency);
    final caption = tr3('预计总价变化', 'Сметаның өзгерісі', 'Изменение сметы',
        'Estimated budget change', ky: 'Сметанын өзгөрүшү', uz: 'Smeta farqi');
    final budgetLabel = '$caption  ${delta > 0 ? '+' : ''}${money(delta)} $symbol';
    final details = <String>['${money(before.total)} → ${money(after.total)} $symbol'];
    final finishChanges = <String, Object?>{};
    for (final key in ['finishArea', 'finishTileArea']) {
      final previous = before.lines.where((l) => l.key == key && !l.custom).firstOrNull;
      final proposed = after.lines.where((l) => l.key == key && !l.custom).firstOrNull;
      final areaChange = (proposed?.quantity ?? 0) - (previous?.quantity ?? 0);
      if (areaChange.abs() < 0.000001) continue;
      final price = (proposed ?? previous)!.price;
      final label = costLineName(key);
      final signed = '${areaChange > 0 ? '+' : ''}${dec(areaChange.toStringAsFixed(2))}';
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
        '$distance mm',
        areas.join('   ·   '), budgetLabel, details.join('\n'));
    showSharedWall(wall);
    update(() => _wallTrial = trial);
    return ActionResult.ok(say: {
      'preview_id': trial.token,
      'applied': false,
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
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(trial.budgetLabel),
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                            title: Text(trial.budgetLabel),
                            content: Text(trial.budgetDetails),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text(tr3('关闭', 'Жабу', 'Закрыть', 'Close',
                                      ky: 'Жабуу', uz: 'Yopish')))
                            ]))),
                TextButton(
                    onPressed: () => resolveWallTrial(trial.token, false),
                    child:
                        Text(tr3('取消试改', 'Бас тарту', 'Отменить', 'Cancel'))),
                FilledButton(
                    onPressed: () => resolveWallTrial(trial.token, true),
                    child: Text(
                        tr3('应用移墙', 'Қолдану', 'Применить', 'Apply move'))),
              ])));
}
