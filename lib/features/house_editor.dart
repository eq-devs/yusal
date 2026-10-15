import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/house_core.dart';
import '../core/commands/room_commands.dart';
import '../core/geometry/floor_base.dart';
import '../core/history/design_history.dart';
import '../core/commands/delete_axis.dart';
import '../core/commands/house_templates.dart';
import '../core/commands/kz_template.dart';
import '../core/geometry/derived_house.dart';
import '../core/checks/check_engine.dart';
import '../render3d/scene_view.dart';
import '../render2d/floor_plan_painter.dart';
import '../render2d/project_preview.dart';
import '../storage/project_store.dart';
import '../storage/house_import.dart';
import '../storage/last_open.dart';
import 'footprint_sketch.dart';
import 'wall_length_dialog.dart';
import 'wall_attachment_points.dart';
import 'wall_snap.dart';
import '../app/messages.dart';
import '../app/settings.dart';
import '../app/tokens.dart';
import '../app/ui.dart';
import '../core/analysis/house_analysis.dart';
import '../core/analysis/design_summary.dart';
import '../core/commands/extras_commands.dart';
import '../render2d/furniture_names.dart';
import '../render2d/section_painters.dart';
import '../core/checks/construction_checks.dart';

part 'editor/editor_header.dart';
part 'editor/plan_tab.dart';
part 'editor/selection_cards.dart';
part 'editor/furniture_tool.dart';
part 'editor/other_tabs.dart';
part 'editor/scene_tab.dart';
part 'editor/home_screen.dart';
part 'editor/compare_card.dart';

class HouseEditor extends StatefulWidget {
  const HouseEditor(
      {super.key,
      required this.entry,
      required this.store,
      this.initialView3d = false,
      this.initialTool,
      this.compareWithId});
  final bool initialView3d;
  final String? initialTool;

  /// Another design to compare with, e.g. the one this scheme was copied from.
  final String? compareWithId;
  final ProjectEntry entry;
  final ProjectStore store;
  @override
  State<HouseEditor> createState() => _HouseEditorState();
}

class _HouseEditorState extends State<HouseEditor>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final DesignHistory history;
  late FloorBase base;
  late DerivedHouse derived;
  /// Current page: plan, ext (3D), walk, det, qty or iss.
  String tab = 'plan';
  bool get view3d => tab != 'plan';
  set view3d(bool value) {
    if (value != view3d) tab = value ? 'ext' : 'plan';
  }

  /// Plan layers, the selection shown in the card, and transient marks.
  bool showFurniture = true, showDimensions = true, showFoundation = false;
  bool panelCollapsed = false;

  /// Short-screen layout, decided by the last build.
  bool compact = false;
  List<Offset> measurePoints = [];
  String? selectedRoomId, selectedOpeningId, selectedFurnitureId;
  FurnitureKind? placingFurniture;

  /// Furniture being moved, resized or turned: the live preview, the grip
  /// and where the press started (plan millimetres).
  FurnitureItem? furnitureDraft;
  String? furnitureGrip;
  Offset? furnitureDown;
  List<PlanRect> highlights = [];
  Level? issueFilter;

  /// The design shown in the scheme comparison.
  String? compareId;
  HouseDocument? compareDoc;

  /// 3D page state, kept while switching pages.
  SceneSettings sceneSettings = const SceneSettings();
  String sceneView = 'iso';
  int sceneViewToken = 0;
  SourceRef? scenePicked;

  /// Where the walk-through starts; a new token moves the walker there.
  ({int floorIndex, double x, double y, double yaw, int token})? walkStart;
  late final AnimationController pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  final barsKey = GlobalKey();

  void update(VoidCallback fn) => setState(fn);

  /// Keep messages above the tool rows.
  double get snackLift {
    final box = barsKey.currentContext?.findRenderObject() as RenderBox?;
    return (box?.hasSize ?? false) ? box!.size.height + 16 : 16;
  }

  List<(String, String)> get editorTabs => [
        ('plan', tr('2D 平面', '2D жоспар')),
        ('ext', tr('3D 外观', '3D сыртқы көрініс')),
        ('walk', tr('室内漫游', 'Ішкі серуен')),
        ('det', tr('构造细节', 'Құрылым бөлшектері')),
        ('qty', tr('门窗与工程量', 'Есік-терезе және көлем')),
        ('iss', tr('问题清单', 'Мәселелер тізімі')),
      ];

  void showTab(String value) {
    if (value == tab) return;
    setState(() {
      cancelDrag();
      clearWallSelection();
      tab = value;
      if (value != 'plan') {
        tool = 'browse';
        browse = true;
        drawingOrigin = null;
        drawingEnd = null;
        placementHint = null;
      }
    });
  }

  Widget tabBody(bool wide) => switch (tab) {
        'plan' => planTab(wide),
        'ext' || 'walk' => sceneTab(wide),
        'det' => detailsTab(wide),
        'qty' => quantitiesTab(wide),
        _ => issuesTab(wide),
      };

  void clearSelection() {
    selectedRoomId = null;
    selectedOpeningId = null;
    selectedFurnitureId = null;
    furnitureDraft = null;
    furnitureGrip = null;
  }

  /// Delete key: the selected wall, furniture or door/window.
  void deleteSelection() {
    if (editStart != null) {
      deleteSelectedWall();
    } else if (selectedFurnitureId != null) {
      final id = selectedFurnitureId!;
      setState(clearSelection);
      action('DeleteFurniture', {'furnitureId': id});
    } else if (selectedOpeningId != null) {
      final opening = floor.openings
          .where((o) => o.id == selectedOpeningId)
          .firstOrNull;
      if (opening != null) {
        setState(clearSelection);
        action('DeleteOpening', {'openingId': opening.id});
      }
    }
  }

  /// Floors named automatically ("一楼", "二楼 副本") follow the language.
  String displayFloorName(String name) {
    const numerals = '一二三四五六七八九十';
    final m = RegExp(r'^([一二三四五六七八九十])楼( 副本)?$').firstMatch(name);
    if (m == null || !isKk) return name;
    final n = numerals.indexOf(m[1]!) + 1;
    return '$n-қабат${m[2] == null ? '' : ' (көшірме)'}';
  }

  /// Rooms keep the name the user gave; automatic names follow the language.
  String displayRoomName(Room r) {
    for (final e in roomNames.entries)
      if (r.name == e.value) return roomTypeName(e.key);
    return r.name;
  }

  /// Flash plan areas (issue locations) until the next edit or tap.
  void flash(List<PlanRect> areas) {
    highlights = areas;
    if (areas.isEmpty || MediaQuery.disableAnimationsOf(context)) {
      pulse.stop();
      pulse.value = 0;
    } else {
      // A few beats to draw the eye, then the area stays marked.
      pulse
        ..value = 0
        ..repeat(reverse: true, count: 6);
    }
  }

  String tool = 'browse';
  PlanRect? focus;
  Offset? spatialStart, spatialEnd;
  FloorPlanPainter? dragCoordinatePainter;
  WallSegment? selectedWall;
  PlanRect? spatialPreview;
  String? spatialError;
  HouseDocument? spatialDocument;
  FloorBase? spatialBase;

  final canvasKey = GlobalKey();
  final canvasTransform = TransformationController();
  /// Room around the plan inside its sheet for dimension chains, the
  /// north arrow and the zoom buttons.
  EdgeInsets get canvasInsets => const EdgeInsets.fromLTRB(52, 60, 60, 60);

  FloorPlanPainter interactionPainter() =>
      FloorPlanPainter(base, {}, {}, viewportInsets: canvasInsets);

  OpeningKind? placingOpening;
  Map<String, dynamic>? openingDrop;
  String? placementHint;

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
    }).toList();
    walls.sort((a, b) => ((a.axis.dir == AxisDir.H ? world.y : world.x) -
            a.axis.pos)
        .abs()
        .compareTo(((b.axis.dir == AxisDir.H ? world.y : world.x) - b.axis.pos)
            .abs()));
    final wall = walls.firstOrNull;
    openingDrop = null;
    derive();
    if (wall == null) {
      placementHint = tr('拖到墙上，门窗会自动贴合', 'Қабырғаға апарыңыз, есік-терезе өзі орнығады');
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
      placementHint = tr('已贴合墙面，松手放置', 'Қабырғаға орнықты, жіберіңіз');
    } else {
      placementHint = result is Rejected ? result.message : tr('此处无法放置', 'Мұнда қоюға болмайды');
    }
  }

  /// Tool names: Chinese key → (Chinese short, Kazakh full, Kazakh short).
  static const toolText = {
    '浏览': ('浏览', 'Шолу', 'Шолу'),
    '墙体': ('墙体', 'Қабырға салу', 'Қабырға'),
    '独立墙': ('独立墙', 'Бөлек қабырға', 'Бөлек'),
    '拉线分房': ('分房', 'Сызықпен бөлу', 'Бөлу'),
    '拖动划房': ('框房', 'Бөлме сызу', 'Бөлме'),
    '拖入门': ('门', 'Есік қосу', 'Есік'),
    '拖入窗': ('窗', 'Терезе қосу', 'Терезе'),
    '家具': ('家具', 'Жиһаз қою', 'Жиһаз'),
    '更多工具': ('更多', 'Басқа құралдар', 'Басқа'),
    '墙体调整': ('改墙', 'Қабырғаны түзету', 'Түзету'),
    '房屋尺寸': ('房屋尺寸', 'Үй өлшемі', 'Өлшем'),
  };

  String toolLabel(String label) {
    final text = toolText[label];
    if (text == null) return label;
    return isKk ? text.$3 : text.$1;
  }

  String toolTip(String label) {
    final text = toolText[label];
    return text == null || !isKk ? label : text.$2;
  }

  Widget basicTool(
      IconData icon, String label, bool selected, VoidCallback onTap) {
    final t = Tokens.of(context);
    return Semantics(
        button: true,
        selected: selected,
        label: toolTip(label),
        child: Tooltip(
            message: toolTip(label),
            child: Material(
                color: selected ? Tokens.mix(t.accent, 0.14, t.panel) : t.panel,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: selected ? t.accent : t.line,
                        width: selected ? 1.5 : 1)),
                child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      cancelDrag();
                      closeWallMenu();
                      spatialDocument = null;
                      spatialBase = null;
                      spatialError = null;
                      spatialStart = null;
                      spatialEnd = null;
                      spatialPreview = null;
                      placementHint = null;
                      placingFurniture = null;
                      measurePoints = [];
                      onTap();
                      if (mounted) setState(() {});
                    },
                    child: SizedBox(
                        width: math.max(
                            52,
                            MediaQuery.textScalerOf(context).scale(11) *
                                    (toolLabel(label).length *
                                        (isKk ? 0.62 : 1.0)) +
                                14),
                        height: math.max(
                            50, MediaQuery.textScalerOf(context).scale(11) + 38),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon,
                                  size: 21, color: selected ? t.accent : t.ink),
                              const SizedBox(height: 3),
                              Text(toolLabel(label),
                                  maxLines: 1,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: selected ? t.accent : t.ink,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w400))
                            ]))))));
  }

  Future<void> footprintOptions() async {
    final width = TextEditingController(
        text: (history.present.footprint.width / 1000).toStringAsFixed(2));
    final depth = TextEditingController(
        text: (history.present.footprint.depth / 1000).toStringAsFixed(2));
    String? error;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => SafeArea(
                child: SingleChildScrollView(
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 20, 20,
                            MediaQuery.viewInsetsOf(context).bottom + 20),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(tr('房屋长宽', 'Үйдің ені мен ұзындығы'),
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600)),
                              Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(tr('外形尺寸用于全部楼层。内部房间位置保持不变。', 'Сыртқы өлшем барлық қабатқа қолданылады. Ішкі бөлмелердің орны сақталады.'))),
                              TextField(
                                  controller: width,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                      labelText: tr('宽（米，左右方向）', 'Ені (м, солдан оңға)'))),
                              TextField(
                                  controller: depth,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                      labelText: tr('长（米，上下方向）', 'Ұзындығы (м, төменнен жоғары)'))),
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              const SizedBox(height: 16),
                              FilledButton(
                                  onPressed: () {
                                    final w = double.tryParse(width.text),
                                        d = double.tryParse(depth.text);
                                    if (w == null ||
                                        d == null ||
                                        !w.isFinite ||
                                        !d.isFinite ||
                                        w < 3 ||
                                        d < 3 ||
                                        w > 100 ||
                                        d > 100) {
                                      update(() => error = tr('长宽需在 3–100 米之间', 'Өлшем 3–100 м аралығында болуы керек'));
                                      return;
                                    }
                                    final args = <String, dynamic>{
                                      'width': (w * 1000).round(),
                                      'depth': (d * 1000).round()
                                    };
                                    final result = executeCommand(
                                        presentState,
                                        DesignCommand('SetFootprintSize', args),
                                        CommandContext(
                                            newId: () => const Uuid().v4(),
                                            now: () => 'unused'));
                                    if (result is Rejected) {
                                      update(() => error = result.message);
                                      return;
                                    }
                                    Navigator.pop(context);
                                    action('SetFootprintSize', args);
                                  },
                                  child: Text(tr('应用尺寸', 'Өлшемді қолдану'))),
                              TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    setState(() {
                                      view3d = false;
                                      browse = false;
                                      tool = 'resize';
                                      placementHint = null;
                                    });
                                  },
                                  icon: const Icon(Icons.open_in_full),
                                  label: Text(tr('拖动外边框调整', 'Сыртқы жиекті сүйреп өзгерту'))),
                            ]))))));
  }

  Future<void> moreTools() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: math.min(MediaQuery.sizeOf(context).height * 0.7, 500),
                child: ListView(children: [
                  Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(tr('更多工具', 'Басқа құралдар'),
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600))),
                  for (final entry in {
                    'fit': tr('恢复画布视角', 'Көріністі қалпына келтіру'),
                    'grid': tr('网格', 'Тор'),
                    'opening': tr('门窗', 'Есік-терезе'),
                    'stair': tr('楼梯', 'Баспалдақ'),
                    for (final type in RoomType.values)
                      type.name: roomTypeName(type),
                    'erase': tr('擦除', 'Өшіру')
                  }.entries)
                    ListTile(
                        title: Text(entry.value),
                        onTap: () => Navigator.pop(context, entry.key)),
                ]))));
    if (choice == null || !mounted) return;
    if (choice == 'fit') {
      canvasTransform.value = Matrix4.identity();
      return;
    }
    setState(() {
      browse = false;
      erase = choice == 'erase';
      placementHint = null;
      if (['grid', 'opening', 'stair'].contains(choice))
        tool = choice;
      else {
        tool = 'room';
        if (!erase) brush = RoomType.values.firstWhere((t) => t.name == choice);
      }
    });
  }

  OpeningKind? draggingNewOpening;

  String openingName(Opening o) => switch (o) {
        DoorOpening() => tr('门', 'есік'),
        WindowOpening() => tr('窗', 'терезе'),
        SlidingOpening() => tr('推拉门', 'сырғымалы есік')
      };

  Map<OpeningKind, String> get openingNames => {
        OpeningKind.door: tr('门', 'есік'),
        OpeningKind.window: tr('窗', 'терезе'),
        OpeningKind.sliding: tr('推拉门', 'сырғымалы есік')
      };

  /// The dragged door or window floats above the finger so the snapped
  /// preview on the wall stays visible. Its arrow tip, not the finger, is
  /// where it lands.
  static const openingDragAnchor = Offset(36, 104);
  static const openingDropPoint = Offset(36, 76);

  Widget openingTool(OpeningKind kind, IconData icon, String label) {
    final button = basicTool(
        icon, label, tool == 'placeOpening' && placingOpening == kind, () {
      placingOpening = kind;
      browse = false;
      tool = 'placeOpening';
      placementHint = tr('点一下墙面放置，也可以从工具栏直接拖入', 'Қабырғаны басып қойыңыз, не құралдар жолынан сүйреп әкеліңіз');
    });
    return Draggable<OpeningKind>(
        data: kind,
        // Sideways swipes scroll the tool row; dragging up takes the item.
        affinity: Axis.vertical,
        dragAnchorStrategy: (_, __, ___) => openingDragAnchor,
        feedback: Material(
            color: Colors.transparent,
            child: Container(
                width: 72,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(blurRadius: 8, color: Color(0x33000000))
                    ]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 28),
                  Text(openingNames[kind]!,
                      style: const TextStyle(fontSize: 13)),
                  const Icon(Icons.arrow_downward, size: 16),
                ]))),
        onDragStarted: () => setState(() {
              cancelDrag();
              clearWallSelection();
              draggingNewOpening = kind;
            }),
        onDragEnd: (_) => setState(() {
              draggingNewOpening = null;
              openingDrop = null;
              placementHint = null;
              derive();
            }),
        child: button);
  }

  bool get spatialTool => tool == 'box' || tool == 'split';

  void updateSpatial(Offset point, Size size) {
    final painter = interactionPainter();
    final world = painter.worldPoint(point, size);
    int snap(double value, List<ResolvedAxis> axes) {
      final clamped = value.round().clamp(axes.first.pos, axes.last.pos);
      for (final axis in axes) {
        if ((axis.pos - clamped).abs() <
            math.min(12 / painter.scale(size), 250)) return axis.pos;
      }
      return (clamped / 100).round() * 100;
    }

    spatialEnd = Offset(snap(world.x, base.axes.v).toDouble(),
        snap(world.y, base.axes.h).toDouble());
    spatialStart ??= spatialEnd;
    if (tool == 'split') {
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
        tool == 'box' &&
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
    final arguments = tool == 'split'
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
    final result = executeCommand(
        presentState,
        DesignCommand(tool == 'split' ? 'SplitSpace' : 'CarveRoom', arguments),
        CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
    spatialError = result is Rejected ? result.message : null;
    if (result is Applied) {
      spatialDocument = composeDocument(history.present.meta, result.newState);
      spatialBase = deriveFloorBase(spatialDocument!, floor.id);
      final count = spatialDocument!.floors
          .firstWhere((f) => f.id == floor.id)
          .rooms
          .length;
      placementHint =
          count > floor.rooms.length + 1 ? tr('分房后会得到 $count 个独立空间，松手完成', 'Бөлгенде $count бөлек кеңістік шығады, жіберіңіз') : null;
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
      setState(() {});
      notify(message);
      return;
    }
    final rectangle = spatialPreview;
    if (tool == 'split' &&
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
      setState(() {});
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

  Offset? downPoint;
  int floorIndex = 0;
  RoomType brush = RoomType.living;
  bool browse = true, erase = false, dirty = false, saving = false;
  String status = '已保存';
  final stroke = <Cell>[];
  final pointers = <int>{};
  bool cancelledStroke = false;
  Offset? lastPoint;
  ResolvedAxis? draggingAxis;
  OpeningPlacement? draggingOpening;
  Map<String, dynamic>? dragArguments;
  String? dragKind;
  bool dragged = false, dragAttempted = false, dragValid = false;
  Timer? timer;
  Future<void>? pendingSave;
  Floor get floor => history.present.floors[floorIndex];

  /// The current design state, extracted once per document so repeated
  /// previews during a drag reuse it (and its cached validation).
  UndoableDesignState get presentState {
    if (!identical(presentSource, history.present)) {
      presentSource = history.present;
      cachedPresentState = extractDesignState(history.present);
    }
    return cachedPresentState!;
  }

  HouseDocument? presentSource;
  UndoableDesignState? cachedPresentState;
  @override
  void initState() {
    super.initState();
    canvasTransform.addListener(onCanvasTransformChanged);
    if (widget.initialView3d) tab = 'ext';
    if (widget.compareWithId != null)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadCompare(widget.compareWithId!);
      });
    history = DesignHistory(widget.entry.document);
    LastOpenProject.write(widget.entry.id);
    derive();
    if (widget.initialTool == 'drawWall') startWallDrawing();
    if (widget.initialTool == 'wallContext') {
      final wall =
          base.wallSegments.firstWhere((w) => w.axis.kind != 'boundary');
      final point = wall.axis.dir == AxisDir.H
          ? Offset(
              (wall.start.pos + wall.end.pos) / 2, wall.axis.pos.toDouble())
          : Offset(
              wall.axis.pos.toDouble(), (wall.start.pos + wall.end.pos) / 2);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => showWallContext(wall, point));
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  void onCanvasTransformChanged() {
    if (mounted) setState(() {});
  }

  void derive() {
    floorIndex = floorIndex.clamp(0, history.present.floors.length - 1);
    derived = deriveHouse(history.present);
    base = derived.floors[floorIndex].base;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) save();
  }

  @override
  void dispose() {
    LastOpenProject.write(null);
    wallHoldTimer?.cancel();
    previewTimer?.cancel();
    canvasTransform.removeListener(onCanvasTransformChanged);
    canvasTransform.dispose();
    pulse.dispose();
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> save() async {
    timer?.cancel();
    while (pendingSave != null) {
      await pendingSave;
    }
    if (!dirty) return;
    final operation = saveOnce();
    pendingSave = operation;
    try {
      await operation;
    } finally {
      if (identical(pendingSave, operation)) pendingSave = null;
    }
  }

  Future<void> saveOnce() async {
    final doc = history.present;
    var failed = false;
    saving = true;
    try {
      await widget.store.saveProject(widget.entry.id, doc);
      if (mounted)
        setState(() {
          dirty = history.present != doc;
          status = dirty ? '未保存' : '已保存';
        });
    } catch (_) {
      failed = true;
      if (mounted) {
        final firstFailure = status != '保存失败';
        setState(() => status = '保存失败');
        if (firstFailure) notify(tr('没能保存到本机，请检查存储空间；稍后会自动再试，也可点右上角保存', 'Құрылғыға сақталмады, жадты тексеріңіз; кейін өзі қайта көреді, не «Сақтау» батырмасын басыңыз'));
      }
    } finally {
      saving = false;
      if (failed && mounted)
        timer = Timer(const Duration(seconds: 5), save);
      else if (dirty && history.present != doc)
        timer = Timer(const Duration(milliseconds: 1500), save);
    }
  }

  void changed() {
    focus = null;
    if (highlights.isNotEmpty) flash(const []);
    derive();
    dirty = true;
    status = '未保存';
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 1500), save);
  }

  void beginDrag(Offset point, Size size) {
    if (tool == 'selectWall') return;
    draggingAxis = null;
    draggingOpening = null;
    dragArguments = null;
    dragKind = null;
    dragged = false;
    dragAttempted = false;
    dragValid = false;
    final painter = interactionPainter(), scale = painter.scale(size);
    dragCoordinatePainter = painter;
    final x = painter.worldPoint(point, size).x,
        y = painter.worldPoint(point, size).y,
        tolerance = 12 / scale;
    if (tool == 'wall' && selectedWall != null) {
      final wall = selectedWall!;
      final along = (wall.start.pos + wall.end.pos) / 2;
      final center = wall.axis.dir == AxisDir.V
          ? painter.point(wall.axis.pos.toDouble(), along, size)
          : painter.point(along, wall.axis.pos.toDouble(), size);
      if ((point - center).distance <= 24) draggingAxis = wall.axis;
    } else if (tool == 'resize') {
      final width = history.present.footprint.width.toDouble(),
          depth = history.present.footprint.depth.toDouble();
      final reach = 28 / canvasZoom;
      if ((point - painter.point(width, depth / 2, size)).distance <= reach) {
        draggingAxis = base.axes.v.last;
      } else if ((point - painter.point(width / 2, depth, size)).distance <=
          reach) {
        draggingAxis = base.axes.h.last;
      }
    } else if (tool == 'grid') {
      final axes = base.axes.all
          .where((a) =>
              a.kind != 'boundary' &&
              ((a.dir == AxisDir.V ? x : y) - a.pos).abs() <= tolerance)
          .toList();
      axes.sort((a, b) => ((a.dir == AxisDir.V ? x : y) - a.pos)
          .abs()
          .compareTo(((b.dir == AxisDir.V ? x : y) - b.pos).abs()));
      draggingAxis = axes.firstOrNull;
    } else if (tool == 'opening' || browse) {
      draggingOpening = openingAt(point, size);
    }
  }

  /// The door or window under [local], nearest first, with a screen-sized
  /// tolerance so it stays easy to grab at any zoom.
  OpeningPlacement? openingAt(Offset local, Size size) {
    final painter = interactionPainter(),
        world = painter.worldPoint(local, size),
        tolerance = 14 / (painter.scale(size) * canvasZoom);
    final hits = derived.floors[floorIndex].openings.where((p) {
      final along = p.axis.dir == AxisDir.H ? world.x : world.y,
          cross = p.axis.dir == AxisDir.H ? world.y : world.x;
      return along >= p.start - tolerance &&
          along <= p.end + tolerance &&
          (cross - p.axis.pos).abs() <= tolerance;
    }).toList()
      ..sort((a, b) =>
          ((a.axis.dir == AxisDir.H ? world.y : world.x) - a.axis.pos)
              .abs()
              .compareTo(
                  ((b.axis.dir == AxisDir.H ? world.y : world.x) - b.axis.pos)
                      .abs()));
    return hits.firstOrNull;
  }

  /// Start moving a placed door or window from any wall tool.
  bool beginOpeningDrag(Offset local, Size size) {
    final hit = openingAt(local, size);
    if (hit == null) return false;
    draggingAxis = null;
    dragArguments = null;
    dragKind = null;
    dragged = false;
    dragAttempted = false;
    dragValid = false;
    dragCoordinatePainter = interactionPainter();
    draggingOpening = hit;
    return true;
  }

  void previewDrag(Offset point, Size size) {
    if (downPoint == null || (downPoint! - point).distance < 8 && !dragged)
      return;
    dragAttempted = true;
    dragValid = false;
    final painter = dragCoordinatePainter ?? interactionPainter();
    final x = painter.worldPoint(point, size).x,
        y = painter.worldPoint(point, size).y;
    if (draggingAxis != null) {
      final axis = draggingAxis!;
      if (tool == 'wall' && selectedWall != null) {
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
        var low = 0,
            high = axis.dir == AxisDir.V
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
          'pos': (axis.dir == AxisDir.V ? x : y).round().clamp(low, high)
        };
      }
    } else if (draggingOpening != null) {
      final opening = draggingOpening!;
      final originalBase = deriveFloorBase(history.present, floor.id);
      final tolerance = 28 / painter.scale(size);
      final candidates = originalBase.wallSegments.where((wall) {
        final along = wall.axis.dir == AxisDir.H ? x : y;
        final cross = wall.axis.dir == AxisDir.H ? y : x;
        return along >= wall.start.pos &&
            along <= wall.end.pos &&
            (cross - wall.axis.pos).abs() <= tolerance;
      }).toList();
      candidates.sort((a, b) => ((a.axis.dir == AxisDir.H ? y : x) - a.axis.pos)
          .abs()
          .compareTo(((b.axis.dir == AxisDir.H ? y : x) - b.axis.pos).abs()));
      final wall = candidates.firstOrNull;
      if (wall == null) {
        placementHint = tr('拖到另一面墙，门窗会自动贴合', 'Басқа қабырғаға апарыңыз, есік-терезе өзі орнығады');
        return;
      }
      final along = wall.axis.dir == AxisDir.H ? x : y;
      final available = wall.end.pos - wall.start.pos - opening.opening.width;
      if (available < 0) {
        placementHint = tr('这段墙放不下这个门窗', 'Бұл қабырғаға есік-терезе сыймайды');
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
    final result = executeCommand(
        presentState,
        DesignCommand(dragKind!, dragArguments!),
        CommandContext(
            newId: () => const Uuid().v4(), now: () => '1970-01-01T00:00:00Z'));
    if (result is Applied) {
      placementHint = null;
      dragged = true;
      dragValid = true;
      derived =
          deriveHouse(composeDocument(history.present.meta, result.newState));
      base = derived.floors[floorIndex].base;
    } else if (result is Rejected) {
      derive();
      placementHint = result.message;
    }
  }

  void cancelDrag() {
    wallHoldTimer?.cancel();
    if (pointers.isNotEmpty) cancelledStroke = true;
    spatialStart = null;
    spatialEnd = null;
    spatialPreview = null;
    downPoint = null;
    if (tool == 'drawWall' && drawingStrokeActive)
      drawingOrigin = drawingBefore;
    drawingStrokeActive = false;
    drawingBefore = null;
    drawingEnd = null;
    spatialError = null;
    wallGrip = null;
    editPreviewStart = null;
    editPreviewEnd = null;
    editDown = null;
    editCommand = null;
    editArgs = null;
    drawConnected = false;
    resetPreview();
    spatialDocument = null;
    spatialBase = null;
    draggingAxis = null;
    draggingOpening = null;
    dragArguments = null;
    dragKind = null;
    dragged = false;
    dragAttempted = false;
    dragValid = false;
    furnitureDraft = null;
    furnitureGrip = null;
    furnitureDown = null;
    derive();
  }

  void sample(Offset p, Size size) {
    final painter = interactionPainter();
    final x = painter.worldPoint(p, size).x, y = painter.worldPoint(p, size).y;
    final i = base.axes.v.indexWhere((a) => a.pos > x) - 1,
        j = base.axes.h.indexWhere((a) => a.pos > y) - 1;
    if (i >= 0 && j >= 0 && i < base.axes.nx && j < base.axes.ny) {
      final c = Cell(i, j);
      if (!stroke.contains(c)) stroke.add(c);
    }
  }

  void record(Offset p, Size size) {
    if (lastPoint != null) {
      final delta = p - lastPoint!;
      final steps = math.max(1, (delta.distance / 3).ceil());
      for (var i = 1; i <= steps; i++)
        sample(lastPoint! + delta * (i / steps), size);
    } else {
      sample(p, size);
    }
    lastPoint = p;
  }

  Future<void> export() async {
    try {
      await save();
      final raw = encodeHouse(history.present);
      final cleanedName = history.present.meta.name
          .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '')
          .trim();
      final filename = '${cleanedName.isEmpty ? tr('房屋设计', 'Үй жобасы') : cleanedName}.house';
      final file = XFile.fromData(utf8.encode(raw),
          mimeType: 'application/json', name: filename);
      if (kIsWeb) {
        await file.saveTo(filename);
      } else {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
            files: [file],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size));
      }
    } catch (_) {
      notify(tr('暂时无法导出这个设计', 'Жобаны қазір шығару мүмкін емес'));
    }
  }

  void placeOpening(Map<String, dynamic> arguments) {
    final before = history.present;
    action('AddOpening', arguments);
    if (history.present != before)
      notify(
          tr('已放置${openingNames[arguments['kind']]} · 可以直接拖动它调整位置',
              '${openingNames[arguments['kind']]} қойылды · оны сүйреп жылжытуға болады'),
          undo: undo);
  }

  /// Short floating message above the tool card; [undo] adds an undo button.
  void notify(String message, {VoidCallback? undo}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        content: Text(coreMessage(message)),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, snackLift),
        duration: Duration(milliseconds: undo == null ? 2500 : 6000),
        // Undo also stays in the header, so the message need not linger.
        persist: false,
        action: undo == null
            ? null
            : SnackBarAction(label: tr('撤销', 'Болдырмау'), onPressed: undo)));
  }

  /// Forget a start point or selection that the document no longer has.
  void dropStaleWallState() {
    clearWallSelection();
    drawingEnd = null;
    final seed = drawingOrigin;
    if (seed != null &&
        !base.wallSegments.any((w) =>
            (w.axis.dir == AxisDir.H ? seed.dy : seed.dx) == w.axis.pos &&
            (w.axis.dir == AxisDir.H ? seed.dx : seed.dy) >= w.start.pos &&
            (w.axis.dir == AxisDir.H ? seed.dx : seed.dy) <= w.end.pos))
      drawingOrigin = null;
  }

  void undo() {
    if (!history.canUndo) return;
    setState(() {
      cancelDrag();
      history.undo();
      changed();
      dropStaleWallState();
      if (tool == 'editWall') {
        tool = 'browse';
        browse = true;
      }
    });
    notify(tr('已撤销上一步', 'Соңғы әрекет болдырылмады'));
  }

  void redo() {
    if (!history.canRedo) return;
    setState(() {
      cancelDrag();
      history.redo();
      changed();
      dropStaleWallState();
      if (tool == 'editWall') {
        tool = 'browse';
        browse = true;
      }
    });
    notify(tr('已重做', 'Қайталанды'));
  }

  void action(String kind, Map<String, dynamic> args) {
    final result = executeCommand(
        presentState,
        DesignCommand(kind, args),
        CommandContext(
            newId: () => const Uuid().v4(),
            now: () => DateTime.now().toUtc().toIso8601String()));
    if (result is Applied) {
      setState(() {
        if (history.commit(
            composeDocument(history.present.meta, result.newState))) changed();
      });
    } else {
      final message = result is Rejected
          ? result.message
          : (result as NeedsResolution).conflict.message;
      notify(message);
    }
  }

  Future<String?> ask(String label, String value, {bool number = false}) async {
    final controller = TextEditingController(text: value);
    return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(label),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: number
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('取消', 'Болдырмау'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: Text(tr('确定', 'Жарайды')))
                ]));
  }

  Future<int?> length(String label, int value) async {
    final result =
        await ask(tr('$label（米）', '$label (м)'), (value / 1000).toStringAsFixed(2),
        number: true);
    final parsed = double.tryParse(result ?? '');
    if (parsed == null || !parsed.isFinite) return null;
    return (parsed * 1000).round();
  }

  Future<void> floorOptions() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final entry in {
                'AddFloor': tr('新增空层', 'Бос қабат қосу'),
                'CopyFloor': tr('复制本层', 'Қабатты көшіру'),
                'RenameFloor': tr('楼层名称', 'Қабат атауы'),
                'SetFloorHeight': tr('层高', 'Қабат биіктігі'),
                'DeleteFloor': tr('删除本层', 'Қабатты жою')
              }.entries)
                ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(context, entry.key))
            ])));
    if (choice == null) return;
    if (choice == 'SetFloorHeight') {
      final value = await length(tr('层高', 'Қабат биіктігі'), floor.height);
      if (value != null) action(choice, {'floorId': floor.id, 'value': value});
    } else if (choice == 'RenameFloor') {
      final value = await ask(tr('楼层名称', 'Қабат атауы'), floor.name);
      if (value != null) action(choice, {'floorId': floor.id, 'value': value});
    } else {
      if (choice == 'DeleteFloor') {
        final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: Text(tr('删除本层及其全部内容？', 'Қабатты бүкіл ішімен жою керек пе?')),
                    content: Text(tr('本层房间和门窗将删除。删除顶层时，下层通向本层的楼梯也会删除。', 'Қабаттағы бөлмелер мен есік-терезелер жойылады. Жоғарғы қабат жойылса, оған апаратын баспалдақ та жойылады.')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(tr('取消', 'Болдырмау'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(tr('删除', 'Жою')))
                    ]));
        if (yes != true) return;
      }
      final before = history.present, index = floorIndex;
      action(choice, {
        'floorId': floor.id,
        if (choice == 'DeleteFloor') 'deleteStairs': true
      });
      if (history.present == before || !mounted) return;
      setState(() {
        cancelDrag();
        clearWallSelection();
        drawingOrigin = null;
        floorIndex = choice == 'DeleteFloor'
            ? math.min(index, history.present.floors.length - 1)
            : index + 1;
        derive();
      });
      notify(choice == 'DeleteFloor'
          ? tr('已删除楼层，现在是「${displayFloorName(floor.name)}」',
              'Қабат жойылды, қазір «${displayFloorName(floor.name)}»')
          : tr('已新增「${displayFloorName(floor.name)}」，现在编辑这一层',
              '«${displayFloorName(floor.name)}» қосылды, енді осы қабатты өзгертесіз'));
    }
  }

  Future<void> settings() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final e in {
                'width': tr('房屋宽度', 'Үйдің ені'),
                'depth': tr('房屋进深', 'Үйдің тереңдігі'),
                'north': tr('正北方向', 'Солтүстік бағыты'),
                'flat': tr('平屋顶', 'Тегіс шатыр'),
                'gable': tr('双坡屋顶', 'Қос беткейлі шатыр'),
                'grid': tr('编辑网格', 'Торды өзгерту'),
                'defaults': tr('默认尺寸', 'Әдепкі өлшемдер')
              }.entries)
                ListTile(
                    title: Text(e.value),
                    onTap: () => Navigator.pop(context, e.key))
            ])));
    if (choice == 'width' || choice == 'depth') {
      final value = await length(
          choice == 'width' ? tr('房屋宽度', 'Үйдің ені') : tr('房屋进深', 'Үйдің тереңдігі'),
          choice == 'width'
              ? history.present.footprint.width
              : history.present.footprint.depth);
      if (value != null) action('SetFootprintSize', {choice!: value});
    }
    if (choice == 'flat') {
      final height =
          await length(tr('女儿墙高度', 'Парапет биіктігі'), history.present.roof.parapetHeight ?? 900);
      if (height != null)
        action('SetRoof', {
          'roof': {'type': 'flat', 'parapetHeight': height}
        });
    }
    if (choice == 'gable') {
      final pitchText = await ask(
          tr('屋顶坡度（5–60°）', 'Шатыр еңісі (5–60°)'), '${history.present.roof.pitchDeg ?? 30}',
          number: true);
      if (pitchText == null) return;
      final pitch = int.tryParse(pitchText);
      if (pitch == null) return;
      final overhang =
          await length(tr('屋檐伸出', 'Карниз шығыңқылығы'), history.present.roof.overhang ?? 500);
      if (overhang == null) return;
      final direction = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                ListTile(
                    title: Text(tr('屋脊沿进深方向', 'Жота тереңдік бойымен')),
                    onTap: () => Navigator.pop(context, 'V')),
                ListTile(
                    title: Text(tr('屋脊沿宽度方向', 'Жота ені бойымен')),
                    onTap: () => Navigator.pop(context, 'H')),
              ])));
      if (direction != null)
        action('SetRoof', {
          'roof': {
            'type': 'gable',
            'ridgeDir': direction,
            'pitchDeg': pitch,
            'overhang': overhang
          }
        });
    }
    if (choice == 'defaults') {
      final raw =
          jsonDecode(encodeHouse(history.present)) as Map<String, dynamic>;
      final defaults = raw['defaults'] as Map<String, dynamic>;
      final labels = {
        'outerWallThickness': tr('外墙厚度', 'Сыртқы қабырға қалыңдығы'),
        'innerWallThickness': tr('内墙厚度', 'Ішкі қабырға қалыңдығы'),
        'slabThickness': tr('楼板厚度', 'Плита қалыңдығы'),
        'stairRiserMax': tr('楼梯最大步高', 'Баспалдақтың ең үлкен биіктігі'),
        'stairTread': tr('楼梯踏步进深', 'Баспалдақ табанының тереңдігі'),
        'stairWidthMin': tr('楼梯最小宽度', 'Баспалдақтың ең аз ені'),
        'floorHeight': tr('默认层高', 'Әдепкі қабат биіктігі'),
        'doorWidth': tr('默认门宽', 'Әдепкі есік ені'),
        'doorHeight': tr('默认门高', 'Әдепкі есік биіктігі'),
        'windowWidth': tr('默认窗宽', 'Әдепкі терезе ені'),
        'windowHeight': tr('默认窗高', 'Әдепкі терезе биіктігі'),
        'windowSill': tr('默认窗台高度', 'Әдепкі терезе алды биіктігі')
      };
      final field = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final entry in labels.entries)
                  ListTile(
                      title: Text(entry.value),
                      subtitle:
                          Text('${dec(((defaults[entry.key] as int) / 1000).toString())} $unitM'),
                      onTap: () => Navigator.pop(context, entry.key)),
              ])));
      if (field != null) {
        final value = await length(labels[field]!, defaults[field] as int);
        if (value != null)
          action('SetDefault', {'field': field, 'value': value});
      }
    }
    if (choice == 'north') {
      final value = await showModalBottomSheet<int>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final angle in [0, 90, 180, 270])
                  ListTile(
                      title: Text(tr('正北指向 $angle°', 'Солтүстік $angle° бағытта')),
                      onTap: () => Navigator.pop(context, angle))
              ])));
      if (value != null) action('SetNorthAngle', {'value': value});
    }
    if (choice == 'grid') grid();
  }

  Future<void> grid() async {
    final selected = await showModalBottomSheet<Object>(
        context: context,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: 360,
                child: ListView(children: [
                  ListTile(
                      title: Text(tr('新增竖向分隔线', 'Тік бөлу сызығын қосу')),
                      onTap: () => Navigator.pop(context, AxisDir.V)),
                  ListTile(
                      title: Text(tr('新增横向分隔线', 'Көлденең бөлу сызығын қосу')),
                      onTap: () => Navigator.pop(context, AxisDir.H)),
                  for (final axis
                      in base.axes.all.where((a) => a.kind != 'boundary'))
                    ListTile(
                        title: Text(
                            tr('${axis.dir == AxisDir.V ? '竖' : '横'}线 · ${(axis.pos / 1000).toStringAsFixed(2)} 米',
                                '${axis.dir == AxisDir.V ? 'Тік' : 'Көлденең'} сызық · ${m2dp(axis.pos)} м')),
                        onTap: () => Navigator.pop(context, axis))
                ]))));
    if (selected is AxisDir) {
      final value = await length(
          tr('新分隔线位置', 'Жаңа сызықтың орны'),
          selected == AxisDir.V
              ? history.present.footprint.width ~/ 2
              : history.present.footprint.depth ~/ 2);
      if (value != null) {
        final scope = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  ListTile(
                      title: Text(tr('所有楼层', 'Барлық қабат')),
                      onTap: () => Navigator.pop(context, 'global')),
                  ListTile(
                      title: Text(tr('仅本层', 'Тек осы қабат')),
                      onTap: () => Navigator.pop(context, 'floor')),
                ])));
        if (scope != null)
          action('AddAxis', {
            'dir': selected,
            'pos': value,
            if (scope == 'floor') 'floorId': floor.id
          });
      }
    }
    if (selected is ResolvedAxis) {
      final operation = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
          ListTile(
              title: Text(tr('修改位置', 'Орнын өзгерту')),
              onTap: () => Navigator.pop(context, 'move')),
          if (selected.kind == 'floor')
            ListTile(
                title: Text(tr('同步到所有楼层', 'Барлық қабатқа тарату')),
                onTap: () => Navigator.pop(context, 'promote')),
          ListTile(
              title: Text(tr('删除分隔线', 'Сызықты жою')),
              onTap: () => Navigator.pop(context, 'delete')),
        ])),
      );
      if (operation == 'move') {
        final value = await length(tr('分隔线位置', 'Сызықтың орны'), selected.pos);
        if (value != null)
          action('MoveAxis', {'axisId': selected.id, 'pos': value});
      }
      if (operation == 'promote')
        action('PromoteFloorAxis', {'axisId': selected.id});
      if (operation == 'delete') {
        var result =
            deleteAxis(history.present, selected.id, () => const Uuid().v4());
        if (result.needsResolution && mounted) {
          final resolution = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                    title: Text(tr('删除分隔线', 'Сызықты жою')),
                    content: Text(
                        '${coreMessage(result.message ?? '')}\n${result.hasHosted ? tr('这条线上的门窗和墙设置将删除。\n', 'Осы сызықтағы есік-терезе мен қабырға баптаулары жойылады.\n') : ''}${result.hasStairs ? tr('受影响的楼梯将删除。\n', 'Әсер ететін баспалдақтар жойылады.\n') : ''}${tr('请选择合并后保留的房间。', 'Біріктірген соң қалатын бөлмені таңдаңыз.')}'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr('取消', 'Болдырмау'))),
                      for (final entry in {
                        'mergeRooms': tr('合并房间', 'Бөлмелерді біріктіру'),
                        'keepLowSide': tr('保留左 / 下侧', 'Сол / төменгі жағын қалдыру'),
                        'keepHighSide': tr('保留右 / 上侧', 'Оң / жоғарғы жағын қалдыру')
                      }.entries)
                        TextButton(
                            onPressed: () => Navigator.pop(context, entry.key),
                            child: Text(entry.value)),
                    ],
                  ));
          if (resolution == null) return;
          result = deleteAxis(
              history.present, selected.id, () => const Uuid().v4(),
              resolution: resolution,
              deleteHostedObjects: true,
              deleteStairs: true);
        }
        if (!mounted) return;
        if (result.document != null) {
          setState(() {
            if (history.commit(
                withExtras(result.document!, history.present.extras))) changed();
          });
        } else {
          notify(result.message ?? tr('无法删除分隔线', 'Сызықты жою мүмкін емес'));
        }
      }
    }
  }

  void pick3d(SourceRef? source) {
    PlanRect? selected;
    int? index;
    if (source is WallSource) {
      final wallRef = source.wall;
      index = history.present.floors.indexWhere((f) => f.id == wallRef.floorId);
      if (index >= 0) {
        final b = derived.floors[index].base;
        final w = b.wallSegments.indexWhere((w) => w.ref == wallRef);
        if (w >= 0) selected = b.wallRects[w];
      }
    } else if (source is OpeningSource || source is StairSource) {
      for (var i = 0; i < derived.floors.length; i++) {
        final g = derived.floors[i];
        if (source is OpeningSource) {
          final p = g.openings
              .where((p) => p.opening.id == source.openingId)
              .firstOrNull;
          if (p != null) {
            final cross = p.axis.pos.toDouble();
            selected = p.axis.dir == AxisDir.H
                ? PlanRect(p.start, cross, p.end, cross)
                : PlanRect(cross, p.start, cross, p.end);
            index = i;
          }
        } else if (source is StairSource) {
          final stair =
              g.stairs.where((s) => s.stairId == source.stairId).firstOrNull;
          if (stair != null) {
            selected = stair.opening;
            index = i;
          }
        }
      }
    }
    if (selected != null && index != null && index >= 0)
      setState(() {
        floorIndex = index!;
        view3d = false;
        browse = true;
        tool = 'browse';
        derive();
        focus = selected;
      });
  }

  Future<void> tapObject(Offset point, Size size) async {
    final painter = interactionPainter();
    // Tolerances are screen pixels, so they stay finger-sized at any zoom.
    final x = painter.worldPoint(point, size).x,
        y = painter.worldPoint(point, size).y,
        tolerance = 14 / (painter.scale(size) * canvasZoom);
    final placements = derived.floors[floorIndex].openings.where((p) {
      final along = p.axis.dir == AxisDir.H ? x : y,
          cross = p.axis.dir == AxisDir.H ? y : x;
      return along >= p.start - tolerance &&
          along <= p.end + tolerance &&
          (cross - p.axis.pos).abs() < tolerance;
    }).toList()
      ..sort((a, b) => ((a.axis.dir == AxisDir.H ? y : x) - a.axis.pos)
          .abs()
          .compareTo(((b.axis.dir == AxisDir.H ? y : x) - b.axis.pos).abs()));
    final opening = placements.firstOrNull;
    if (opening != null && tool != 'selectWall') {
      selectOpening(opening.opening);
      return;
    }
    final cellI = base.axes.v.indexWhere((a) => a.pos > x) - 1,
        cellJ = base.axes.h.indexWhere((a) => a.pos > y) - 1;
    final roomHere = base.owners[Cell(cellI, cellJ)];
    final piece = furnitureAtWorld(Offset(x, y));
    // Rugs cover rooms: the first tap picks the room, the next the rug.
    if (piece != null &&
        tool != 'selectWall' &&
        (!isFlatFurniture(piece.kind) ||
            (roomHere != null && roomHere == selectedRoomId) ||
            roomHere == null)) {
      setState(() {
        clearSelection();
        clearWallSelection();
        selectedFurnitureId = piece.id;
        panelCollapsed = false;
        placementHint = null;
      });
      return;
    }
    final wall = wallAtPoint(point, size, radius: 16);
    if (wall != null) {
      setState(clearSelection);
      if (wall.axis.kind != 'boundary') {
        setState(
            () => showWallContext(wall, attachmentOnWall(wall, point, size)));
        return;
      }
      final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final entry in {
                  'door': tr('门', 'Есік'),
                  'window': tr('窗', 'Терезе'),
                  'sliding': tr('推拉门', 'Сырғымалы есік'),
                  if (wall.axis.kind != 'boundary') 'move': tr('拖动这段墙', 'Қабырғаны сүйреу'),
                  if (wall.axis.kind != 'boundary') 'position': tr('精确调整这段墙', 'Қабырғаны дәл орналастыру'),
                  'open': tr('开放（无墙）', 'Ашық (қабырғасыз)'),
                  'thickness': tr('调整墙厚', 'Қалыңдығын өзгерту'),
                  'default': tr('恢复默认墙', 'Әдепкі қабырғаны қайтару')
                }.entries)
                  ListTile(
                      title: Text(entry.value),
                      onTap: () => Navigator.pop(context, entry.key))
              ])));
      if (choice == null) return;
      if (choice == 'move') {
        setState(() {
          selectedWall = wall;
          tool = 'wall';
          browse = false;
          placementHint = null;
        });
        return;
      }
      if (choice == 'position') {
        final value = await length(
            wall.axis.dir == AxisDir.V ? tr('距左侧外墙', 'Сол жақ сыртқы қабырғадан') : tr('距下侧外墙', 'Төменгі сыртқы қабырғадан'), wall.axis.pos);
        if (value != null)
          action('MoveLocalWall',
              {'floorId': floor.id, 'anchor': wall.ref.anchor, 'pos': value});
        return;
      }
      if (['door', 'window', 'sliding'].contains(choice)) {
        action('AddOpening', {
          'floorId': floor.id,
          'anchor': wall.ref.anchor,
          'kind': OpeningKind.values.firstWhere((k) => k.name == choice),
          'tapT': ((wall.axis.dir == AxisDir.H ? x : y) - wall.start.pos)
              .clamp(0, wall.end.pos - wall.start.pos)
        });
      } else {
        int? thickness;
        if (choice == 'thickness')
          thickness = await length(tr('墙厚', 'Қабырға қалыңдығы'), wall.thickness.round());
        if (choice != 'thickness' || thickness != null)
          action('SetWallOverride', {
            'floorId': floor.id,
            'anchor': wall.ref.anchor,
            'type': choice,
            'value': thickness
          });
      }
      return;
    }
    if (tool == 'editWall' || menuWall != null) {
      // A tap beside the selected wall just ends the selection.
      setState(() {
        clearWallSelection();
        if (tool == 'editWall') {
          tool = 'browse';
          browse = true;
        }
        placementHint = null;
      });
      return;
    }
    final i = base.axes.v.indexWhere((a) => a.pos > x) - 1,
        j = base.axes.h.indexWhere((a) => a.pos > y) - 1;
    final id = base.owners[Cell(i, j)];
    final room = floor.rooms.where((r) => r.id == id).firstOrNull;
    if (room != null) {
      setState(() {
        clearSelection();
        selectedRoomId = room.id;
        panelCollapsed = false;
        if (highlights.isNotEmpty) flash(const []);
      });
      return;
    }
    if (id == null)
      setState(() {
        clearSelection();
        if (highlights.isNotEmpty) flash(const []);
      });
    final stair = floor.stairs.where((s) => s.id == id).firstOrNull;
    if (stair != null) {
      final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final e in {
                  'straight': tr('直梯', 'Тік баспалдақ'),
                  'L': tr('L 型楼梯', 'L тәрізді баспалдақ'),
                  'U': tr('U 型楼梯', 'U тәрізді баспалдақ'),
                  'turn': tr('切换转向', 'Бұрылысын ауыстыру'),
                  'start': tr('切换起步边', 'Басталатын жағын ауыстыру'),
                  'delete': tr('删除楼梯', 'Баспалдақты жою')
                }.entries)
                  ListTile(
                      title: Text(e.value),
                      onTap: () => Navigator.pop(context, e.key))
              ])));
      if (choice == null) return;
      if (choice == 'delete')
        action('DeleteStair', {'stairId': stair.id});
      else if (choice == 'turn')
        action('UpdateStair', {
          'stairId': stair.id,
          'turn': stair is TurnStair && stair.turn == StairTurn.left
              ? 'right'
              : 'left'
        });
      else if (choice == 'start')
        action('UpdateStair', {
          'stairId': stair.id,
          'startEdge': StairEdge.values[(stair.startEdge.index + 1) % 4].name
        });
      else
        action('UpdateStair', {'stairId': stair.id, 'type': choice});
    }
  }

  /// Show the card of [opening]; it can also be dragged on the plan.
  void selectOpening(Opening opening) => setState(() {
        clearSelection();
        clearWallSelection();
        selectedOpeningId = opening.id;
        panelCollapsed = false;
      });

  Offset? drawingOrigin, drawingEnd;

  /// Floating sheet over the plan (wall menu, live status).
  Widget floatingSurface(Widget child) {
    final t = Tokens.of(context);
    return Material(
        color: t.panel,
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: t.line)),
        child: child);
  }

  String? selectedDrawnId;
  BoundaryAnchor? selectedDrawnAnchor;
  Offset? editStart, editEnd, editPreviewStart, editPreviewEnd, editDown;
  String? wallGrip;

  /// Command and arguments of the wall edit being previewed, so release
  /// commits exactly what the preview showed.
  String? editCommand;
  Map<String, dynamic>? editArgs;

  /// Current single-finger gesture in the wall tools: 'draw' from a plus,
  /// 'edit' on the selected wall, 'tap' until it moves, then 'pan'.
  String? wallGesture;
  Offset? gestureScreen;
  bool drawConnected = false;

  /// Wall whose nearby action menu is open, and the pressed point on it.
  WallSegment? menuWall;
  Offset? menuPoint;
  Size canvasSize = Size.zero;
  bool coachDismissed = false;

  void closeWallMenu() {
    menuWall = null;
    menuPoint = null;
  }

  void clearWallSelection() {
    closeWallMenu();
    selectedWall = null;
    selectedDrawnId = null;
    selectedDrawnAnchor = null;
    editStart = null;
    editEnd = null;
  }

  void selectWallForEdit(WallSegment wall, double x, double y,
      {bool keepTool = false}) {
    final along = wall.axis.dir == AxisDir.V ? y : x;
    final solid = floor.wallOverrides.whereType<SolidWall>().where((w) {
      final c = resolveAnchor(base.axes, w.anchor).chain!;
      return c.carrier.id == wall.axis.id &&
          c.startPos <= along &&
          c.endPos >= along;
    }).firstOrNull;
    final a = solid?.anchor ?? wall.ref.anchor;
    final c = resolveAnchor(base.axes, a).chain!;
    setState(() {
      cancelDrag();
      selectedWall = wall;
      selectedDrawnId = solid?.id;
      selectedDrawnAnchor = a;
      editStart = c.carrier.dir == AxisDir.V
          ? Offset(c.carrier.pos.toDouble(), c.startPos.toDouble())
          : Offset(c.startPos.toDouble(), c.carrier.pos.toDouble());
      editEnd = c.carrier.dir == AxisDir.V
          ? Offset(c.carrier.pos.toDouble(), c.endPos.toDouble())
          : Offset(c.endPos.toDouble(), c.carrier.pos.toDouble());
      if (!keepTool) {
        tool = 'editWall';
        browse = false;
      }
      placementHint = tr('拖两端改长度 · 拖墙身移动', 'Ұштарын сүйреп ұзындығын, денесін сүйреп орнын өзгертіңіз');
    });
  }

  Map<String, dynamic> wallEditArguments(Offset start, Offset end) => {
        'floorId': floor.id,
        if (selectedDrawnId != null) 'wallId': selectedDrawnId,
        if (selectedDrawnId == null) 'anchor': selectedDrawnAnchor,
        'x0': start.dx.round(),
        'y0': start.dy.round(),
        'x1': end.dx.round(),
        'y1': end.dy.round()
      };

  void beginWallEdit(Offset local, Size size) {
    wallGrip = null;
    editDown = null;
    if (editStart == null || editEnd == null) return;
    final painter = interactionPainter();
    final a = painter.point(editStart!.dx, editStart!.dy, size),
        b = painter.point(editEnd!.dx, editEnd!.dy, size);
    final grips = wallGrips(a, b, zoom: canvasZoom);
    final handles = {
      if (grips.middle != null) 'middle': grips.middle!,
      'start': grips.start,
      'end': grips.end
    }.entries.toList()
      ..sort((x, y) =>
          (local - x.value).distance.compareTo((local - y.value).distance));
    if ((local - handles.first.value).distance * canvasZoom <= 24) {
      wallGrip = handles.first.key;
    } else if (distanceToSegment(local, a, b) * canvasZoom <= 18) {
      // The whole wall body moves the wall; easier than a small middle grip.
      wallGrip = 'middle';
    }
    final world = painter.worldPoint(local, size);
    editDown = Offset(world.x, world.y);
    editPreviewStart = null;
    editPreviewEnd = null;
    editCommand = null;
    editArgs = null;
    spatialError = null;
  }

  void previewWallEdit(Offset local, Size size) {
    if (wallGrip == null ||
        editDown == null ||
        editStart == null ||
        editEnd == null) return;
    if (editPreviewStart == null &&
        downPoint != null &&
        (local - downPoint!).distance * canvasZoom < 8) return;
    final painter = interactionPainter(),
        world = painter.worldPoint(local, size),
        raw = Offset(world.x, world.y),
        pixel = 1 / (painter.scale(size) * canvasZoom);
    final vertical = editStart!.dx == editEnd!.dx;
    final carrier = vertical ? editStart!.dx : editStart!.dy;
    final lo = math.min(vertical ? editStart!.dy : editStart!.dx,
            vertical ? editEnd!.dy : editEnd!.dx),
        hi = math.max(vertical ? editStart!.dy : editStart!.dx,
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
    if (wallGrip == 'start' || wallGrip == 'end') {
      final fixed = wallGrip == 'start' ? editEnd! : editStart!,
          moving = wallGrip == 'start' ? editStart! : editEnd!;
      final snap = snapWallEnd(base, fixed, raw,
          connectRadius: 22 * pixel,
          alignRadius: 14 * pixel,
          forceHorizontal: !vertical,
          ignore: own,
          skipAlong: {(vertical ? moving.dy : moving.dx).round()});
      drawConnected = snap.connected;
      editPreviewStart = wallGrip == 'start' ? snap.end : editStart;
      editPreviewEnd = wallGrip == 'end' ? snap.end : editEnd;
      editCommand = 'UpdateDrawnWall';
      editArgs = wallEditArguments(editPreviewStart!, editPreviewEnd!);
    } else {
      final delta = raw - editDown!;
      final across = vertical ? delta.dx : delta.dy,
          along = vertical ? delta.dy : delta.dx;
      drawConnected = false;
      if (across.abs() >= along.abs()) {
        // Sideways: walls that end on this one stretch along with it.
        var position = carrier + across, best = 14 * pixel;
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
        ok: tr('松手完成，支持撤销', 'Жіберіңіз, болдырмауға болады'), failed: tr('无法移动这段墙', 'Бұл қабырғаны жылжыту мүмкін емес'));
  }

  /// Full previews (validation plus the resulting rooms) can take tens of
  /// milliseconds on large plans. The line, grips and length update on every
  /// move; when a preview is slow it runs at most every ~100 ms, once more
  /// when the finger rests, and always before release decides.
  String? previewedKind;
  Map<String, dynamic>? previewedArgs, pendingArgs;
  String? pendingKind;
  ({String ok, String failed})? pendingText;
  Duration previewCost = Duration.zero;
  final previewClock = Stopwatch();
  Timer? previewTimer;

  bool get previewIsCurrent =>
      pendingKind == null ||
      (pendingKind == previewedKind && mapEquals(pendingArgs, previewedArgs));

  void schedulePreview(String kind, Map<String, dynamic> args,
      {required String ok, required String failed}) {
    pendingKind = kind;
    pendingArgs = args;
    pendingText = (ok: ok, failed: failed);
    if (previewIsCurrent) return;
    final wait = previewCost.inMilliseconds < 24
        ? Duration.zero
        : Duration(milliseconds: math.max(100, previewCost.inMilliseconds * 2));
    final elapsed = previewClock.isRunning ? previewClock.elapsed : wait;
    if (elapsed >= wait) {
      runPreview();
    } else {
      previewTimer ??= Timer(wait - elapsed, () {
        previewTimer = null;
        if (!mounted || pendingKind == null || previewIsCurrent) return;
        setState(runPreview);
      });
    }
  }

  void runPreview() {
    final kind = pendingKind, args = pendingArgs, text = pendingText;
    if (kind == null || args == null || text == null) return;
    final watch = Stopwatch()..start();
    final result = executeCommand(presentState, DesignCommand(kind, args),
        CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
    if (result is Applied) {
      spatialDocument = composeDocument(history.present.meta, result.newState);
      spatialBase = deriveFloorBase(spatialDocument!, floor.id);
      spatialError = null;
      placementHint = text.ok;
    } else {
      spatialDocument = null;
      spatialBase = null;
      spatialError = result is Rejected ? result.message : text.failed;
      placementHint = spatialError;
    }
    previewCost = watch.elapsed;
    previewClock
      ..reset()
      ..start();
    previewedKind = kind;
    previewedArgs = args;
  }

  /// Release must judge the final position, not a throttled older one.
  void settlePreview() {
    previewTimer?.cancel();
    previewTimer = null;
    if (!previewIsCurrent) runPreview();
  }

  void resetPreview() {
    previewTimer?.cancel();
    previewTimer = null;
    pendingKind = null;
    pendingArgs = null;
    pendingText = null;
    previewedKind = null;
    previewedArgs = null;
  }

  void refreshWallSelection(Offset start, Offset end) {
    final vertical = start.dx == end.dx,
        along0 = vertical ? start.dy : start.dx,
        along1 = vertical ? end.dy : end.dx;
    final solid = floor.wallOverrides.whereType<SolidWall>().where((w) {
      final c = resolveAnchor(base.axes, w.anchor).chain!;
      return c.carrier.dir == (vertical ? AxisDir.V : AxisDir.H) &&
          c.carrier.pos == (vertical ? start.dx : start.dy) &&
          c.startPos == math.min(along0, along1) &&
          c.endPos == math.max(along0, along1);
    }).firstOrNull;
    if (solid == null) {
      clearWallSelection();
      if (tool == 'editWall') {
        tool = 'browse';
        browse = true;
      }
      return;
    }
    selectedDrawnId = solid.id;
    selectedDrawnAnchor = solid.anchor;
    editStart = start;
    editEnd = end;
    selectedWall = base.wallSegments
            .where((w) =>
                w.axis.dir == (vertical ? AxisDir.V : AxisDir.H) &&
                w.axis.pos == (vertical ? start.dx : start.dy) &&
                w.start.pos >= math.min(along0, along1) &&
                w.end.pos <= math.max(along0, along1))
            .firstOrNull ??
        selectedWall;
  }

  void finishWallEdit() {
    settlePreview();
    final start = editPreviewStart,
        end = editPreviewEnd,
        error = spatialError,
        kind = editCommand,
        args = editArgs;
    cancelDrag();
    spatialError = null;
    if (start != null &&
        end != null &&
        error == null &&
        kind != null &&
        args != null) {
      final before = history.present;
      action(kind, args);
      if (history.present != before) refreshWallSelection(start, end);
    }
    if (error != null) notify(error);
    placementHint = tr('拖两端改长度 · 拖墙身移动', 'Ұштарын сүйреп ұзындығын, денесін сүйреп орнын өзгертіңіз');
    setState(() {});
  }

  /// Whether the given end of the selected wall touches another wall.
  bool selectedEndJoins(Offset end) {
    if (editStart == null || editEnd == null) return false;
    final vertical = editStart!.dx == editEnd!.dx;
    final carrier = vertical ? editStart!.dx : editStart!.dy;
    return endJoinsWall(base, end,
        horizontal: !vertical,
        ignore: (w) =>
            w.axis.dir == (vertical ? AxisDir.V : AxisDir.H) &&
            w.axis.pos == carrier);
  }

  Future<void> preciseWallLength() async {
    if (editStart == null || editEnd == null) return;
    final start = editStart!, end = editEnd!;
    final value = await length(tr('墙长', 'Қабырға ұзындығы'), (end - start).distance.round());
    if (value == null || !mounted) return;
    // Keep the end that is joined to another wall; move the free one.
    final keepEnd = selectedEndJoins(end) && !selectedEndJoins(start);
    final vertical = start.dx == end.dx;
    final direction = vertical ? const Offset(0, 1) : const Offset(1, 0);
    final from = keepEnd ? end - direction * value.toDouble() : start,
        to = keepEnd ? end : start + direction * value.toDouble();
    final before = history.present;
    action('UpdateDrawnWall', wallEditArguments(from, to));
    if (history.present != before) {
      setState(() => refreshWallSelection(from, to));
      notify(tr('墙长已改为 ${(value / 1000).toStringAsFixed(2)} 米',
          'Қабырға ұзындығы ${m2dp(value)} м болды'));
    }
  }

  Future<void> preciseWallPosition() async {
    if (editStart == null || editEnd == null) return;
    final vertical = editStart!.dx == editEnd!.dx;
    final value = await length(vertical ? tr('墙到左侧外墙的距离', 'Сол сыртқы қабырғаға дейінгі қашықтық') : tr('墙到下侧外墙的距离', 'Төменгі сыртқы қабырғаға дейінгі қашықтық'),
        (vertical ? editStart!.dx : editStart!.dy).round());
    if (value == null || !mounted) return;
    final start = vertical
        ? Offset(value.toDouble(), editStart!.dy)
        : Offset(editStart!.dx, value.toDouble());
    final end = vertical
        ? Offset(value.toDouble(), editEnd!.dy)
        : Offset(editEnd!.dx, value.toDouble());
    final before = history.present;
    action('MoveDrawnWall', {
      'floorId': floor.id,
      if (selectedDrawnId != null) 'wallId': selectedDrawnId,
      if (selectedDrawnId == null) 'anchor': selectedDrawnAnchor,
      'pos': value
    });
    if (history.present != before)
      setState(() => refreshWallSelection(start, end));
  }

  Future<void> wallSettings({bool directThickness = false}) async {
    if (selectedDrawnAnchor == null) return;
    final choice = directThickness
        ? 'thickness'
        : await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  ListTile(
                      title: Text(tr('调整墙厚', 'Қалыңдығын өзгерту')),
                      onTap: () => Navigator.pop(context, 'thickness')),
                  ListTile(
                      title: Text(tr('恢复默认墙厚', 'Әдепкі қалыңдықты қайтару')),
                      onTap: () => Navigator.pop(context, 'default'))
                ])));
    if (choice == null) return;
    int? value;
    if (choice == 'thickness') {
      final current = floor.wallOverrides
          .where((w) => w.anchor == selectedDrawnAnchor)
          .firstOrNull;
      final thickness = current is SolidWall
          ? current.value
          : current is ThicknessWall
              ? current.value
              : selectedWall?.thickness.round() ??
                  history.present.defaults.innerWallThickness;
      value = await showDialog<int>(
          context: context,
          builder: (_) => WallThicknessDialog(initial: thickness));
      if (value == null || !mounted) return;
    }
    final start = editStart, end = editEnd;
    action('SetWallOverride', {
      'floorId': floor.id,
      'anchor': selectedDrawnAnchor,
      'type': choice,
      if (value != null) 'value': value
    });
    if (start != null && end != null)
      setState(() => refreshWallSelection(start, end));
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
                  title: Text(tr('删除墙及其门窗？', 'Қабырға мен ондағы есік-терезені жою керек пе?')),
                  content: Text(tr('这段墙上的 $hosted 个门窗也会删除，可通过撤销恢复。',
                      'Қабырғадағы $hosted есік-терезе де жойылады, болдырмау арқылы қайтаруға болады.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('取消', 'Болдырмау'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(tr('删除', 'Жою')))
                  ]));
      if (yes != true) return;
    }
    final args = wallEditArguments(editStart!, editEnd!)
      ..['deleteHostedObjects'] = true;
    final before = history.present;
    action('DeleteDrawnWall', args);
    if (history.present != before) {
      setState(() {
        cancelDrag();
        if (tool == 'editWall') {
          tool = 'browse';
          browse = true;
        }
        clearWallSelection();
        placementHint = null;
      });
      notify(
          hosted > 0
              ? tr('已删除墙体和 $hosted 个门窗', 'Қабырға мен $hosted есік-терезе жойылды')
              : tr('已删除墙体', 'Қабырға жойылды'),
          undo: undo);
    }
  }

  Offset? drawingBefore;
  bool placingWallStart = false;
  bool drawingStrokeActive = false;
  bool wallFromAdjust = false;
  Timer? wallHoldTimer;
  Offset? wallHoldScreen;
  double get canvasZoom => canvasTransform.value.getMaxScaleOnAxis();

  /// Same inputs, same pluses: build, hit tests and hover all ask for them.
  (
    FloorBase,
    double,
    Size,
    Offset?,
    Offset?,
    Offset?,
    List<Offset>
  )? attachmentMemo;

  List<Offset> visibleWallAttachments(Size size) {
    final seed = tool == 'drawWall' ? drawingOrigin : null;
    final memo = attachmentMemo;
    if (memo != null &&
        identical(memo.$1, base) &&
        memo.$2 == canvasZoom &&
        memo.$3 == size &&
        memo.$4 == seed &&
        memo.$5 == editStart &&
        memo.$6 == editEnd) return memo.$7;
    final result = computeWallAttachments(size);
    attachmentMemo = (base, canvasZoom, size, seed, editStart, editEnd, result);
    return result;
  }

  List<Offset> computeWallAttachments(Size size) {
    final painter = interactionPainter();
    final result = <Offset>[];
    // The active start point and the selected wall's grips own their spots.
    final reserved = [
      if (tool == 'drawWall' && drawingOrigin != null)
        painter.point(drawingOrigin!.dx, drawingOrigin!.dy, size)
    ];
    bool onSelected(Offset p) {
      if (editStart == null || editEnd == null) return false;
      final vertical = editStart!.dx == editEnd!.dx;
      final along = vertical ? p.dy : p.dx;
      return (vertical ? p.dx == editStart!.dx : p.dy == editStart!.dy) &&
          along >=
              math.min(vertical ? editStart!.dy : editStart!.dx,
                  vertical ? editEnd!.dy : editEnd!.dx) &&
          along <=
              math.max(vertical ? editStart!.dy : editStart!.dx,
                  vertical ? editEnd!.dy : editEnd!.dx);
    }

    for (final p
        in wallAttachmentPoints(base, derived.floors[floorIndex].openings)) {
      if (onSelected(p)) continue;
      final local = painter.point(p.dx, p.dy, size);
      if (reserved.any((q) => (local - q).distance * canvasZoom < 34)) continue;
      if (result.every((q) =>
          (local - painter.point(q.dx, q.dy, size)).distance * canvasZoom >=
          52)) result.add(p);
    }
    return result;
  }

  /// The start point or plus under [local] within a finger-sized radius.
  Offset? attachmentAt(Offset local, Size size) {
    final painter = interactionPainter();
    final candidates = [
      if (tool == 'drawWall' && drawingOrigin != null) drawingOrigin!,
      ...visibleWallAttachments(size)
    ];
    candidates.sort((a, b) => (painter.point(a.dx, a.dy, size) - local)
        .distance
        .compareTo((painter.point(b.dx, b.dy, size) - local).distance));
    if (candidates.isEmpty) return null;
    final first = candidates.first;
    return (painter.point(first.dx, first.dy, size) - local).distance *
                canvasZoom <=
            24
        ? first
        : null;
  }

  WallSegment? wallAtPoint(Offset local, Size size, {double radius = 18}) {
    final painter = interactionPainter(),
        world = painter.worldPoint(local, size);
    return nearestWall(base, Offset(world.x, world.y),
        radius / (painter.scale(size) * canvasZoom));
  }

  Offset attachmentOnWall(WallSegment wall, Offset local, Size size) {
    final world = interactionPainter().worldPoint(local, size);
    final horizontal = wall.axis.dir == AxisDir.H;
    final along = ((horizontal ? world.x : world.y) / 100).round() * 100.0;
    return horizontal
        ? Offset(along.clamp(wall.start.pos, wall.end.pos).toDouble(),
            wall.axis.pos.toDouble())
        : Offset(wall.axis.pos.toDouble(),
            along.clamp(wall.start.pos, wall.end.pos).toDouble());
  }

  void scheduleWallHold(Offset local, Offset screen, Size size) {
    wallHoldTimer?.cancel();
    wallHoldScreen = screen;
    if (!(browse ||
        tool == 'drawWall' ||
        tool == 'editWall' ||
        tool == 'selectWall')) return;
    // Pressing a plus before dragging is common; it must not open a menu.
    if ((tool == 'drawWall' || tool == 'selectWall') &&
        attachmentAt(local, size) != null) return;
    final wall = wallAtPoint(local, size);
    if (wall == null) return;
    wallHoldTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted ||
          pointers.length != 1 ||
          cancelledStroke ||
          furnitureGrip != null) return;
      final point = attachmentOnWall(wall, local, size);
      setState(() {
        cancelDrag();
        wallGesture = 'held';
        showWallContext(wall, point);
      });
    });
  }

  /// Select [wall] and open its nearby action menu. Inner walls also get
  /// grips; outer walls belong to the footprint and only offer actions.
  void showWallContext(WallSegment wall, Offset point) {
    final inner = wall.axis.kind != 'boundary';
    if (inner) {
      selectWallForEdit(wall, point.dx, point.dy, keepTool: tool == 'drawWall');
    } else {
      clearWallSelection();
    }
    menuWall = wall;
    menuPoint = point;
    // Selecting ends "continue from the last wall"; the menu can restart it.
    drawingOrigin = null;
    HapticFeedback.selectionClick();
  }

  Future<void> wallMenuAction(String choice) async {
    final wall = menuWall, point = menuPoint;
    if (wall == null || point == null) return;
    setState(closeWallMenu);
    if (choice == 'add') {
      setState(() {
        clearWallSelection();
        startWallDrawing();
        drawingOrigin = point;
        placementHint = tr('按住大 ＋ 拖出新墙', 'Үлкен ＋ белгісін ұстап, жаңа қабырға тартыңыз');
      });
      return;
    }
    if (choice == 'footprint') return footprintOptions();
    if (choice == 'outerThickness') {
      final value = await showDialog<int>(
          context: context,
          builder: (_) => WallThicknessDialog(initial: wall.thickness.round()));
      if (value != null && mounted)
        action('SetWallOverride', {
          'floorId': floor.id,
          'anchor': wall.ref.anchor,
          'type': 'thickness',
          'value': value
        });
      return;
    }
    if (choice == 'length') await preciseWallLength();
    if (choice == 'move') await preciseWallPosition();
    if (choice == 'thickness') await wallSettings(directThickness: true);
    if (choice == 'delete') await deleteSelectedWall();
  }

  /// A tap in the wall tool: select a wall and show its menu, open a door
  /// or window, or clear the selection. The start point never moves here.
  void wallToolTap(Offset local, Size size) {
    final painter = interactionPainter(),
        world = painter.worldPoint(local, size),
        tolerance = 14 / (painter.scale(size) * canvasZoom);
    final opening = derived.floors[floorIndex].openings.where((p) {
      final along = p.axis.dir == AxisDir.H ? world.x : world.y,
          cross = p.axis.dir == AxisDir.H ? world.y : world.x;
      return along >= p.start - tolerance &&
          along <= p.end + tolerance &&
          (cross - p.axis.pos).abs() <= tolerance;
    }).firstOrNull;
    if (opening != null) {
      setState(clearWallSelection);
      selectOpening(opening.opening);
      return;
    }
    final wall = wallAtPoint(local, size, radius: 16);
    setState(() {
      if (wall == null) {
        clearWallSelection();
        placementHint = null;
      } else {
        showWallContext(wall, attachmentOnWall(wall, local, size));
      }
    });
  }

  /// Move the canvas with one finger when a gesture started on nothing
  /// editable. Keeps part of the house on screen so it cannot get lost.
  void panCanvas(Offset delta) {
    final next = Matrix4.translationValues(delta.dx, delta.dy, 0)
      ..multiply(canvasTransform.value);
    final painter = interactionPainter();
    final house = Rect.fromPoints(
        MatrixUtils.transformPoint(next, painter.point(0, 0, canvasSize)),
        MatrixUtils.transformPoint(
            next,
            painter.point(base.axes.v.last.pos.toDouble(),
                base.axes.h.last.pos.toDouble(), canvasSize)));
    if (!house.overlaps((Offset.zero & canvasSize).deflate(60))) return;
    canvasTransform.value = next;
  }

  Offset wallPoint(Offset local, Size size) {
    final painter = interactionPainter(),
        world = painter.worldPoint(local, size);
    final tolerance = 14 / (painter.scale(size) * canvasZoom);
    double snap(double value, List<ResolvedAxis> axes) {
      ResolvedAxis? best;
      var distance = tolerance;
      for (final axis in axes)
        if ((axis.pos - value).abs() < distance) {
          best = axis;
          distance = (axis.pos - value).abs();
        }
      return best?.pos.toDouble() ?? (value / 100).round() * 100.0;
    }

    return Offset(snap(world.x, base.axes.v), snap(world.y, base.axes.h));
  }

  /// Decide what a single finger does in the wall tool: grips and body of
  /// the selected wall edit it, a plus draws, anything else is a tap or pan.
  void beginWallTool(Offset local, Size size) {
    if (editStart != null && editEnd != null) {
      beginWallEdit(local, size);
      // The selected wall wins, even where a door sits on it.
      if (wallGrip != null) {
        wallGesture = 'edit';
        closeWallMenu();
        return;
      }
      wallGrip = null;
    }
    if (beginOpeningDrag(local, size)) {
      wallGesture = 'opening';
      clearWallSelection();
      return;
    }
    if (attachmentAt(local, size) != null || placingWallStart) {
      clearWallSelection();
      wallGesture = 'draw';
      beginWallStroke(local, size);
      return;
    }
    wallGesture = 'tap';
  }

  /// A tap on the already selected wall shows its menu again.
  void reopenWallMenu(Offset local, Size size) {
    if (editStart == null || editEnd == null || selectedWall == null) return;
    final world = interactionPainter().worldPoint(local, size);
    final vertical = editStart!.dx == editEnd!.dx;
    final lo = math.min(vertical ? editStart!.dy : editStart!.dx,
            vertical ? editEnd!.dy : editEnd!.dx),
        hi = math.max(vertical ? editStart!.dy : editStart!.dx,
            vertical ? editEnd!.dy : editEnd!.dx);
    final along = ((vertical ? world.y : world.x) / 100).round() * 100.0;
    final at = along.clamp(lo, hi).toDouble();
    menuWall = selectedWall;
    menuPoint =
        vertical ? Offset(editStart!.dx, at) : Offset(at, editStart!.dy);
  }

  /// Whether the active stroke started on a plus (rather than a free start).
  bool strokeFromAttachment = false;

  void beginWallStroke(Offset local, Size size) {
    drawingStrokeActive = true;
    drawingBefore = drawingOrigin;
    final hit = attachmentAt(local, size);
    strokeFromAttachment = hit != null;
    if (hit != null) {
      drawingOrigin = hit;
    } else if (placingWallStart) {
      drawingOrigin = wallPoint(local, size);
      placingWallStart = false;
    }
    drawingEnd = null;
    drawConnected = false;
    spatialError = null;
    spatialDocument = null;
    spatialBase = null;
  }

  Map<String, dynamic> get drawingArguments => {
        'floorId': floor.id,
        'x0': drawingOrigin!.dx.round(),
        'y0': drawingOrigin!.dy.round(),
        'x1': drawingEnd!.dx.round(),
        'y1': drawingEnd!.dy.round()
      };

  void previewWallStroke(Offset local, Size size) {
    if (drawingOrigin == null) return;
    if (drawingEnd == null &&
        downPoint != null &&
        (local - downPoint!).distance * canvasZoom < 8) return;
    final painter = interactionPainter(),
        world = painter.worldPoint(local, size),
        pixel = 1 / (painter.scale(size) * canvasZoom);
    final snap = snapWallEnd(base, drawingOrigin!, Offset(world.x, world.y),
        connectRadius: 22 * pixel, alignRadius: 14 * pixel);
    drawingEnd = snap.end;
    drawConnected = snap.connected;
    if ((drawingEnd! - drawingOrigin!).distance < 300) {
      resetPreview();
      spatialDocument = null;
      spatialBase = null;
      spatialError = null;
      return;
    }
    schedulePreview('AddDrawnWall', drawingArguments,
        ok: tr('松手建墙，末端可以继续拖', 'Жіберсеңіз қабырға салынады, ұшынан жалғастыруға болады'), failed: tr('此处无法建墙', 'Мұнда қабырға салу мүмкін емес'));
  }

  void finishWallStroke() {
    settlePreview();
    final end = drawingEnd, error = spatialError;
    if (drawingOrigin == null) drawingOrigin = drawingBefore;
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
      if (history.present != before)
        drawingOrigin =
            canExtendWallFrom(base, derived.floors[floorIndex].openings, end!)
                ? end
                : null;
    }
    if (error != null) notify(error);
    placementHint = tapped
        ? tr('按住大 ＋ 拖出新墙 · 也可点尺子输入长度', 'Үлкен ＋ белгісін ұстап тартыңыз · не сызғышты басып ұзындық енгізіңіз')
        : !accepted && error == null
            ? tr('墙至少 0.30 米，请拖远一些', 'Қабырға кемінде 0,30 м, әріректе жіберіңіз')
            : null;
    setState(() {});
  }

  Future<void> addWallByLength() async {
    if (drawingOrigin == null) return;
    final value = await showDialog<WallLengthChoice>(
        context: context, builder: (_) => const WallLengthDialog());
    if (value == null || !mounted || drawingOrigin == null) return;
    final origin = drawingOrigin!;
    final delta = switch (value.direction) {
      'up' => Offset(0, value.length.toDouble()),
      'down' => Offset(0, -value.length.toDouble()),
      'left' => Offset(-value.length.toDouble(), 0),
      _ => Offset(value.length.toDouble(), 0)
    };
    final end = origin + delta;
    final before = history.present;
    action('AddDrawnWall', {
      'floorId': floor.id,
      'x0': origin.dx.round(),
      'y0': origin.dy.round(),
      'x1': end.dx.round(),
      'y1': end.dy.round()
    });
    if (history.present != before) setState(() => drawingOrigin = end);
  }

  void startWallDrawing() {
    cancelDrag();
    browse = false;
    view3d = false;
    tool = 'drawWall';
    drawingOrigin = null;
    placingWallStart = false;
    drawingEnd = null;
    clearWallSelection();
    placementHint = null;
  }

  String meters(num value) => m2dp(value);

  String get dragOntoWallHint =>
      tr('拖到墙上，门窗会自动贴合', 'Қабырғаға апарыңыз, есік-терезе өзі орнығады');

  bool get floorHasInnerWalls =>
      base.wallSegments.any((w) => w.axis.kind != 'boundary');

  bool get showWallCoach =>
      tool == 'drawWall' &&
      !coachDismissed &&
      !drawingStrokeActive &&
      drawingOrigin == null &&
      menuWall == null &&
      !floorHasInnerWalls;

  bool get showStartCoach =>
      tool == 'browse' &&
      !view3d &&
      !coachDismissed &&
      !floorHasInnerWalls &&
      floor.openings.isEmpty;

  String? get coachText => showWallCoach
      ? tr('按住橙色 ＋ 往里拖，松手就建好一面墙', 'Сары ＋ белгісін ішке қарай тартыңыз, жіберсеңіз қабырға салынады')
      : showStartCoach
          ? tr('先点「墙体」，再按住 ＋ 往里拖', 'Алдымен «Қабырға» батырмасын, сосын ＋ белгісін ішке тартыңыз')
          : null;

  /// Dashed arrow from one outer plus into the house for the first wall.
  (Offset, Offset)? coachArrow(Size size) {
    if (!showWallCoach) return null;
    final points = visibleWallAttachments(size);
    if (points.isEmpty) return null;
    final width = base.axes.v.last.pos.toDouble(),
        depth = base.axes.h.last.pos.toDouble();
    final p = points.reduce((a, b) => b.dy > a.dy ? b : a);
    final inward = p.dy == depth
        ? const Offset(0, -1)
        : p.dy == 0
            ? const Offset(0, 1)
            : p.dx == 0
                ? const Offset(1, 0)
                : const Offset(-1, 0);
    final reach =
        math.min(3000.0, (inward.dx == 0 ? depth : width) * 0.35).toDouble();
    return (p, p + inward * reach);
  }

  /// In-canvas label for the wall being drawn, resized or moved.
  String? get wallDraftLabel {
    if (tool == 'drawWall' && drawingEnd != null && drawingOrigin != null)
      return '${meters((drawingEnd! - drawingOrigin!).distance)} $unitM';
    if (wallGrip == null || editPreviewStart == null || editPreviewEnd == null)
      return null;
    if (editCommand == 'MoveDrawnWall' ||
        (wallGrip == 'middle' && editStart != null)) {
      return tr('移动 ${meters((editPreviewStart! - editStart!).distance)} 米',
          'Жылжыту ${meters((editPreviewStart! - editStart!).distance)} м');
    }
    return '${meters((editPreviewEnd! - editPreviewStart!).distance)} $unitM';
  }

  /// Live state while drawing or editing a wall: what will happen on release.
  ({String text, IconData icon, Color color})? get liveStatus {
    const good = Color(0xff286b50),
        warn = Color(0xff8a5a00),
        bad = Color(0xffa14539),
        info = Color(0xff4a5548);
    if (tool == 'drawWall' &&
        drawingStrokeActive &&
        drawingOrigin != null &&
        drawingEnd != null) {
      final length = (drawingEnd! - drawingOrigin!).distance;
      if (length < 300)
        return (text: tr('继续拖动 · 墙至少 0.30 米', 'Тарта беріңіз · қабырға кемінде 0,30 м'), icon: Icons.straighten, color: info);
      if (spatialError != null)
        return (text: spatialError!, icon: Icons.block, color: bad);
      final direction = drawingEnd!.dy == drawingOrigin!.dy ? tr('横墙', 'Көлденең қабырға') : tr('竖墙', 'Тік қабырға');
      return drawConnected
          ? (
              text: tr('$direction ${meters(length)} 米 · 已连到墙', '$direction ${meters(length)} м · қабырғаға жалғанды'),
              icon: Icons.link,
              color: good
            )
          : (
              text: tr('$direction ${meters(length)} 米 · 末端没连墙', '$direction ${meters(length)} м · ұшы жалғанбаған'),
              icon: Icons.link_off,
              color: warn
            );
    }
    if (draggingAxis?.kind == 'boundary' && dragAttempted) {
      final width = dragArguments?['width'] as int?,
          depth = dragArguments?['depth'] as int?;
      return dragValid && (width != null || depth != null)
          ? (
              text: width != null
                  ? tr('房屋宽 ${meters(width)} 米 · 所有楼层一起改', 'Үй ені ${meters(width)} м · барлық қабат бірге өзгереді')
                  : tr('房屋长 ${meters(depth!)} 米 · 所有楼层一起改', 'Үй ұзындығы ${meters(depth)} м · барлық қабат бірге өзгереді'),
              icon: Icons.open_in_full,
              color: good
            )
          : (
              text: placementHint ?? tr('这个尺寸放不下已有的墙或房间', 'Бұл өлшемге бар қабырға не бөлме сыймайды'),
              icon: Icons.block,
              color: bad
            );
    }
    if (draggingOpening != null && dragAttempted) {
      final name = openingName(draggingOpening!.opening);
      return dragValid
          ? (
              text: tr('松手把$name放在这里', '$name осында қою үшін жіберіңіз'),
              icon: Icons.check_circle_outline,
              color: good
            )
          : (
              text: placementHint ?? tr('这里放不下$name', '$name мұнда сыймайды'),
              icon: Icons.block,
              color: bad
            );
    }
    if (draggingNewOpening != null) {
      return openingDrop != null
          ? (
              text: tr('已贴合墙面，松手放下${openingNames[draggingNewOpening]}',
                  'Қабырғаға орнықты, ${openingNames[draggingNewOpening]} қою үшін жіберіңіз'),
              icon: Icons.check_circle_outline,
              color: good
            )
          : (
              text: placementHint ?? tr('拖到墙上，门窗会自动贴合', 'Қабырғаға апарыңыз, есік-терезе өзі орнығады'),
              icon: Icons.touch_app_outlined,
              color: warn
            );
    }
    if (wallGrip != null && editPreviewStart != null) {
      if (spatialError != null)
        return (text: spatialError!, icon: Icons.block, color: bad);
      if (editCommand == 'MoveDrawnWall')
        return (
          text: tr('${wallDraftLabel!} · 相连的墙会跟着伸缩', '${wallDraftLabel!} · жалғас қабырғалар бірге созылады'),
          icon: Icons.open_with,
          color: good
        );
      if (wallGrip == 'middle')
        return (text: wallDraftLabel!, icon: Icons.open_with, color: good);
      return drawConnected
          ? (
              text: tr('墙长 ${wallDraftLabel!} · 已连到墙', 'Қабырға ${wallDraftLabel!} · қабырғаға жалғанды'),
              icon: Icons.link,
              color: good
            )
          : (
              text: tr('墙长 ${wallDraftLabel!} · 这一端没连墙', 'Қабырға ${wallDraftLabel!} · бұл ұшы жалғанбаған'),
              icon: Icons.link_off,
              color: warn
            );
    }
    return null;
  }

  Widget statusChip() {
    final status = liveStatus;
    Widget card(Widget child) => Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: floatingSurface(Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: child))));
    if (status != null)
      return IgnorePointer(
          child: Semantics(
              liveRegion: true,
              child: card(Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(status.icon, size: 20, color: status.color),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(coreMessage(status.text),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: status.color)))
              ]))));
    return const SizedBox.shrink();
  }

  /// Actions for the pressed wall, placed beside it rather than in a sheet
  /// so the wall and its grips stay visible.
  Widget? wallMenuCard() {
    final wall = menuWall, point = menuPoint;
    if (wall == null || point == null || view3d || canvasSize.isEmpty)
      return null;
    final inner = wall.axis.kind != 'boundary';
    final painter = interactionPainter();
    Offset screen(Offset world) => MatrixUtils.transformPoint(
        canvasTransform.value, painter.point(world.dx, world.dy, canvasSize));
    final a = inner && editStart != null
            ? editStart!
            : wall.axis.dir == AxisDir.H
                ? Offset(wall.start.pos.toDouble(), wall.axis.pos.toDouble())
                : Offset(wall.axis.pos.toDouble(), wall.start.pos.toDouble()),
        b = inner && editEnd != null
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
    final width = math.min(312.0, canvasSize.width - 24),
        height = 104.0 + (opening ? 18 : 0),
        top = overlayTop,
        bottom = canvasSize.height - canvasInsets.bottom + 24;
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
                        tr('${inner ? '内墙' : '外墙'} ${meters(length)} 米 · 厚 ${meters(wall.thickness)} 米',
                            '${inner ? 'Ішкі' : 'Сыртқы'} қабырға ${meters(length)} м · қалыңдығы ${meters(wall.thickness)} м'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600))),
                IconButton(
                    tooltip: tr('关闭', 'Жабу'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(closeWallMenu),
                    icon: const Icon(Icons.close, size: 18))
              ]),
              Row(children: [
                button('add', Icons.add_circle_outline, tr('接墙', 'Жалғау'),
                    '从这里接墙'.trKey('Осы жерден жалғау'),
                    enabled: !opening),
                if (inner) ...[
                  button('length', Icons.straighten, tr('长度', 'Ұзындық'),
                      '调整长度'.trKey('Ұзындығын өзгерту')),
                  button('move', Icons.open_with, tr('位置', 'Орны'),
                      '移动墙体'.trKey('Қабырғаны жылжыту')),
                  button('thickness', Icons.line_weight, tr('墙厚', 'Қалыңдық'),
                      '修改墙厚'.trKey('Қалыңдығын өзгерту')),
                  button('delete', Icons.delete_outline, tr('删除', 'Жою'),
                      '删除墙体'.trKey('Қабырғаны жою'),
                      danger: true),
                ] else ...[
                  button('footprint', Icons.aspect_ratio, tr('房屋尺寸', 'Үй өлшемі'),
                      '调整房屋长宽'.trKey('Үй өлшемін өзгерту')),
                  button('outerThickness', Icons.line_weight, tr('墙厚', 'Қалыңдық'),
                      '外墙厚度'.trKey('Сыртқы қабырға қалыңдығы')),
                ]
              ]),
              if (opening)
                Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child:
                        Text(tr('这里有门窗，换个位置才能接墙', 'Мұнда есік-терезе бар, жалғау үшін басқа жерді таңдаңыз'), style: TextStyle(fontSize: 12))),
            ]))));
  }

  /// Where floating status and menus may start inside the plan sheet.
  double get overlayTop => 52;

  String get interactionHint =>
      (placementHint == null ? null : coreMessage(placementHint!)) ??
      (tool == 'drawWall'
          ? tr('按住 ＋ 拖出新墙 · 点墙修改 · 拖空白处移动画布', '＋ белгісін ұстап қабырға тартыңыз · қабырғаны басып өзгертіңіз · бос жерді сүйреп жылжытыңыз')
          : tool == 'selectWall'
              ? tr('点墙修改 · 拖 ＋ 接墙 · 拖空白处移动画布', 'Қабырғаны басып өзгертіңіз · ＋ белгісінен жалғаңыз · бос жерді сүйреп жылжытыңыз')
              : tool == 'editWall'
                  ? tr('拖两端改长度 · 拖墙身移动', 'Ұштарын сүйреп ұзындығын, денесін сүйреп орнын өзгертіңіз')
                  : spatialTool
                      ? (tool == 'split' ? tr('拉一条横线或竖线，松手分房', 'Көлденең не тік сызық тартып, жіберсеңіз бөлінеді') : tr('从一角拖到另一角，松手创建房间', 'Бір бұрыштан екіншісіне тартып жіберсеңіз, бөлме жасалады'))
                      : tool == 'resize'
                          ? tr('拖右边或上边的圆形手柄改长宽 · 所有楼层一起改', 'Оң не жоғарғы дөңгелек тұтқаны сүйреп өлшемін өзгертіңіз · барлық қабат бірге өзгереді')
                          : tr('拖动画布 · 点选对象调整 · 双指缩放', 'Сызбаны сүйреп жылжытыңыз · нысанды басып өзгертіңіз · екі саусақпен үлкейтіңіз'));

  MouseCursor canvasCursor = MouseCursor.defer;

  /// What the mouse pointer would do here, shown before pressing.
  MouseCursor hoverCursor(Offset local, Size size) {
    if (view3d) return MouseCursor.defer;
    final wallTools = tool == 'drawWall' || tool == 'editWall';
    if (wallTools && editStart != null && editEnd != null) {
      final painter = interactionPainter();
      final a = painter.point(editStart!.dx, editStart!.dy, size),
          b = painter.point(editEnd!.dx, editEnd!.dy, size);
      final grips = wallGrips(a, b, zoom: canvasZoom);
      final vertical = editStart!.dx == editEnd!.dx;
      for (final end in [grips.start, grips.end])
        if ((local - end).distance * canvasZoom <= 24)
          return vertical
              ? SystemMouseCursors.resizeUpDown
              : SystemMouseCursors.resizeLeftRight;
      if (distanceToSegment(local, a, b) * canvasZoom <= 18)
        return SystemMouseCursors.move;
    }
    if (tool == 'resize') {
      final painter = interactionPainter();
      final width = base.axes.v.last.pos.toDouble(),
          depth = base.axes.h.last.pos.toDouble();
      if ((local - painter.point(width, depth / 2, size)).distance *
              canvasZoom <=
          28) return SystemMouseCursors.resizeLeftRight;
      if ((local - painter.point(width / 2, depth, size)).distance *
              canvasZoom <=
          28) return SystemMouseCursors.resizeUpDown;
    }
    if ((tool == 'drawWall' || tool == 'selectWall') &&
        attachmentAt(local, size) != null) return SystemMouseCursors.click;
    if (openingAt(local, size) != null) return SystemMouseCursors.grab;
    if ((browse || wallTools || tool == 'selectWall') &&
        wallAtPoint(local, size, radius: 16) != null)
      return SystemMouseCursors.click;
    return browse || wallTools || tool == 'selectWall'
        ? SystemMouseCursors.grab
        : MouseCursor.defer;
  }

  /// Saved state at a glance: icon plus a word, red when saving failed.
  Widget saveIndicator() {
    final failed = status == '保存失败',
        color = failed ? Theme.of(context).colorScheme.error : null;
    return Semantics(
        liveRegion: true,
        label: status,
        child: ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              failed
                  ? Icons.error_outline
                  : saving
                      ? Icons.sync
                      : dirty
                          ? Icons.edit_note
                          : Icons.check_circle_outline,
              size: 14,
              color: color),
          const SizedBox(width: 2),
          Flexible(
              child: Text(
                  saving
                      ? tr('保存中', 'Сақталуда')
                      : switch (status) {
                          '已保存' => tr('已保存', 'Сақталды'),
                          '未保存' => tr('未保存', 'Сақталмаған'),
                          '保存失败' => tr('保存失败', 'Сақталмады'),
                          _ => status
                        },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: color))),
        ])));
  }

  /// Esc steps back one level: an unfinished drag, the menu, the
  /// selection, then the active tool.
  void escape() {
    setState(() {
      if (drawingStrokeActive || wallGrip != null || dragAttempted) {
        cancelDrag();
      } else if (menuWall != null || editStart != null) {
        clearWallSelection();
        if (tool == 'editWall') {
          tool = 'browse';
          browse = true;
        }
      } else if (tool != 'browse') {
        tool = 'browse';
        browse = true;
        drawingOrigin = null;
        placingWallStart = false;
      }
      placementHint = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = Tokens.of(context);
    return PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop) {
            await save();
            if (mounted && !dirty) Navigator.pop(context);
          }
        },
        child: CallbackShortcuts(
            bindings: {
              for (final meta in [false, true]) ...{
                SingleActivator(LogicalKeyboardKey.keyZ,
                    control: !meta, meta: meta): undo,
                SingleActivator(LogicalKeyboardKey.keyZ,
                    control: !meta, meta: meta, shift: true): redo,
              },
              const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                  redo,
              const SingleActivator(LogicalKeyboardKey.escape): escape,
              const SingleActivator(LogicalKeyboardKey.delete): deleteSelection,
              const SingleActivator(LogicalKeyboardKey.backspace):
                  deleteSelection,
            },
            child: Focus(
                autofocus: true,
                child: Scaffold(
                    backgroundColor: t.bg,
                    body: SafeArea(
                        child: LayoutBuilder(builder: (context, constraints) {
                      // Short screens (landscape phones) merge the header
                      // into the tab bar and put tools beside the plan.
                      compact = constraints.maxHeight < 640 &&
                          constraints.maxWidth > constraints.maxHeight;
                      final wide = !compact && constraints.maxWidth >= 1000;
                      return Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1440),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (compact)
                                      compactBar()
                                    else ...[
                                      editorHeader(wide),
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: TabStrip(
                                              tabs: editorTabs,
                                              current: tab,
                                              onSelect: showTab)),
                                    ],
                                    Expanded(child: tabBody(wide)),
                                  ])));
                    }))))));
  }

  /// The plan drawing with all editing gestures; sized by its sheet.
  Widget planCanvas() => LayoutBuilder(builder: (context, constraints) {
                              final size = Size(
                                  constraints.maxWidth, constraints.maxHeight);
                              canvasSize = size;
                              final displayBase = spatialBase ?? base;
                              final displayRooms = spatialDocument?.floors
                                      .firstWhere((f) => f.id == floor.id)
                                      .rooms ??
                                  floor.rooms;
                              final displayOpenings = spatialDocument == null
                                  ? derived.floors[floorIndex].openings
                                  : deriveOpenings(
                                      spatialDocument!, displayBase, floor.id);
                              return InteractiveViewer(
                                  transformationController: canvasTransform,
                                  boundaryMargin: const EdgeInsets.all(200),
                                  panEnabled: ((browse ||
                                              tool == 'measure' ||
                                              tool == 'placeFurniture') &&
                                          draggingOpening == null &&
                                          furnitureGrip == null) ||
                                      pointers.length > 1,
                                  minScale: 0.4,
                                  maxScale: 5,
                                  child: MouseRegion(
                                      cursor: canvasCursor,
                                      onHover: (e) {
                                        final cursor =
                                            hoverCursor(e.localPosition, size);
                                        if (cursor != canvasCursor)
                                          setState(() => canvasCursor = cursor);
                                      },
                                      child: Listener(
                                          onPointerDown: (e) {
                                            if (pointers.isEmpty) {
                                              cancelledStroke = false;
                                              wallFromAdjust = false;
                                            }
                                            pointers.add(e.pointer);
                                            canvasSize = size;
                                            if (pointers.length == 1)
                                              scheduleWallHold(e.localPosition,
                                                  e.position, size);
                                            downPoint = e.localPosition;
                                            gestureScreen = e.position;
                                            wallGesture = null;
                                            if (pointers.length == 1) {
                                              if (browse &&
                                                  beginFurnitureGesture(
                                                      e.localPosition, size)) {
                                                setState(() {});
                                              } else if (tool == 'selectWall') {
                                                if (attachmentAt(
                                                        e.localPosition,
                                                        size) !=
                                                    null)
                                                  setState(() {
                                                    tool = 'drawWall';
                                                    browse = false;
                                                    wallFromAdjust = true;
                                                    wallGesture = 'draw';
                                                    clearWallSelection();
                                                    beginWallStroke(
                                                        e.localPosition, size);
                                                  });
                                                else
                                                  // 改墙 selects walls even where
                                                  // a door sits on them.
                                                  wallGesture = 'tap';
                                              } else if (tool == 'drawWall') {
                                                setState(() => beginWallTool(
                                                    e.localPosition, size));
                                              } else if (tool == 'editWall') {
                                                setState(() {
                                                  beginWallEdit(
                                                      e.localPosition, size);
                                                  if (wallGrip == null &&
                                                      beginOpeningDrag(
                                                          e.localPosition,
                                                          size)) {
                                                    wallGrip = null;
                                                    wallGesture = 'opening';
                                                  } else {
                                                    wallGesture =
                                                        wallGrip != null
                                                            ? 'edit'
                                                            : 'tap';
                                                  }
                                                  if (wallGrip != null)
                                                    closeWallMenu();
                                                });
                                              } else if (spatialTool) {
                                                spatialStart = null;
                                                setState(() => updateSpatial(
                                                    e.localPosition, size));
                                              } else {
                                                setState(() => beginDrag(
                                                    e.localPosition, size));
                                              }
                                            }
                                            if (pointers.length > 1) {
                                              cancelledStroke = true;
                                              setState(() {
                                                stroke.clear();
                                                spatialStart = null;
                                                spatialPreview = null;
                                                cancelDrag();
                                              });
                                              lastPoint = null;
                                              return;
                                            }
                                            if (!browse &&
                                                !spatialTool &&
                                                tool != 'editWall' &&
                                                tool != 'selectWall' &&
                                                tool != 'drawWall' &&
                                                tool != 'placeOpening' &&
                                                tool != 'resize' &&
                                                tool != 'wall' &&
                                                tool != 'opening' &&
                                                tool != 'grid' &&
                                                tool != 'measure' &&
                                                tool != 'placeFurniture')
                                              setState(() => record(
                                                  e.localPosition, size));
                                          },
                                          onPointerMove: (e) {
                                            if (wallHoldScreen != null &&
                                                (e.position - wallHoldScreen!)
                                                        .distance >
                                                    8) wallHoldTimer?.cancel();
                                            final single = !cancelledStroke &&
                                                pointers.length == 1;
                                            if (single && furnitureGrip != null) {
                                              setState(() => previewFurniture(
                                                  e.localPosition, size));
                                              return;
                                            }
                                            if (single &&
                                                (wallGesture == 'tap' ||
                                                    wallGesture == 'pan')) {
                                              if (wallGesture == 'tap' &&
                                                  gestureScreen != null &&
                                                  (e.position - gestureScreen!)
                                                          .distance >
                                                      8) {
                                                wallGesture = 'pan';
                                                wallHoldTimer?.cancel();
                                                panCanvas(e.position -
                                                    gestureScreen!);
                                              } else if (wallGesture == 'pan') {
                                                panCanvas(e.delta);
                                              }
                                            } else if (single &&
                                                wallGesture == 'edit') {
                                              setState(() => previewWallEdit(
                                                  e.localPosition, size));
                                            } else if (single &&
                                                wallGesture == 'draw') {
                                              setState(() => previewWallStroke(
                                                  e.localPosition, size));
                                            }
                                            if (spatialTool &&
                                                !cancelledStroke &&
                                                pointers.length == 1) {
                                              setState(() => updateSpatial(
                                                  e.localPosition, size));
                                            }
                                            if (!cancelledStroke &&
                                                pointers.length == 1 &&
                                                (draggingAxis != null ||
                                                    draggingOpening != null))
                                              setState(() => previewDrag(
                                                  e.localPosition, size));
                                            if (!browse &&
                                                !spatialTool &&
                                                tool != 'editWall' &&
                                                tool != 'selectWall' &&
                                                tool != 'drawWall' &&
                                                tool != 'placeOpening' &&
                                                tool != 'resize' &&
                                                tool != 'wall' &&
                                                tool != 'opening' &&
                                                tool != 'grid' &&
                                                tool != 'measure' &&
                                                tool != 'placeFurniture' &&
                                                !cancelledStroke &&
                                                pointers.length == 1)
                                              setState(() => record(
                                                  e.localPosition, size));
                                          },
                                          onPointerCancel: (e) {
                                            pointers.remove(e.pointer);
                                            setState(() {
                                              stroke.clear();
                                              spatialStart = null;
                                              spatialEnd = null;
                                              spatialPreview = null;
                                              cancelDrag();
                                            });
                                            lastPoint = null;
                                          },
                                          onPointerUp: (e) {
                                            wallHoldTimer?.cancel();
                                            final gesture = wallGesture;
                                            wallGesture = null;
                                            final single = !cancelledStroke &&
                                                pointers.length == 1;
                                            if (single && gesture == 'pan') {
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (single && furnitureGrip != null) {
                                              final tap = furnitureDraft == null &&
                                                  furnitureGrip != 'rotate';
                                              finishFurniture();
                                              pointers.remove(e.pointer);
                                              final at = downPoint;
                                              downPoint = null;
                                              // A tap on the selected piece
                                              // may mean the door beside it.
                                              if (tap && at != null)
                                                tapObject(e.localPosition, size);
                                              return;
                                            }
                                            final tapped = single &&
                                                downPoint != null &&
                                                (downPoint! - e.localPosition)
                                                            .distance *
                                                        canvasZoom <
                                                    8;
                                            if (tapped &&
                                                tool == 'placeFurniture') {
                                              placeFurnitureAt(
                                                  e.localPosition, size);
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (tapped && tool == 'measure') {
                                              addMeasurePoint(
                                                  e.localPosition, size);
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (single &&
                                                gesture == 'opening' &&
                                                !dragAttempted) {
                                              final opening = draggingOpening;
                                              setState(cancelDrag);
                                              if (opening != null)
                                                selectOpening(opening.opening);
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (single && gesture == 'edit') {
                                              final moved =
                                                  editPreviewStart != null;
                                              finishWallEdit();
                                              if (!moved)
                                                setState(() => reopenWallMenu(
                                                    e.localPosition, size));
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (tool == 'drawWall' &&
                                                single &&
                                                gesture == 'tap') {
                                              wallToolTap(
                                                  e.localPosition, size);
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (tool == 'drawWall' &&
                                                single &&
                                                gesture == 'draw' &&
                                                !wallFromAdjust &&
                                                strokeFromAttachment &&
                                                drawingEnd == null) {
                                              // A plus sits on a wall: tapping it
                                              // selects that wall; only a drag
                                              // draws a new one.
                                              setState(cancelDrag);
                                              wallToolTap(
                                                  e.localPosition, size);
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (tool == 'drawWall' &&
                                                single &&
                                                gesture == 'draw') {
                                              final tapFromAdjust =
                                                  wallFromAdjust &&
                                                      downPoint != null &&
                                                      (downPoint! - e.localPosition)
                                                                  .distance *
                                                              canvasZoom <
                                                          8;
                                              if (tapFromAdjust) {
                                                setState(() {
                                                  cancelDrag();
                                                  tool = 'selectWall';
                                                });
                                                tapObject(
                                                    e.localPosition, size);
                                              } else {
                                                finishWallStroke();
                                              }
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (tool == 'placeOpening' &&
                                                !cancelledStroke &&
                                                pointers.length == 1 &&
                                                downPoint != null &&
                                                (downPoint! - e.localPosition)
                                                        .distance <
                                                    8) {
                                              final box = canvasKey
                                                      .currentContext!
                                                      .findRenderObject()
                                                  as RenderBox;
                                              previewOpening(
                                                  placingOpening!,
                                                  box.localToGlobal(
                                                      e.localPosition));
                                              final args = openingDrop;
                                              derive();
                                              if (args != null)
                                                placeOpening(args);
                                              else
                                                setState(() {});
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (spatialTool &&
                                                !cancelledStroke &&
                                                pointers.length == 1) {
                                              finishSpatial();
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (dragAttempted &&
                                                !cancelledStroke &&
                                                pointers.length == 1) {
                                              final kind = dragKind,
                                                  arguments = dragArguments,
                                                  valid = dragValid,
                                                  message = placementHint;
                                              cancelDrag();
                                              if (valid &&
                                                  kind != null &&
                                                  arguments != null)
                                                action(kind, arguments);
                                              else {
                                                setState(() {});
                                                if (message != null)
                                                  notify(message);
                                              }

                                              if (tool == 'wall')
                                                setState(() {
                                                  tool = 'browse';
                                                  browse = true;
                                                  selectedWall = null;
                                                  placementHint = null;
                                                });
                                              pointers.remove(e.pointer);
                                              lastPoint = null;
                                              downPoint = null;
                                              return;
                                            }
                                            if ((browse ||
                                                    tool == 'editWall' ||
                                                    tool == 'selectWall' ||
                                                    tool == 'opening' ||
                                                    tool == 'grid') &&
                                                !cancelledStroke &&
                                                pointers.length == 1 &&
                                                downPoint != null &&
                                                (downPoint! - e.localPosition)
                                                        .distance <
                                                    8) {
                                              tapObject(e.localPosition, size);
                                            }
                                            if (tool == 'stair' &&
                                                !cancelledStroke &&
                                                stroke.isNotEmpty &&
                                                pointers.length == 1) {
                                              final first = stroke.first,
                                                  last = stroke.last;
                                              final i0 =
                                                      math.min(first.i, last.i),
                                                  i1 = math.max(
                                                          first.i, last.i) +
                                                      1,
                                                  j0 =
                                                      math.min(first.j, last.j),
                                                  j1 = math.max(
                                                          first.j, last.j) +
                                                      1;
                                              action('AddStair', {
                                                'floorId': floor.id,
                                                'type': StairType.straight,
                                                'region': AxisRectangle(
                                                    x0: base.axes.v[i0].id,
                                                    x1: base.axes.v[i1].id,
                                                    y0: base.axes.h[j0].id,
                                                    y1: base.axes.h[j1].id)
                                              });
                                              stroke.clear();
                                            }
                                            if (tool == 'room' &&
                                                !browse &&
                                                !cancelledStroke &&
                                                pointers.length == 1 &&
                                                stroke.isNotEmpty) {
                                              final cells = List.of(stroke);
                                              stroke.clear();
                                              action(
                                                  erase
                                                      ? 'EraseCells'
                                                      : 'PaintCells',
                                                  {
                                                    'floorId': floor.id,
                                                    'cells': cells,
                                                    'roomType': brush
                                                  });
                                            }
                                            pointers.remove(e.pointer);
                                            lastPoint = null;
                                          },
                                          child: DragTarget<OpeningKind>(
                                              onWillAcceptWithDetails: (_) =>
                                                  true,
                                              onMove: (details) => setState(() =>
                                                  previewOpening(
                                                      details.data,
                                                      details.offset +
                                                          openingDropPoint)),
                                              onLeave: (_) => setState(() {
                                                    openingDrop = null;
                                                    placementHint = null;
                                                    derive();
                                                  }),
                                              onAcceptWithDetails: (details) {
                                                previewOpening(
                                                    details.data,
                                                    details.offset +
                                                        openingDropPoint);
                                                final arguments = openingDrop;
                                                final message = placementHint;
                                                openingDrop = null;
                                                placementHint = null;
                                                derive();
                                                if (arguments != null)
                                                  placeOpening(arguments);
                                                else {
                                                  setState(() {});
                                                  notify(message == null ||
                                                          message == dragOntoWallHint
                                                      ? tr('没有放上墙：请把${openingNames[details.data]}拖到墙上再松手',
                                                          '${openingNames[details.data]} қабырғаға қойылмады: оны қабырғаға апарып жіберіңіз')
                                                      : message);
                                                }
                                              },
                                              builder: (context, candidates, rejected) =>
                                                  CustomPaint(
                                                      key: canvasKey,
                                                      size: size,
                                                      painter: FloorPlanPainter(
                                                          displayBase,
                                                          {
                                                            for (final r
                                                                in displayRooms)
                                                              r.id: displayRoomName(r)
                                                          },
                                                          const {},
                                                          viewportInsets:
                                                              canvasInsets,
                                                          openings:
                                                              displayOpenings,
                                                          stairs: derived
                                                              .floors[
                                                                  floorIndex]
                                                              .stairs,
                                                          northAngleDeg: history
                                                              .present
                                                              .footprint
                                                              .northAngleDeg,
                                                          focus: focus,
                                                          editableWall: (tool == 'editWall' || tool == 'drawWall') && editStart != null && editEnd != null ? PlanRect((editPreviewStart ?? editStart)!.dx, (editPreviewStart ?? editStart)!.dy, (editPreviewEnd ?? editEnd)!.dx, (editPreviewEnd ?? editEnd)!.dy) : null,
                                                          wallSeed: tool == 'drawWall' ? drawingOrigin : null,
                                                          wallAttachments: (tool == 'drawWall' || tool == 'selectWall') && drawingEnd == null && editPreviewStart == null ? visibleWallAttachments(size) : const [],
                                                          handleScale: canvasZoom,
                                                          draftLabel: wallDraftLabel,
                                                          draftEnd: tool == 'drawWall' && drawingStrokeActive && drawingEnd != null
                                                              ? drawingEnd
                                                              : wallGrip == 'start'
                                                                  ? editPreviewStart
                                                                  : wallGrip == 'end'
                                                                      ? editPreviewEnd
                                                                      : null,
                                                          draftConnected: drawConnected,
                                                          coach: coachArrow(size),
                                                          draft: tool == 'drawWall' && drawingEnd != null && drawingOrigin != null ? PlanRect(math.min(drawingOrigin!.dx, drawingEnd!.dx), math.min(drawingOrigin!.dy, drawingEnd!.dy), math.max(drawingOrigin!.dx, drawingEnd!.dx), math.max(drawingOrigin!.dy, drawingEnd!.dy)) : spatialPreview,
                                                          showGridDimensions: tool == 'grid',
                                                          draftInvalid: spatialError != null,
                                                          draftIsLine: tool == 'split' || tool == 'drawWall',
                                                          viewport: draggingAxis?.kind == 'boundary' && dragAttempted && dragCoordinatePainter != null
                                                              ? (
                                                                  scale: dragCoordinatePainter!
                                                                      .scale(
                                                                          size),
                                                                  origin: dragCoordinatePainter!
                                                                      .origin(
                                                                          size)
                                                                )
                                                              : null,
                                                          resizeHandles: tool == 'resize',
                                                          wallHandle: tool == 'wall' && selectedWall != null ? (selectedWall!.axis.dir == AxisDir.V ? PlanRect((dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.start.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.end.pos.toDouble()) : PlanRect(selectedWall!.start.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.end.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()))) : null,
                                                          tokens: Tokens.of(context),
                                                          bearingMin: history.present.extras.foundation.bearingMin,
                                                          furniture: [for (final f in history.present.extras.furniture) if (f.floorId == floor.id && f.id != furnitureDraft?.id) f],
                                                          furnitureDraft: furnitureDraft,
                                                          selectedFurniture: selectedFurnitureId,
                                                          selectedRoom: selectedRoomId,
                                                          showFurniture: showFurniture,
                                                          showDimensions: showDimensions,
                                                          foundation: showFoundation && floorIndex == 0 ? foundationTakeoff(history.present, derived) : null,
                                                          sleeves: history.present.extras.sleeves,
                                                          highlights: highlights,
                                                          pulse: pulse,
                                                          measure: measurePoints,
                                                          preview: List.of(stroke)))))));
                            });
}
