import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/home/state/plan_cover.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/serialization/house_codec.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/engine/render2d/furniture_names.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';

HouseDocument? _document(DesignSnapshot? snapshot) {
  final text = snapshot?.planJson;
  if (text == null) return null;
  return loadHouse(utf8.encode(text)).document;
}

/// The ground-floor plan as a cover, for houses published without a
/// picture. Loads the snapshot once and keeps the parsed, derived plan;
/// shows nothing (the cover's paper) while loading or if unavailable.
///
/// Once loaded it draws in the very first frame: a house page, or the
/// card's picture flying into it, builds a new cover, and waiting a frame
/// for the cache would flash the empty placeholder.
class PlanCover extends StatelessWidget {
  const PlanCover(
      {super.key, required this.snapshotId, this.postId, this.demandId});
  final String snapshotId;
  final String? postId;
  final String? demandId;

  static final _cache = <String, _CoverPlan?>{};

  @override
  Widget build(BuildContext context) {
    if (_cache.containsKey(snapshotId)) {
      return _CoverSheet(plan: _cache[snapshotId]);
    }
    return Live<DesignSnapshot?>(
        provider: coverSnapshotProvider((snapshotId, postId, demandId)),
        loading: const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        builder: (context, snap) => _CoverSheet(
            plan: _cache.containsKey(snapshotId)
                ? _cache[snapshotId]
                : _cache[snapshotId] = _CoverPlan.of(_document(snap))));
  }
}

/// A plan ready to paint: derived once, not on every frame of a flight.
class _CoverPlan {
  _CoverPlan(this.doc, this.floor);
  final HouseDocument doc;
  final DerivedFloor floor;

  static _CoverPlan? of(HouseDocument? doc) => doc == null || doc.floors.isEmpty
      ? null
      : _CoverPlan(doc, deriveHouse(doc).floors.first);
}

class _CoverSheet extends StatelessWidget {
  const _CoverSheet({required this.plan});
  final _CoverPlan? plan;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    if (p == null) return const SizedBox.shrink();
    final rooms = p.doc.floors.first.rooms;
    return RepaintBoundary(
        child: ColoredBox(
            color: YTokens.paper,
            child: CustomPaint(
                painter: FloorPlanPainter(
                    p.floor.base,
                    {for (final r in rooms) r.id: ''},
                    {for (final r in rooms) r.id: roomColors[r.type]!},
                    openings: p.floor.openings,
                    stairs: p.floor.stairs,
                    furniture: p.doc.extras.furniture,
                    showDimensions: false,
                    showLabels: false,
                    viewportInsets: const EdgeInsets.all(18)))));
  }
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
      SectionTitle(tr3('设计图纸', 'Жоба сызбалары', 'Чертежи проекта', 'Design drawings', ky: 'Долбоордун чиймелери', uz: 'Loyiha chizmalari')),
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
                  'Старое вложение: только изображение',
                  'Old attachment: image only', ky: 'Эски тиркеме: сүрөт гана', uz: 'Eski ilova: faqat rasm')
              : tr3(
                  '${doc.floors.length} 层 · 发布时版本 · 只读',
                  '${doc.floors.length} қабат · Жарияланған нұсқа · Тек көру',
                  '${doc.floors.length} эт. · Версия публикации · Только просмотр',
                  '${doc.floors.length} fl. · Published version · View only', ky: '${doc.floors.length} каб. · Жарыяланган версия · Көрүү гана', uz: '${doc.floors.length} qav. · Eʼlon qilingan versiya · Faqat koʻrish')),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.open_in_full),
              label: Text(tr3('打开图纸', 'Сызбаны ашу', 'Открыть чертежи', 'Open drawings', ky: 'Чиймелерди ачуу', uz: 'Chizmalarni ochish'))),
        ] else
          Text(hidden
              ? tr3(
                  '图纸未公开，可联系发布者',
                  'Сызба жарияланбаған, автормен байланысыңыз',
                  'Чертежи скрыты — свяжитесь с автором',
                  'Drawings are hidden; contact the author', ky: 'Чиймелер жашырылган; автор менен байланышыңыз', uz: 'Chizmalar yashirilgan; muallif bilan bogʻlaning')
              : tr3(
                  '此内容暂未附可查看的图纸，请联系发布者补充',
                  'Көруге болатын сызба тіркелмеген. Автордан сұраңыз.',
                  'Чертежи пока не приложены. Попросите автора добавить их.',
                  'No drawings attached yet. Ask the author to add them.', ky: 'Азырынча чиймелер тиркелген жок. Авторду аларды кошууну сураныңыз.', uz: 'Hozircha chizmalar biriktirilmagan. Muallifdan ularni qoʻshishni soʻrang.')),
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
  bool threeD = false;
  bool roof = true;
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
          title: Text(tr3('图纸 · 只读', 'Сызба · Тек көру', 'Чертежи · Просмотр', 'Drawings · View', ky: 'Чиймелер · Көрүү', uz: 'Chizmalar · Koʻrish')),
          actions: [
            IconButton(
                tooltip: tr3(
                    '重置缩放', 'Масштабты қалпына келтіру', 'Сбросить масштаб', 'Reset zoom', ky: 'Масштабды баштапкы абалга келтирүү', uz: 'Masshtabni asliga qaytarish'),
                onPressed: () => setState(() {
                      transform.value = Matrix4.identity();
                      viewToken++;
                    }),
                icon: const Icon(Icons.fit_screen)),
          ]),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
                '${widget.snapshot.projectName} · ${fmtDay(widget.snapshot.extractedAt)}')),
        if (doc != null) ...[
          SegmentedButton<bool>(segments: const [
            ButtonSegment(value: false, label: Text('2D')),
            ButtonSegment(value: true, label: Text('3D')),
          ], selected: {
            threeD
          }, onSelectionChanged: (v) => setState(() => threeD = v.single)),
          if (threeD)
            FilterChip(
                label: Text(tr3('显示屋顶', 'Шатырды көрсету', 'Показать крышу', 'Show the roof', ky: 'Чатырды көрсөтүү', uz: 'Tomni koʻrsatish')),
                selected: roof,
                onSelected: (v) => setState(() => roof = v)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButton<int>(
                isExpanded: true,
                value: floor,
                items: [
                  for (var i = 0; i < doc.floors.length; i++)
                    DropdownMenuItem(
                        value: i,
                        child: Text(
                            '${i + 1} · ${floorDisplayName(doc.floors[i].name)}'))
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      floor = value;
                      transform.value = Matrix4.identity();
                    });
                  }
                },
              )),
        ],
        Expanded(
            child: threeD && doc != null
                ? SceneView(
                    doc: doc,
                    derived: deriveHouse(doc),
                    roomName: shownRoomName,
                    settings: SceneSettings(
                        roof: roof, furniture: false, site: false),
                    walk: false,
                    viewToken: viewToken)
                : ClipRect(
                    child: InteractiveViewer(
                    transformationController: transform,
                    minScale: 1,
                    maxScale: 8,
                    child: SizedBox.expand(
                        child: _Sheet(
                            document: doc,
                            snapshot: widget.snapshot,
                            floor: floor)),
                  ))),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text(tr3(
                '双指缩放、拖动查看。设计图不替代专业施工图。',
                'Екі саусақпен үлкейтіп, жылжытыңыз. Бұл кәсіби құрылыс сызбасы емес.',
                'Масштабируйте двумя пальцами и перемещайте. План не заменяет рабочую документацию.',
                "Pinch to zoom and drag to move. The plan doesn't replace working drawings.", ky: 'Чоңойтуу үчүн кыпчып, жылдыруу үчүн сүйрөңүз. План иштөөчү чиймелерди алмаштырбайт.', uz: 'Kattalashtirish uchun qisib-oching, surish uchun suring. Reja ishchi chizmalarni almashtirmaydi.'))),
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
      if (bytes == null) {
        return Center(
            child:
                Text(tr3('图纸暂不可用', 'Сызба қолжетімсіз', 'Чертежи недоступны', 'Drawings unavailable', ky: 'Чиймелер жеткиликсиз', uz: 'Chizmalar mavjud emas')));
      }
      return Image.memory(imageBytes(bytes),
          fit: BoxFit.contain,
          errorBuilder: (_, error, stack) => Center(
              child: Text(tr3('预览图无法读取', 'Көріністі оқу мүмкін емес',
                  'Не удалось прочитать изображение',
                  "Couldn't read the image", ky: 'Сүрөттү окуу мүмкүн болбоду', uz: 'Rasmni oʻqib boʻlmadi'))));
    }
    final derived = deriveHouse(doc).floors[floor];
    return ColoredBox(
        color: YTokens.paper,
        child: CustomPaint(
          painter: FloorPlanPainter(
              derived.base,
              {
                for (final room in doc.floors[floor].rooms)
                  room.id: shownRoomName(room)
              },
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
