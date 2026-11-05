part of '../house_editor.dart';

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
                  height: math.min(MediaQuery.sizeOf(context).height * 0.75, 520),
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Text(tr('水电暖点位', 'Су, электр, жылу нүктелері'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 10),
                            child: Text(
                                tr('自动布置会按房间类型放灯、开关、插座、给排水、排气扇和窗下暖气片，之后可以拖动或删除。',
                                    'Автоматты орналастыру бөлме түріне қарай шам, ажыратқыш, розетка, су-кәріз, желдеткіш және терезе астына радиатор қояды; кейін жылжытып не жоюға болады.'),
                                style: TextStyle(fontSize: 12, color: t.muted))),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          Btn(
                              label: tr('自动布置本层', 'Осы қабатты автоматты'),
                              icon: Icons.auto_fix_high,
                              primary: true,
                              onPressed: () => Navigator.pop(context, 'auto')),
                          if (count > 0)
                            Btn(
                                label: '${tr('清除本层点位', 'Қабат нүктелерін өшіру')} ($count)',
                                icon: Icons.delete_sweep_outlined,
                                danger: true,
                                onPressed: () => Navigator.pop(context, 'clear')),
                        ]),
                        for (var g = 0; g < utilityGroups.length; g++) ...[
                          Padding(
                              padding: const EdgeInsets.only(top: 14, bottom: 6),
                              child: Text(utilityGroupName(g),
                                  style: TextStyle(fontSize: 12, color: t.muted))),
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
      action('ClearUtilities', {'floorId': floor.id});
      notify(tr('已清除本层 $ids 个点位', 'Қабаттағы $ids нүкте өшірілді'), undo: undo);
      return;
    }
    final kind = choice as UtilityKind;
    update(() {
      cancelDrag();
      clearWallSelection();
      clearSelection();
      showUtilities = true;
      placingUtility = kind;
      tool = 'placeUtility';
      browse = false;
      placementHint = tr('点平面放置「${utilityName(kind)}」，可连续放置',
          '«${utilityName(kind)}» қою үшін жоспарды басыңыз, бірнеше рет қоюға болады');
    });
  }

  void autoUtilities() {
    final spots = suggestUtilities(history.present, derived, floorIndex);
    if (spots.isEmpty) {
      notify(tr('本层已有建议的点位，没有新增', 'Бұл қабатта ұсынылған нүктелер бар, жаңасы жоқ'));
      return;
    }
    update(() => showUtilities = true);
    action('AddUtilities', {
      'floorId': floor.id,
      'points': [
        for (final s in spots) {'kind': s.kind, 'x': s.x, 'y': s.y}
      ]
    });
    notify(
        tr('已布置 ${spots.length} 个点位，可拖动调整', '${spots.length} нүкте қойылды, сүйреп түзетуге болады'),
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
    if (history.present != before)
      update(() {
        selectedUtilityId = id;
        panelCollapsed = false;
      });
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
    final u = floorUtilities.where((u) => u.id == selectedUtilityId).firstOrNull;
    if (u == null || utilityDown == null) return;
    if (utilityDraft == null &&
        downPoint != null &&
        (local - downPoint!).distance * canvasZoom < 6) return;
    final delta = worldAt(local, size) - utilityDown!;
    utilityDraft = u.copyWith(
        x: _FurnitureTool.snap50(u.x + delta.dx),
        y: _FurnitureTool.snap50(u.y + delta.dy));
    placementHint = tr('松手放下', 'Жіберіп қойыңыз');
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
    action('UpdateUtility', {'utilityId': draft.id, 'x': draft.x, 'y': draft.y});
    return true;
  }

  Widget utilityCard(UtilityPoint u) {
    final t = Tokens.of(context);
    return InfoCard(
        titleWidget: Row(children: [
          Icon(utilityIcon(u.kind), size: 18, color: t.accent),
          const SizedBox(width: 6),
          Flexible(
              child: Text(u.label ?? utilityName(u.kind),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        trailing: IconButton(
            tooltip: tr('关闭', 'Жабу'),
            visualDensity: VisualDensity.compact,
            onPressed: () => update(() => selectedUtilityId = null),
            icon: const Icon(Icons.close, size: 18)),
        children: [
          KvGrid([
            Kv(utilityName(u.kind), tr('类型', 'Түрі'), onTap: () async {
              final kind = await showMotionSheet<UtilityKind>(
                  context: context,
                  builder: (context) => SafeArea(
                          child: ListView(shrinkWrap: true, children: [
                        for (final k in UtilityKind.values)
                          ListTile(
                              leading: Icon(utilityIcon(k)),
                              title: Text(utilityName(k)),
                              selected: k == u.kind,
                              onTap: () => Navigator.pop(context, k))
                      ])));
              if (kind != null && kind != u.kind)
                action('UpdateUtility', {'utilityId': u.id, 'kind': kind});
            }),
            Kv('${m2dp(u.x)}, ${m2dp(u.y)}', tr('位置 (米)', 'Орны (м)'),
                onTap: () async {
              final x = await length(tr('离左墙外皮', 'Сол қабырғадан'), u.x);
              if (x == null || !mounted) return;
              final y = await length(tr('离下墙外皮', 'Төменгі қабырғадан'), u.y);
              if (y == null) return;
              action('UpdateUtility', {'utilityId': u.id, 'x': x, 'y': y});
            }),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr('备注', 'Белгі'),
                icon: Icons.edit_outlined,
                onPressed: () async {
                  final v = await askText(tr('备注 (如：空调插座 16A)', 'Белгі (мысалы: кондиционер 16А)'),
                      u.label ?? '');
                  if (v != null)
                    action('UpdateUtility',
                        {'utilityId': u.id, 'label': v.trim()});
                }),
            Btn(
                label: tr('删除', 'Жою'),
                icon: Icons.delete_outline,
                danger: true,
                onPressed: () {
                  update(() => selectedUtilityId = null);
                  action('DeleteUtility', {'utilityId': u.id});
                }),
          ]),
          Note(tr('拖动符号可移动；在“预算”里，电线和水管长度按点位到配电箱、进水套管、排水套管和锅炉的走墙距离估算。',
              'Белгіні сүйреп жылжытыңыз; «Смета» бетінде сым мен құбыр ұзындығы нүктеден электр қалқанына, су және кәріз гильзасына, қазандыққа дейінгі қабырға бойындағы қашықтықпен есептеледі.')),
        ]);
  }

  /// Counts and lengths for the house card.
  Widget utilitySummary() {
    final take = utilityTakeoff(history.present);
    if (take.isEmpty) return const SizedBox.shrink();
    return KvGrid([
      Kv('${take.electrical}', tr('电气点位', 'Электр нүктелері')),
      Kv('${money(take.lightCable + take.powerCable)} $unitM', tr('电线约', 'Сым шамамен')),
      Kv('${money(take.waterPipe + take.drainPipe)} $unitM', tr('水管约', 'Су құбыры шамамен')),
      Kv('${take.count(UtilityKind.radiator)}', tr('暖气片', 'Радиатор')),
    ]);
  }
}
