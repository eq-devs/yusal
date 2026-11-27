part of '../page.dart';

/// Electrical, water and heating points on the plan: a palette to place
/// them one by one, an automatic first layout per floor, and dragging or
/// deleting the selected point. Points show while the "水电" layer is on.
extension _UtilityTool on _HouseEditorState {
  List<UtilityPoint> get floorUtilities => [
        for (final u in history.present.extras.utilities)
          if (u.floorId == floor.id) u
      ];

  Future<void> chooseUtility() async {
    final choice = await showMotionSheet<Object>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final t = Tokens.of(context);
          final count = floorUtilities.length;
          return SafeArea(
              child: SizedBox(
                  height:
                      math.min(MediaQuery.sizeOf(context).height * 0.75, 520),
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Text(
                            tr3(
                                '水电暖点位',
                                'Су, электр, жылу нүктелері',
                                'Точки воды, электрики и отопления',
                                'Water, electrical and heating points',
                                ky: 'Суу, электр жана жылытуу чекиттери',
                                uz: 'Suv, elektr va isitish nuqtalari'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 10),
                            child: Text(
                                tr3(
                                    '自动布置会按房间类型放灯、开关、插座、给排水、排气扇和窗下暖气片，之后可以拖动或删除。',
                                    'Автоматты орналастыру бөлме түріне қарай шам, ажыратқыш, розетка, су-кәріз, желдеткіш және терезе астына радиатор қояды; кейін жылжытып не жоюға болады.',
                                    'Авторасстановка размещает по типу комнаты светильники, выключатели, розетки, водопровод и канализацию, вентиляторы и радиаторы под окнами; затем их можно переместить или удалить.',
                                    'Auto-place puts lights, switches, sockets, water and drains, fans and under-window radiators by room type; you can move or delete them afterwards.',
                                    ky:
                                        'Автоматтык жайгаштыруу бөлмөнүн түрүнө жараша шамдарды, өчүргүчтөрдү, розеткаларды, суу менен агызууну, желдеткичтерди жана терезе алдындагы радиаторлорду коёт; кийин аларды жылдырып же өчүрсөңүз болот.',
                                    uz:
                                        'Avtomatik joylash xona turiga qarab chiroqlar, oʻchirgichlar, rozetkalar, suv va oqova, ventilyatorlar va deraza ostidagi radiatorlarni qoʻyadi; keyin ularni surish yoki oʻchirish mumkin.'),
                                style:
                                    TextStyle(fontSize: 12, color: t.muted))),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          Btn(
                              label: tr3(
                                  '自动布置本层',
                                  'Осы қабатты автоматты',
                                  'Авторасстановка на этаже',
                                  'Auto-place on this floor',
                                  ky: 'Бул кабатта автоматтык жайгаштыруу',
                                  uz: 'Bu qavatda avtomatik joylash'),
                              icon: Icons.auto_fix_high,
                              primary: true,
                              onPressed: () => Navigator.pop(context, 'auto')),
                          if (count > 0)
                            Btn(
                                label:
                                    '${tr3('清除本层点位', 'Қабат нүктелерін өшіру', 'Удалить точки этажа', "Delete this floor's points", ky: 'Бул кабаттын чекиттерин өчүрүү', uz: 'Bu qavat nuqtalarini oʻchirish')} ($count)',
                                icon: Icons.delete_sweep_outlined,
                                danger: true,
                                onPressed: () =>
                                    Navigator.pop(context, 'clear')),
                        ]),
                        for (var g = 0; g < utilityGroups.length; g++) ...[
                          Padding(
                              padding:
                                  const EdgeInsets.only(top: 14, bottom: 6),
                              child: Text(utilityGroupName(g),
                                  style:
                                      TextStyle(fontSize: 12, color: t.muted))),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final kind in utilityGroups[g])
                              Btn(
                                  label: utilityName(kind),
                                  icon: utilityIcon(kind),
                                  onPressed: () =>
                                      Navigator.pop(context, kind)),
                          ]),
                        ],
                      ])));
        });
    if (choice == null || !mounted) return;
    if (choice == 'auto') {
      autoUtilities();
      return;
    }
    if (choice == 'clear') {
      final ids = floorUtilities.length;
      if (action('ClearUtilities', {'floorId': floor.id}) is! Applied) return;
      notify(
          tr3(
              '已清除本层 $ids 个点位',
              'Қабаттағы $ids нүкте өшірілді',
              'Удалено точек на этаже: $ids',
              'Points deleted on this floor: $ids',
              ky: 'Бул кабатта өчүрүлгөн чекиттер: $ids',
              uz: 'Bu qavatda oʻchirilgan nuqtalar: $ids'),
          undo: undo);
      return;
    }
    final kind = choice as UtilityKind;
    update(() {
      cancelDrag();
      clearWallSelection();
      clearSelection();
      showUtilities = true;
      placingUtility = kind;
      tool = EditorTool.placeUtility;
      placementHint = tr3(
          '点平面放置「${utilityName(kind)}」，可连续放置',
          '«${utilityName(kind)}» қою үшін жоспарды басыңыз, бірнеше рет қоюға болады',
          'Нажмите на план, чтобы поставить «${utilityName(kind)}»; можно ставить несколько раз подряд',
          'Tap the plan to place “${utilityName(kind)}”; you can place several in a row',
          ky: '«${utilityName(kind)}» коюу үчүн планды басыңыз; катары менен бир нечесин койсоңуз болот',
          uz: '“${utilityName(kind)}” ni joylash uchun rejaga bosing; ketma-ket bir nechtasini qoʻyish mumkin');
    });
  }

  void autoUtilities() {
    final spots = suggestUtilities(history.present, derived, floorIndex);
    if (spots.isEmpty) {
      notify(tr3(
          '本层已有建议的点位，没有新增',
          'Бұл қабатта ұсынылған нүктелер бар, жаңасы жоқ',
          'На этом этаже рекомендуемые точки уже есть, новых нет',
          'This floor already has the recommended points; nothing new',
          ky: 'Бул кабатта сунушталган чекиттер бар; жаңы эч нерсе жок',
          uz: 'Bu qavatda tavsiya etilgan nuqtalar bor; yangi narsa yoʻq'));
      return;
    }
    update(() => showUtilities = true);
    final placed = action('AddUtilities', {
      'floorId': floor.id,
      'points': [
        for (final s in spots) {'kind': s.kind, 'x': s.x, 'y': s.y}
      ]
    });
    if (placed is! Applied) return;
    notify(
        tr3(
            '已布置 ${spots.length} 个点位，可拖动调整',
            '${spots.length} нүкте қойылды, сүйреп түзетуге болады',
            'Расставлено точек: ${spots.length}, их можно перетаскивать',
            'Points placed: ${spots.length}; you can drag them',
            ky: 'Коюлган чекиттер: ${spots.length}; аларды сүйрөсөңүз болот',
            uz: 'Qoʻyilgan nuqtalar: ${spots.length}; ularni surish mumkin'),
        undo: undo);
  }

  void placeUtilityAt(Offset local, Size size) {
    final kind = placingUtility;
    if (kind == null) return;
    final p = worldAt(local, size);
    final id = const Uuid().v4();
    final before = history.present;
    action('AddUtility', {
      'id': id,
      'floorId': floor.id,
      'kind': kind,
      'x': _FurnitureTool.snap50(p.dx),
      'y': _FurnitureTool.snap50(p.dy),
    });
    if (history.present != before) {
      update(() {
        selectedUtilityId = id;
        panelCollapsed = false;
      });
    }
  }

  /// The point under [local] within a finger's reach.
  UtilityPoint? utilityAt(Offset local, Size size) {
    if (!showUtilities) return null;
    final painter = interactionPainter();
    UtilityPoint? best;
    var bestDistance = 18.0;
    for (final u in floorUtilities) {
      final d = (painter.point(u.x.toDouble(), u.y.toDouble(), size) - local)
              .distance *
          canvasZoom;
      if (d < bestDistance) {
        best = u;
        bestDistance = d;
      }
    }
    return best;
  }

  /// Start dragging the selected point when the press is on it.
  bool beginUtilityGesture(Offset local, Size size) {
    final u = utilityAt(local, size);
    if (u == null || u.id != selectedUtilityId) return false;
    utilityDown = worldAt(local, size);
    utilityDraft = null;
    return true;
  }

  void previewUtility(Offset local, Size size) {
    final u =
        floorUtilities.where((u) => u.id == selectedUtilityId).firstOrNull;
    if (u == null || utilityDown == null) return;
    if (utilityDraft == null &&
        downPoint != null &&
        (local - downPoint!).distance * canvasZoom < 6) {
      return;
    }
    final delta = worldAt(local, size) - utilityDown!;
    utilityDraft = u.copyWith(
        x: _FurnitureTool.snap50(u.x + delta.dx),
        y: _FurnitureTool.snap50(u.y + delta.dy));
    placementHint = tr3('松手放下', 'Жіберіп қойыңыз', 'Отпустите, чтобы поставить',
        'Release to place',
        ky: 'Коюу үчүн коё бериңиз', uz: 'Joylash uchun qoʻyib yuboring');
  }

  /// Returns whether the point moved (otherwise the press was a tap).
  bool finishUtility() {
    final draft = utilityDraft;
    utilityDraft = null;
    utilityDown = null;
    placementHint = null;
    if (draft == null) {
      update(() {});
      return false;
    }
    action(
        'UpdateUtility', {'utilityId': draft.id, 'x': draft.x, 'y': draft.y});
    return true;
  }

  Widget utilityCard(UtilityPoint u) {
    final t = Tokens.of(context);
    return InfoCard(
        titleWidget: Row(children: [
          Icon(utilityIcon(u.kind), size: 18, color: t.ink),
          const SizedBox(width: 6),
          Flexible(
              child: Text(u.label ?? utilityName(u.kind),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        trailing: IconButton(
            tooltip: tr3('关闭', 'Жабу', 'Закрыть', 'Close',
                ky: 'Жабуу', uz: 'Yopish'),
            visualDensity: VisualDensity.compact,
            onPressed: () => update(() => selectedUtilityId = null),
            icon: const Icon(YIcons.close, size: 18)),
        children: [
          KvGrid([
            Kv(utilityName(u.kind),
                tr3('类型', 'Түрі', 'Тип', 'Type', ky: 'Түрү', uz: 'Turi'),
                onTap: () async {
              final kind = await showMotionSheet<UtilityKind>(
                  context: context,
                  builder: (context) => SafeArea(
                          child: ListView(shrinkWrap: true, children: [
                        for (final k in UtilityKind.values)
                          ListTile(
                              contentPadding: tilePad,
                              leading: Icon(utilityIcon(k)),
                              title: Text(utilityName(k)),
                              selected: k == u.kind,
                              onTap: () => Navigator.pop(context, k))
                      ])));
              if (kind != null && kind != u.kind) {
                action('UpdateUtility', {'utilityId': u.id, 'kind': kind});
              }
            }),
            Kv(
                '${m2dp(u.x)}, ${m2dp(u.y)}',
                tr3('位置 (米)', 'Орны (м)', 'Положение (м)', 'Position (m)',
                    ky: 'Орду (м)', uz: 'Joylashuvi (m)'), onTap: () async {
              final x = await length(
                  tr3('离左墙外皮', 'Сол қабырғадан', 'От левой стены',
                      'From the left wall',
                      ky: 'Сол дубалдан', uz: 'Chap devordan'),
                  u.x);
              if (x == null || !mounted) return;
              final y = await length(
                  tr3('离下墙外皮', 'Төменгі қабырғадан', 'От нижней стены',
                      'From the bottom wall',
                      ky: 'Ылдыйкы дубалдан', uz: 'Pastki devordan'),
                  u.y);
              if (y == null) return;
              action('UpdateUtility', {'utilityId': u.id, 'x': x, 'y': y});
            }),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr3('备注', 'Белгі', 'Примечание', 'Note',
                    ky: 'Эскертме', uz: 'Izoh'),
                icon: YIcons.edit,
                onPressed: () async {
                  final v = await askText(
                      tr3(
                          '备注 (如：空调插座 16A)',
                          'Белгі (мысалы: кондиционер 16А)',
                          'Примечание (например: кондиционер 16А)',
                          'Note (e.g. air conditioner 16A)',
                          ky: 'Эскертме (мис., кондиционер 16A)',
                          uz: 'Izoh (masalan, konditsioner 16A)'),
                      u.label ?? '');
                  if (v != null) {
                    action('UpdateUtility',
                        {'utilityId': u.id, 'label': v.trim()});
                  }
                }),
            Btn(
                label: tr3('删除', 'Жою', 'Удалить', 'Delete',
                    ky: 'Өчүрүү', uz: 'Oʻchirish'),
                icon: YIcons.delete,
                danger: true,
                onPressed: () {
                  update(() => selectedUtilityId = null);
                  action('DeleteUtility', {'utilityId': u.id});
                }),
          ]),
          Note(tr3(
              '拖动符号可移动；在“预算”里，电线和水管长度按点位到配电箱、进水套管、排水套管和锅炉的走墙距离估算。',
              'Белгіні сүйреп жылжытыңыз; «Смета» бетінде сым мен құбыр ұзындығы нүктеден электр қалқанына, су және кәріз гильзасына, қазандыққа дейінгі қабырға бойындағы қашықтықпен есептеледі.',
              'Перетащите значок, чтобы переместить его; на странице «Смета» длина провода и труб считается по расстоянию вдоль стен от точки до электрощита, гильз водопровода и канализации, котла.',
              'Drag an icon to move it; on the “Estimate” page wire and pipe lengths are measured along the walls from each point to the electrical panel, the water and drain sleeves, and the boiler.',
              ky: 'Жылдыруу үчүн белгини сүйрөңүз; «Смета» бетинде зым жана түтүк узундуктары ар бир чекиттен электр щитине, суу жана агызуу гильзаларына жана казанга чейин дубалдар боюнча өлчөнөт.',
              uz: 'Surish uchun belgini suring; “Smeta” sahifasida sim va quvur uzunliklari har bir nuqtadan elektr shchitiga, suv va oqova gilzalariga va qozongacha devorlar boʻylab oʻlchanadi.')),
        ]);
  }

  /// Counts and lengths for the house card.
  Widget utilitySummary() {
    final take = utilityTakeoff(history.present);
    if (take.isEmpty) return const SizedBox.shrink();
    return KvGrid([
      Kv(
          '${take.electrical}',
          tr3('电气点位', 'Электр нүктелері', 'Электроточки', 'Electrical points',
              ky: 'Электр чекиттери', uz: 'Elektr nuqtalari')),
      Kv(
          '${money(take.lightCable + take.powerCable)} $unitM',
          tr3('电线约', 'Сым шамамен', 'Провод примерно', 'Wire, approx.',
              ky: 'Зым, болжол менен', uz: 'Sim, taxminan')),
      Kv(
          '${money(take.waterPipe + take.drainPipe)} $unitM',
          tr3('水管约', 'Су құбыры шамамен', 'Водопроводная труба примерно',
              'Water pipe, approx.',
              ky: 'Суу түтүгү, болжол менен', uz: 'Suv quvuri, taxminan')),
      Kv(
          '${take.count(UtilityKind.radiator)}',
          tr3('暖气片', 'Радиатор', 'Радиатор', 'Radiator',
              ky: 'Радиатор', uz: 'Radiator')),
    ]);
  }
}
