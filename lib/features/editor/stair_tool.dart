part of 'house_editor.dart';

/// Placing and moving stairs.
extension _StairTool on _HouseEditorState {
  /// A stair to slide into place, like a room of a set size. On the top
  /// floor it first offers the floor the stair would lead to.
  void startStairStamp({Stair? moving, ({int w, int d})? size}) {
    if (floorIndex == history.present.floors.length - 1) {
      final floorId = floor.id;
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      messenger.showSnackBar(
          SnackBar(
              key: const Key('stair-needs-floor'),
              content: Text(tr3(
                  '楼梯要通到上面一层，现在还没有。',
                  'Баспалдақ жоғарғы қабатқа апарады, ол әлі жоқ.',
                  'Лестница ведёт на этаж выше, а его пока нет.')),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.fromLTRB(16, 0, 16, snackLift),
              duration: const Duration(seconds: 8),
              persist: false,
              action: SnackBarAction(
                  label: tr3('加一层并放楼梯', 'Қабат қосып, баспалдақ қою',
                      'Добавить этаж и лестницу'),
                  onPressed: () {
                    final before = history.present;
                    action('AddFloor', {'floorId': floorId});
                    if (history.present == before || !mounted) return;
                    update(() => derive());
                    startStairStamp();
                  })),
          snackBarAnimationStyle: Motion.toastStyle);
      return;
    }
    final fp = history.present.footprint;
    final at =
        moving == null ? null : resolveRect(base.axes, moving.region).rect;
    // A two-flight stair first: it is what most self-built houses have.
    final sizes = size != null
        ? [size]
        : at != null
            ? [(w: at.right - at.left, d: at.top - at.bottom)]
            : const [
                (w: 2400, d: 3600),
                (w: 3600, d: 2400),
                (w: 1200, d: 4800),
                (w: 4800, d: 1200)
              ];
    update(() {
      clearSelection();
      clearWallSelection();
      view3d = false;
      tool = EditorTool.box;
      stampStair = true;
      movingStairId = moving?.id;
      search:
      for (final s in sizes) {
        roomStamp = s;
        if (at != null) {
          setStamp(at.left.toDouble(), at.bottom.toDouble(), reach: 0);
          break;
        }
        for (final c in ['bl', 'br', 'tl', 'tr']) {
          setStamp(c.endsWith('l') ? 0 : (fp.width - s.w).toDouble(),
              c.startsWith('b') ? 0 : (fp.depth - s.d).toDouble());
          if (spatialError == null) break search;
        }
      }
      if (spatialError != null && at == null) {
        roomStamp = sizes.first;
        setStamp(0, 0);
      }
    });
    if (spatialPreview != null) reveal(spatialPreview!);
  }

  /// A stair over [region] of this floor, in the first shape that fits
  /// there: straight, then L, then U. Where none fits nothing is placed
  /// and the message says how much room a stair needs. On the top floor
  /// the message offers to add the floor the stair would lead to.
  void placeStair(AxisRectangle region) {
    final floorId = floor.id;
    if (floorIndex == history.present.floors.length - 1) {
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      messenger.showSnackBar(
          SnackBar(
              key: const Key('stair-needs-floor'),
              content: Text(tr3(
                  '楼梯要通到上面一层，现在还没有。',
                  'Баспалдақ жоғарғы қабатқа апарады, ол әлі жоқ.',
                  'Лестница ведёт на этаж выше, а его пока нет.')),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.fromLTRB(16, 0, 16, snackLift),
              duration: const Duration(seconds: 8),
              persist: false,
              action: SnackBarAction(
                  label: tr3('加一层并放楼梯', 'Қабат қосып, баспалдақ қою',
                      'Добавить этаж и лестницу'),
                  onPressed: () {
                    final before = history.present;
                    action('AddFloor', {'floorId': floorId});
                    if (history.present == before || !mounted) return;
                    update(() => derive());
                    placeStair(region);
                  })),
          snackBarAnimationStyle: Motion.toastStyle);
      return;
    }
    final rect = resolveRect(base.axes, region).rect;
    if (rect != null) {
      final cells = cellsOfRect(rect).toSet();
      final taken = floor.stairs.any((s) {
        final r = resolveRect(base.axes, s.region).rect;
        return r != null && cellsOfRect(r).any(cells.contains);
      });
      if (taken) {
        update(() => tool = EditorTool.browse);
        notify(tr3(
            '这里已经有楼梯了。点一下楼梯可以换样式或删除。',
            'Мұнда баспалдақ бар. Оны басып түрін өзгертуге не жоюға болады.',
            'Здесь уже есть лестница. Нажмите на неё, чтобы сменить вид или удалить.'));
        return;
      }
    }
    String? refusal;
    StairGeometry? tight;
    for (final type in StairType.values) {
      final args = {'floorId': floorId, 'type': type, 'region': region};
      final result = executeCommand(
          presentState,
          DesignCommand('AddStair', args),
          CommandContext(
              newId: () => const Uuid().v4(),
              now: () => DateTime.now().toUtc().toIso8601String()));
      if (result is! Applied) {
        refusal = result is Rejected
            ? result.message
            : (result as NeedsResolution).conflict.message;
        break;
      }
      final next = composeDocument(history.present.meta, result.newState);
      final known = {for (final s in floor.stairs) s.id};
      final added = deriveHouse(next)
          .floors[floorIndex]
          .stairs
          .where((s) => !known.contains(s.stairId))
          .firstOrNull;
      if (added != null && !added.fits) {
        tight ??= added;
        if (added.requiredA * added.requiredB <
            tight.requiredA * tight.requiredB) tight = added;
        continue;
      }
      update(() {
        if (history.commit(next)) changed();
        tool = EditorTool.browse;
        placementHint = null;
      });
      notify(
          switch (type) {
            StairType.straight => tr3(
                '已放直梯 · 点楼梯可换样式',
                'Тік баспалдақ қойылды · түрін өзгерту үшін оны басыңыз',
                'Прямая лестница поставлена · нажмите на неё, чтобы сменить вид'),
            StairType.L => tr3(
                '直梯放不下，已换成 L 型 · 点楼梯可换样式',
                'Тік баспалдақ сыймады, L тәрізді қойылды · түрін өзгерту үшін оны басыңыз',
                'Прямая не поместилась, поставлена Г-образная · нажмите на неё, чтобы сменить вид'),
            StairType.U => tr3(
                '直梯放不下，已换成 U 型 · 点楼梯可换样式',
                'Тік баспалдақ сыймады, U тәрізді қойылды · түрін өзгерту үшін оны басыңыз',
                'Прямая не поместилась, поставлена П-образная · нажмите на неё, чтобы сменить вид'),
          },
          undo: undo);
      return;
    }
    if (refusal != null) return notify(refusal);
    final need = tight!;
    notify(tr3(
        '这里放不下楼梯，至少要 ${meters(need.requiredA)} × ${meters(need.requiredB)} 米。换一个大些的房间，或先把墙挪开。',
        'Мұнда баспалдақ сыймайды, кемінде ${meters(need.requiredA)} × ${meters(need.requiredB)} м керек. Үлкенірек бөлмені таңдаңыз не қабырғаны жылжытыңыз.',
        'Лестница здесь не поместится: нужно не меньше ${meters(need.requiredA)} × ${meters(need.requiredB)} м. Выберите комнату побольше или сдвиньте стену.'));
  }
}
