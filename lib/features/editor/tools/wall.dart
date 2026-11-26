part of '../page.dart';

/// Drawing, editing and deleting walls on the plan.
extension _WallTool on _HouseEditorState {
  void startWallDrawing() {
    cancelDrag();
    view3d = false;
    tool = EditorTool.drawWall;
    drawingOrigin = null;
    placingWallStart = false;
    drawingEnd = null;
    clearWallSelection();
    placementHint = null;
  }

  void finishWallStroke() {
    settlePreview();
    final end = drawingEnd;
    final error = spatialError;
    drawingOrigin ??= drawingBefore;
    final accepted = end != null &&
        drawingOrigin != null &&
        (end - drawingOrigin!).distance >= 300 &&
        error == null;
    final tapped = end == null;
    final args = accepted ? drawingArguments : null;
    spatialDocument = null;
    spatialBase = null;
    spatialError = null;
    drawingStrokeActive = false;
    drawingBefore = null;
    drawingEnd = null;
    if (args != null) {
      final before = history.present;
      action('AddDrawnWall', args);
      // The guide has done its job once a wall exists.
      if (history.present != before) coachDismissed = true;
      // Continue from the new end only where another wall can still start.
      if (history.present != before) {
        final from = Offset(
            (args['x0'] as int).toDouble(), (args['y0'] as int).toDouble());
        drawingOrigin =
            canExtendWallFrom(base, derived.floors[floorIndex].openings, end!)
                ? end
                : null;
        final step = end - from;
        looseEnd = drawingOrigin == null ||
                endJoinsWall(base, end,
                    horizontal: step.dx != 0,
                    ignore: (w) =>
                        (w.axis.dir == AxisDir.H) == (step.dx != 0) &&
                        w.axis.pos == (step.dx != 0 ? end.dy : end.dx))
            ? null
            : (
                at: end,
                heading: step.dx != 0
                    ? Offset(step.dx.sign, 0)
                    : Offset(0, step.dy.sign)
              );
      }
    }
    if (error != null) notify(error);
    placementHint = reachAcrossPoint != null
        ? tr3(
            '墙停在了半路。可以接着拖，或点「接到对面」',
            'Қабырға жарты жолда тоқтады. Жалғастырып тартыңыз не «Қарсы қабырғаға дейін» басыңыз',
            'Стена остановилась на полпути. Тяните дальше или нажмите «До стены напротив»',
            'The wall stopped halfway. Keep dragging or tap “To the opposite wall”',
            ky:
                'Дубал жарым жолдо токтоду. Сүйрөй бериңиз же «Карама-каршы дубалга чейин» дегенди басыңыз',
            uz:
                'Devor yarim yoʻlda toʻxtadi. Surishda davom eting yoki “Qarama-qarshi devorgacha” ni bosing')
        : tapped
            ? tr3(
                '按住大 ＋ 拖出新墙 · 也可点尺子输入长度',
                'Үлкен ＋ белгісін ұстап тартыңыз · не сызғышты басып ұзындық енгізіңіз',
                'Удерживайте большой ＋ и тяните · или нажмите на линейку и введите длину',
                'Hold the big ＋ and drag · or tap the ruler and enter a length',
                ky:
                    'Чоң ＋ белгисин кармап сүйрөңүз · же сызгычты басып, узундугун киргизиңиз',
                uz:
                    'Katta ＋ ni bosib turib suring · yoki chizgʻichga bosib, uzunlikni kiriting')
            : !accepted && error == null
                ? tr3(
                    '墙至少 0.30 米，请拖远一些',
                    'Қабырға кемінде 0,30 м, әріректе жіберіңіз',
                    'Стена не короче 0,30 м, протяните дальше',
                    'Walls are at least 0.30 m; drag further',
                    ky: 'Дубалдар кеминде 0,30 м; андан ары сүйрөңүз',
                    uz: 'Devorlar kamida 0,30 m; yana suring')
                : null;
    update(() {});
  }

  void previewWallEdit(Offset local, Size size) {
    if (wallGrip == null ||
        editDown == null ||
        editStart == null ||
        editEnd == null) {
      return;
    }
    if (editPreviewStart == null &&
        downPoint != null &&
        (local - downPoint!).distance * canvasZoom < 8) {
      return;
    }
    final painter = interactionPainter();
    final world = painter.worldPoint(local, size);
    final raw = Offset(world.x, world.y);
    final pixel = mmPerPixel(painter, size);
    final vertical = editStart!.dx == editEnd!.dx;
    final carrier = vertical ? editStart!.dx : editStart!.dy;
    final lo = math.min(vertical ? editStart!.dy : editStart!.dx,
        vertical ? editEnd!.dy : editEnd!.dx);
    final hi = math.max(vertical ? editStart!.dy : editStart!.dx,
        vertical ? editEnd!.dy : editEnd!.dx);
    bool own(WallSegment w) =>
        w.axis.dir == (vertical ? AxisDir.V : AxisDir.H) &&
        w.axis.pos == carrier &&
        w.start.pos >= lo &&
        w.end.pos <= hi;
    final target = <String, dynamic>{
      'floorId': floor.id,
      if (selectedDrawnId != null) 'wallId': selectedDrawnId,
      if (selectedDrawnId == null) 'anchor': selectedDrawnAnchor,
    };
    if (wallGrip == WallGrip.start || wallGrip == WallGrip.end) {
      final fixed = wallGrip == WallGrip.start ? editEnd! : editStart!;
      final moving = wallGrip == WallGrip.start ? editStart! : editEnd!;
      final snap = lastWallSnap = snapWallEnd(base, fixed, raw,
          connectRadius: 22 * pixel,
          alignRadius: 14 * pixel,
          forceHorizontal: !vertical,
          ignore: own,
          skipAlong: {(vertical ? moving.dy : moving.dx).round()},
          previous: lastWallSnap);
      if (snap.connected && !drawConnected) HapticFeedback.selectionClick();
      drawConnected = snap.connected;
      alignGuide = guideFor(snap);
      editPreviewStart = wallGrip == WallGrip.start ? snap.end : editStart;
      editPreviewEnd = wallGrip == WallGrip.end ? snap.end : editEnd;
      editCommand = 'UpdateDrawnWall';
      editArgs = wallEditArguments(editPreviewStart!, editPreviewEnd!);
    } else {
      final delta = raw - editDown!;
      final across = vertical ? delta.dx : delta.dy;
      final along = vertical ? delta.dy : delta.dx;
      drawConnected = false;
      alignGuide = null;
      // Moving the wall sideways and sliding it along are two commands:
      // once one is chosen it holds until the other way clearly wins.
      final sideways = bodySideways = switch (bodySideways) {
        true => along.abs() <= across.abs() * 1.5,
        false => across.abs() > along.abs() * 1.5,
        null => across.abs() >= along.abs(),
      };
      if (sideways) {
        // Sideways: walls that end on this one stretch along with it.
        var position = carrier + across;
        var best = 14 * pixel;
        for (final axis in vertical ? base.axes.v : base.axes.h) {
          if (axis.pos == carrier) continue;
          final distance = (axis.pos - (carrier + across)).abs();
          if (distance < best) {
            best = distance;
            position = axis.pos.toDouble();
          }
        }
        if (best == 14 * pixel) position = (position / 100).round() * 100.0;
        editPreviewStart = vertical
            ? Offset(position, editStart!.dy)
            : Offset(editStart!.dx, position);
        editPreviewEnd = vertical
            ? Offset(position, editEnd!.dy)
            : Offset(editEnd!.dx, position);
        editCommand = 'MoveDrawnWall';
        editArgs = {...target, 'pos': position.round()};
      } else {
        final shift = (along / 100).round() * 100.0;
        final offset = vertical ? Offset(0, shift) : Offset(shift, 0);
        editPreviewStart = editStart! + offset;
        editPreviewEnd = editEnd! + offset;
        editCommand = 'UpdateDrawnWall';
        editArgs = wallEditArguments(editPreviewStart!, editPreviewEnd!);
      }
    }
    schedulePreview(editCommand!, editArgs!,
        ok: tr3('松手完成，支持撤销', 'Жіберіңіз, болдырмауға болады',
            'Отпустите, действие можно отменить', 'Release; you can undo this',
            ky: 'Коё бериңиз; муну артка кайтарса болот',
            uz: 'Qoʻyib yuboring; buni bekor qilish mumkin'),
        failed: tr3('无法移动这段墙', 'Бұл қабырғаны жылжыту мүмкін емес',
            'Эту стену нельзя переместить', "This wall can't be moved",
            ky: 'Бул дубалды жылдырууга болбойт',
            uz: 'Bu devorni surib boʻlmaydi'));
  }

  /// Ask how high the selected wall stands: to the ceiling, or one of the
  /// usual heights of a low wall.
  Future<void> chooseWallHeight() async {
    final id = selectedDrawnId;
    if (id == null) return;
    final now = floor.wallOverrides
            .whereType<SolidWall>()
            .where((w) => w.id == id)
            .firstOrNull
            ?.height ??
        0;
    final picked = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
                title: Text(tr3(
                    '墙的高度', 'Қабырға биіктігі', 'Высота стены', 'Wall height',
                    ky: 'Дубалдын бийиктиги', uz: 'Devor balandligi')),
                children: [
                  for (final (value, label) in [
                    (
                      0,
                      tr3(
                          '到顶（分隔房间）',
                          'Төбеге дейін (бөлмені бөледі)',
                          'До потолка (делит комнату)',
                          'To the ceiling (divides the room)',
                          ky: 'Шыпка чейин (бөлмөнү бөлөт)',
                          uz: 'Shiftgacha (xonani ajratadi)')
                    ),
                    (
                      600,
                      tr3('0.6 米 · 矮台', '0,6 м · аласа', '0,6 м · бортик',
                          '0.6 m · ledge',
                          ky: '0,6 м · бортик', uz: '0,6 m · bortik')
                    ),
                    (
                      900,
                      tr3('0.9 米 · 栏杆', '0,9 м · қоршау', '0,9 м · перила',
                          '0.9 m · railing',
                          ky: '0,9 м · тосмо', uz: '0,9 m · panjara')
                    ),
                    (
                      1100,
                      tr3('1.1 米 · 吧台', '1,1 м · бар', '1,1 м · стойка',
                          '1.1 m · bar counter',
                          ky: '1,1 м · бар', uz: '1,1 m · bar peshtaxtasi')
                    ),
                    (
                      1500,
                      tr3('1.5 米 · 半隔断', '1,5 м · жартылай',
                          '1,5 м · полуперегородка', '1.5 m · half partition',
                          ky: '1,5 м · жарым тосмо', uz: '1,5 m · yarim toʻsiq')
                    ),
                  ])
                    SimpleDialogOption(
                        key: ValueKey('wall-height-$value'),
                        onPressed: () => Navigator.pop(context, value),
                        child: Row(children: [
                          Icon(
                              value == now
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 18),
                          const SizedBox(width: 10),
                          Text(label)
                        ])),
                ]));
    if (picked == null || picked == now || !mounted) return;
    action('SetDrawnWallHeight',
        {'floorId': floor.id, 'wallId': id, 'height': picked});
  }

  /// Actions for the pressed wall, placed beside it rather than in a sheet
  /// so the wall and its grips stay visible.
  Widget? wallMenuCard() {
    final wall = menuWall;
    final point = menuPoint;
    if (wall == null || point == null || view3d || canvasSize.isEmpty) {
      return null;
    }
    final inner = wall.axis.kind != 'boundary';
    final painter = interactionPainter();
    Offset screen(Offset world) => MatrixUtils.transformPoint(
        canvasTransform.value, painter.point(world.dx, world.dy, canvasSize));
    final a = inner && editStart != null
        ? editStart!
        : wall.axis.dir == AxisDir.H
            ? Offset(wall.start.pos.toDouble(), wall.axis.pos.toDouble())
            : Offset(wall.axis.pos.toDouble(), wall.start.pos.toDouble());
    final b = inner && editEnd != null
        ? editEnd!
        : wall.axis.dir == AxisDir.H
            ? Offset(wall.end.pos.toDouble(), wall.axis.pos.toDouble())
            : Offset(wall.axis.pos.toDouble(), wall.end.pos.toDouble());
    final anchor = screen(point);
    final around = Rect.fromPoints(screen(a), screen(b)).inflate(24);
    final opening = derived.floors[floorIndex].openings.any((o) {
      final along = o.axis.dir == AxisDir.H ? point.dx : point.dy;
      final cross = o.axis.dir == AxisDir.H ? point.dy : point.dx;
      return o.status == 'ok' &&
          cross == o.axis.pos &&
          along >= o.start &&
          along <= o.end;
    });
    final width = math.min(312.0, canvasSize.width - 24);
    final height = 104.0 + (opening ? 18 : 0);
    final top = overlayTop;
    final bottom = canvasSize.height - canvasInsets.bottom + 24;
    var y = around.top - height - 6;
    var x = (anchor.dx - width / 2)
        .clamp(12.0, math.max(12.0, canvasSize.width - width - 12))
        .toDouble();
    if (y < top) y = around.bottom + 6;
    if (y + height > bottom) {
      // No room above or below (a long wall): beside it if there is room,
      // otherwise just above the pressed point.
      final right = canvasSize.width - 8;
      y = (anchor.dy - height / 2)
          .clamp(top, math.max(top, bottom - height))
          .toDouble();
      if (around.right + 6 + width <= right) {
        x = around.right + 6;
      } else if (around.left - 6 - width >= 12) {
        x = around.left - 6 - width;
      } else {
        y = (anchor.dy - height - 36)
            .clamp(top, math.max(top, bottom - height))
            .toDouble();
      }
    }
    Widget button(String key, IconData icon, String label, String tip,
            {bool danger = false, bool enabled = true}) =>
        Expanded(
            child: Tooltip(
                message: tip,
                child: Semantics(
                    button: true,
                    enabled: enabled,
                    label: tip,
                    child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: enabled ? () => wallMenuAction(key) : null,
                        child: SizedBox(
                            height: 56,
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(icon,
                                      size: 22,
                                      color: !enabled
                                          ? Theme.of(context).disabledColor
                                          : danger
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                              : null),
                                  const SizedBox(height: 4),
                                  Text(label,
                                      maxLines: 1,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: !enabled
                                              ? Theme.of(context).disabledColor
                                              : danger
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .error
                                                  : null))
                                ]))))));
    final length = (b - a).distance;
    final low =
        base.lowWalls.where((w) => identical(w.segment, wall)).firstOrNull;
    return Positioned(
        left: x,
        top: y,
        width: width,
        child: floatingSurface(Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text(
                        tr3(
                            low != null
                                ? '矮墙 ${meters(length)} 米 · 高 ${meters(low.height)} 米'
                                : '${inner ? '内墙' : '外墙'} ${meters(length)} 米 · 厚 ${meters(wall.thickness)} 米',
                            low != null
                                ? 'Аласа қабырға ${meters(length)} м · биіктігі ${meters(low.height)} м'
                                : '${inner ? 'Ішкі' : 'Сыртқы'} қабырға ${meters(length)} м · қалыңдығы ${meters(wall.thickness)} м',
                            low != null
                                ? 'Низкая стена ${meters(length)} м · высота ${meters(low.height)} м'
                                : '${inner ? 'Перегородка' : 'Наружная стена'} ${meters(length)} м · толщина ${meters(wall.thickness)} м',
                            low != null
                                ? 'Low wall ${meters(length)} m · height ${meters(low.height)} m'
                                : '${inner ? 'Partition' : 'Outer wall'} ${meters(length)} m · thickness ${meters(wall.thickness)} m',
                            ky: low != null
                                ? 'Жапыз дубал ${meters(length)} м · бийиктиги ${meters(low.height)} м'
                                : '${inner ? 'Тосмо' : 'Сырткы дубал'} ${meters(length)} м · калыңдыгы ${meters(wall.thickness)} м',
                            uz: low != null
                                ? 'Past devor ${meters(length)} m · balandligi ${meters(low.height)} m'
                                : '${inner ? 'Toʻsiq devor' : 'Tashqi devor'} ${meters(length)} m · qalinligi ${meters(wall.thickness)} m'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600))),
                if (inner && wallRooms(wall) != null)
                  TextButton(
                      key: const ValueKey('wall-target-area'),
                      onPressed: () => wallMenuAction('area'),
                      child: Text(tr3('面积', 'Аудан', 'Площадь', 'Area',
                          ky: 'Аянт', uz: 'Maydon'))),
                IconButton(
                    tooltip: tr3('关闭', 'Жабу', 'Закрыть', 'Close',
                        ky: 'Жабуу', uz: 'Yopish'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => update(closeWallMenu),
                    icon: const Icon(Icons.close, size: 18))
              ]),
              Row(children: [
                button(
                    'add',
                    Icons.add_circle_outline,
                    tr3('接墙', 'Жалғау', 'Пристроить', 'Extend',
                        ky: 'Узартуу', uz: 'Uzaytirish'),
                    '从这里接墙'.trKey(
                        'Осы жерден жалғау',
                        'Пристроить стену отсюда',
                        'Extend a wall from here',
                        'Бул жерден дубал улантуу',
                        'Shu yerdan devorni davom ettirish'),
                    enabled: !opening),
                if (inner) ...[
                  button(
                      'length',
                      Icons.straighten,
                      tr3('长度', 'Ұзындық', 'Длина', 'Length',
                          ky: 'Узундугу', uz: 'Uzunligi'),
                      '调整长度'.trKey(
                          'Ұзындығын өзгерту',
                          'Изменить длину',
                          'Change the length',
                          'Узундугун өзгөртүү',
                          'Uzunlikni oʻzgartirish')),
                  button(
                      'move',
                      Icons.open_with,
                      tr3('位置', 'Орны', 'Место', 'Location',
                          ky: 'Жайгашкан жери', uz: 'Joylashuvi'),
                      '移动墙体'.trKey(
                          'Қабырғаны жылжыту',
                          'Переместить стену',
                          'Move the wall',
                          'Дубалды жылдыруу',
                          'Devorni surish')),
                  if (low == null)
                    button(
                        'thickness',
                        Icons.line_weight,
                        tr3('墙厚', 'Қалыңдық', 'Толщина', 'Thickness',
                            ky: 'Калыңдыгы', uz: 'Qalinligi'),
                        '修改墙厚'.trKey(
                            'Қалыңдығын өзгерту',
                            'Изменить толщину',
                            'Change the thickness',
                            'Калыңдыгын өзгөртүү',
                            'Qalinlikni oʻzgartirish')),
                  if (selectedDrawnId != null)
                    button(
                        'height',
                        Icons.height,
                        tr3('高度', 'Биіктік', 'Высота', 'Height',
                            ky: 'Бийиктиги', uz: 'Balandligi'),
                        '到顶的墙或矮墙'.trKey(
                            'Төбеге дейін немесе аласа қабырға',
                            'До потолка или низкая стена',
                            'To the ceiling or a low wall',
                            'Шыпка чейин же жапыз дубал',
                            'Shiftgacha yoki past devor')),
                  button(
                      'delete',
                      Icons.delete_outline,
                      tr3('删除', 'Жою', 'Удалить', 'Delete',
                          ky: 'Өчүрүү', uz: 'Oʻchirish'),
                      '删除墙体'.trKey(
                          'Қабырғаны жою',
                          'Удалить стену',
                          'Delete the wall',
                          'Дубалды өчүрүү',
                          'Devorni oʻchirish'),
                      danger: true),
                ] else ...[
                  button(
                      'footprint',
                      Icons.aspect_ratio,
                      tr3('房屋尺寸', 'Үй өлшемі', 'Размеры дома',
                          'House dimensions',
                          ky: 'Үйдүн өлчөмдөрү', uz: 'Uy oʻlchamlari'),
                      '调整房屋长宽'.trKey(
                          'Үй өлшемін өзгерту',
                          'Изменить размеры дома',
                          'Change the house size',
                          'Үйдүн өлчөмүн өзгөртүү',
                          'Uy oʻlchamini oʻzgartirish')),
                  button(
                      'outerThickness',
                      Icons.line_weight,
                      tr3('墙厚', 'Қалыңдық', 'Толщина', 'Thickness',
                          ky: 'Калыңдыгы', uz: 'Qalinligi'),
                      '外墙厚度'.trKey(
                          'Сыртқы қабырға қалыңдығы',
                          'Толщина наружной стены',
                          'Outer wall thickness',
                          'Сырткы дубалдын калыңдыгы',
                          'Tashqi devor qalinligi')),
                ]
              ]),
              if (opening)
                Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                        tr3(
                            '这里有门窗，换个位置才能接墙',
                            'Мұнда есік-терезе бар, жалғау үшін басқа жерді таңдаңыз',
                            'Здесь окно или дверь, выберите другое место для стены',
                            "There's a window or door here; pick another spot for the wall",
                            ky: 'Бул жерде терезе же эшик бар; дубал үчүн башка жер тандаңыз',
                            uz: 'Bu yerda deraza yoki eshik bor; devor uchun boshqa joy tanlang'),
                        style: const TextStyle(fontSize: 12))),
            ]))));
  }

  Future<void> deleteSelectedWall() async {
    if (editStart == null || editEnd == null) return;
    final vertical = editStart!.dx == editEnd!.dx;
    final hosted = derived.floors[floorIndex].openings
        .where((o) =>
            o.axis.dir == (vertical ? AxisDir.V : AxisDir.H) &&
            o.axis.pos == (vertical ? editStart!.dx : editStart!.dy) &&
            o.start < (vertical ? editEnd!.dy : editEnd!.dx) &&
            o.end > (vertical ? editStart!.dy : editStart!.dx))
        .length;
    if (hosted > 0) {
      final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(tr3(
                      '删除墙及其门窗？',
                      'Қабырға мен ондағы есік-терезені жою керек пе?',
                      'Удалить стену вместе с окнами и дверями?',
                      'Delete the wall with its windows and doors?',
                      ky: 'Дубалды терезе-эшиктери менен өчүрөсүзбү?',
                      uz:
                          'Devor derazalari va eshiklari bilan oʻchirilsinmi?')),
                  content: Text(tr3(
                      '这段墙上的 $hosted 个门窗也会删除，可通过撤销恢复。',
                      'Қабырғадағы $hosted есік-терезе де жойылады, болдырмау арқылы қайтаруға болады.',
                      'Окна и двери на этой стене ($hosted шт.) тоже будут удалены, вернуть их можно отменой.',
                      'The windows and doors on this wall ($hosted) will be deleted too; undo brings them back.',
                      ky: 'Бул дубалдагы терезелер менен эшиктер ($hosted) да өчүрүлөт; артка кайтаруу аларды кайтарат.',
                      uz: 'Bu devordagi deraza va eshiklar ($hosted) ham oʻchiriladi; bekor qilish ularni qaytaradi.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel',
                            ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr3('删除', 'Жою', 'Удалить', 'Delete',
                            ky: 'Өчүрүү', uz: 'Oʻchirish')))
                  ]));
      if (yes != true) return;
    }
    final args = wallEditArguments(editStart!, editEnd!)
      ..['deleteHostedObjects'] = true;
    final before = history.present;
    action('DeleteDrawnWall', args);
    if (history.present != before) {
      update(() {
        cancelDrag();
        if (tool == EditorTool.editWall) {
          tool = EditorTool.browse;
        }
        clearWallSelection();
        placementHint = null;
      });
      notify(
          hosted > 0
              ? tr3(
                  '已删除墙体和 $hosted 个门窗',
                  'Қабырға мен $hosted есік-терезе жойылды',
                  'Стена удалена вместе с окнами и дверями ($hosted шт.)',
                  'Wall deleted with its windows and doors ($hosted)',
                  ky: 'Дубал терезе-эшиктери менен өчүрүлдү ($hosted)',
                  uz:
                      'Devor derazalari va eshiklari bilan oʻchirildi ($hosted)')
              : tr3('已删除墙体', 'Қабырға жойылды', 'Стена удалена', 'Wall deleted',
                  ky: 'Дубал өчүрүлдү', uz: 'Devor oʻchirildi'),
          undo: undo);
    }
  }

  /// Runs the wall just drawn on to the wall it was heading for.
  void reachAcross() {
    final to = reachAcrossPoint;
    final from = drawingOrigin;
    if (to == null || from == null) return;
    final before = history.present;
    action('AddDrawnWall', {
      'floorId': floor.id,
      'x0': from.dx.round(),
      'y0': from.dy.round(),
      'x1': to.dx.round(),
      'y1': to.dy.round()
    });
    if (history.present == before) return;
    update(() {
      looseEnd = null;
      drawingOrigin = null;
      placementHint = null;
    });
  }
}
