import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/document/house_document.dart';
import '../../../core/geometry/derived_house.dart';
import '../../../core/serialization/house_codec.dart';
import '../../../render2d/floor_plan_painter.dart';
import '../../../render3d/scene_view.dart';
import '../../domain/models.dart';
import '../../../app/settings.dart';
import '../scope.dart';
import '../widgets.dart';

HouseDocument? _document(DesignSnapshot? snapshot) {
  final text = snapshot?.planJson;
  if (text == null) return null;
  return loadHouse(utf8.encode(text)).document;
}

/// The ground-floor plan as a cover, for houses published without a
/// picture. Loads the snapshot once and keeps the parsed plan; shows
/// nothing (the cover's placeholder) while loading or if unavailable.
class PlanCover extends StatelessWidget {
  const PlanCover(
      {super.key, required this.snapshotId, this.postId, this.demandId});
  final String snapshotId;
  final String? postId, demandId;

  static final _cache = <String, HouseDocument?>{};

  @override
  Widget build(BuildContext context) => Live<HouseDocument?>(
      reloadKey: 'plan-cover:$snapshotId',
      load: (r) async {
        if (_cache.containsKey(snapshotId)) return _cache[snapshotId];
        try {
          final snap =
              await r.snapshot(snapshotId, postId: postId, demandId: demandId);
          return _cache[snapshotId] = _document(snap);
        } catch (_) {
          return null;
        }
      },
      loading: const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      builder: (context, doc) {
        if (doc == null || doc.floors.isEmpty) return const SizedBox.shrink();
        final derived = deriveHouse(doc).floors.first;
        final rooms = doc.floors.first.rooms;
        return ColoredBox(
            color: const Color(0xfff6f7f3),
            child: CustomPaint(
                painter: FloorPlanPainter(
                    derived.base,
                    {for (final r in rooms) r.id: ''},
                    {for (final r in rooms) r.id: roomColors[r.type]!},
                    openings: derived.openings,
                    stairs: derived.stairs,
                    furniture: doc.extras.furniture,
                    showDimensions: false,
                    showLabels: false,
                    viewportInsets: const EdgeInsets.all(18))));
      });
}

/// Shared public entry point. Never opens the editor or writes local projects.
class PlanAttachment extends StatelessWidget {
  const PlanAttachment(
      {super.key, required this.snapshot, this.hidden = false});
  final DesignSnapshot? snapshot;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final doc = hidden ? null : _document(snapshot);
    final available = !hidden && (doc != null || snapshot?.preview != null);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(tr3('设计图纸', 'Жоба сызбалары', 'Чертежи проекта')),
      YCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (available) ...[
          InkWell(
            onTap: () => _open(context),
            child: SizedBox(
                height: 180,
                child: _Sheet(document: doc, snapshot: snapshot!, floor: 0)),
          ),
          const SizedBox(height: 8),
          Text(doc == null
              ? tr3('旧版附件：仅提供预览图', 'Ескі тіркеме: тек алдын ала көрініс',
                  'Старое вложение: только изображение')
              : tr3(
                  '${doc.floors.length} 层 · 发布时版本 · 只读',
                  '${doc.floors.length} қабат · Жарияланған нұсқа · Тек көру',
                  '${doc.floors.length} эт. · Версия публикации · Только просмотр')),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.open_in_full),
              label: Text(tr3('打开图纸', 'Сызбаны ашу', 'Открыть чертежи'))),
        ] else
          Text(hidden
              ? tr3(
                  '图纸未公开，可联系发布者',
                  'Сызба жарияланбаған, автормен байланысыңыз',
                  'Чертежи скрыты — свяжитесь с автором')
              : tr3(
                  '此内容暂未附可查看的图纸，请联系发布者补充',
                  'Көруге болатын сызба тіркелмеген. Автордан сұраңыз.',
                  'Чертежи пока не приложены. Попросите автора добавить их.')),
      ])),
    ]);
  }

  void _open(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlanViewer(snapshot: snapshot!)));
}

class PlanViewer extends StatefulWidget {
  const PlanViewer({super.key, required this.snapshot});
  final DesignSnapshot snapshot;
  @override
  State<PlanViewer> createState() => _PlanViewerState();
}

class _PlanViewerState extends State<PlanViewer> {
  late HouseDocument? document = _document(widget.snapshot);
  final transform = TransformationController();
  int floor = 0;
  bool threeD = false, roof = true;
  int viewToken = 0;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = document;
    return Scaffold(
      appBar: AppBar(
          title: Text(tr3('图纸 · 只读', 'Сызба · Тек көру', 'Чертежи · Просмотр')),
          actions: [
            IconButton(
                tooltip: tr3(
                    '重置缩放', 'Масштабты қалпына келтіру', 'Сбросить масштаб'),
                onPressed: () => setState(() { transform.value = Matrix4.identity(); viewToken++; }),
                icon: const Icon(Icons.fit_screen)),
          ]),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
                '${widget.snapshot.projectName} · ${widget.snapshot.extractedAt.toIso8601String().substring(0, 10)}')),
        if (doc != null) ...[
          SegmentedButton<bool>(segments: const [
            ButtonSegment(value: false, label: Text('2D')),
            ButtonSegment(value: true, label: Text('3D')),
          ], selected: {threeD}, onSelectionChanged: (v) => setState(() => threeD = v.single)),
          if (threeD) FilterChip(label: Text(tr3('显示屋顶', 'Шатырды көрсету', 'Показать крышу')),
            selected: roof, onSelected: (v) => setState(() => roof = v)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButton<int>(
                isExpanded: true,
                value: floor,
                items: [
                  for (var i = 0; i < doc.floors.length; i++)
                    DropdownMenuItem(
                        value: i,
                        child: Text('${i + 1} · ${doc.floors[i].name}'))
                ],
                onChanged: (value) {
                  if (value != null)
                    setState(() {
                      floor = value;
                      transform.value = Matrix4.identity();
                    });
                },
              )),
        ],
        Expanded(
            child: threeD && doc != null
                ? SceneView(doc: doc, derived: deriveHouse(doc), roomName: (r) => r.name,
                    settings: SceneSettings(roof: roof, furniture: false, site: false),
                    walk: false, viewToken: viewToken)
                : ClipRect(
                child: InteractiveViewer(
          transformationController: transform,
          minScale: 1,
          maxScale: 8,
          child: SizedBox.expand(
              child: _Sheet(
                  document: doc, snapshot: widget.snapshot, floor: floor)),
        ))),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text(tr3(
                '双指缩放、拖动查看。设计图不替代专业施工图。',
                'Екі саусақпен үлкейтіп, жылжытыңыз. Бұл кәсіби құрылыс сызбасы емес.',
                'Масштабируйте двумя пальцами и перемещайте. План не заменяет рабочую документацию.'))),
      ])),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet(
      {required this.document, required this.snapshot, required this.floor});
  final HouseDocument? document;
  final DesignSnapshot snapshot;
  final int floor;
  @override
  Widget build(BuildContext context) {
    final doc = document;
    if (doc == null) {
      final bytes = snapshot.preview;
      if (bytes == null)
        return Center(
            child:
                Text(tr3('图纸暂不可用', 'Сызба қолжетімсіз', 'Чертежи недоступны')));
      return Image.memory(Uint8List.fromList(bytes),
          fit: BoxFit.contain,
          errorBuilder: (_, error, stack) => Center(
              child: Text(tr3('预览图无法读取', 'Көріністі оқу мүмкін емес',
                  'Не удалось прочитать изображение'))));
    }
    final derived = deriveHouse(doc).floors[floor];
    return ColoredBox(
        color: const Color(0xfff6f7f3),
        child: CustomPaint(
          painter: FloorPlanPainter(
              derived.base,
              {for (final room in doc.floors[floor].rooms) room.id: room.name},
              {
                for (final room in doc.floors[floor].rooms)
                  room.id: roomColors[room.type]!
              },
              openings: derived.openings,
              stairs: derived.stairs,
              northAngleDeg: doc.footprint.northAngleDeg),
        ));
  }
}
