import '../../core/number_input.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import '../../core/house_core.dart';
import '../../core/commands/room_commands.dart';
import '../../core/geometry/floor_base.dart';
import '../../core/geometry/furniture_snap.dart';
import '../../core/history/design_history.dart';
import '../../core/commands/delete_axis.dart';
import '../../core/commands/house_spec.dart';
import '../../core/commands/house_templates.dart';
import '../../core/commands/kz_template.dart';
import '../../core/geometry/derived_house.dart';
import '../../core/checks/check_engine.dart';
import '../../render3d/scene_view.dart';
import '../../render2d/floor_plan_painter.dart';
import '../../render2d/project_preview.dart';
import '../../storage/project_store.dart';
import '../../storage/house_import.dart';
import '../../storage/last_open.dart';
import 'footprint_sketch.dart';
import 'wall_length_dialog.dart';
import 'wall_attachment_points.dart';
import 'wall_snap.dart';
import 'drawing_export.dart';
import '../../app/image_bytes.dart';
import '../../app/messages.dart';
import '../../app/settings.dart';
import '../../app/tokens.dart';
import '../../app/ui.dart';
import '../../core/analysis/house_analysis.dart';
import '../../core/analysis/design_summary.dart';
import '../../core/commands/extras_commands.dart';
import '../../render2d/furniture_names.dart';
import '../../render2d/section_painters.dart';
import '../../core/checks/construction_checks.dart';
import '../../core/analysis/build_schedule.dart';
import '../../core/analysis/cost_estimate.dart';
import '../../core/analysis/heat_loss.dart';
import '../../core/analysis/site_analysis.dart';
import '../../core/analysis/utility_plan.dart';
import '../../render2d/planning_names.dart';
import '../../render2d/site_plan_painter.dart';
import '../../shared/motion/motion.dart';
import '../../voice/action.dart';
import '../../voice/actions_design.dart';
import '../../voice/actions_houses.dart';
import '../../voice/scene.dart';
import '../../voice/screen.dart';
import '../../voice/session.dart';
import '../../voice/voice_overlay.dart';
import 'house_wizard.dart';

part 'roof_picker.dart';
part 'editor_header.dart';
part 'plan_tab.dart';
part 'selection_cards.dart';
part 'furniture_tool.dart';
part 'other_tabs.dart';
part 'scene_tab.dart';
part 'home_screen.dart';
part 'compare_card.dart';
part 'cost_tab.dart';
part 'heat_tab.dart';
part 'site_tab.dart';
part 'build_tab.dart';
part 'utility_tool.dart';
part 'outline_tool.dart';
part 'editor_dialogs.dart';
part 'wall_tool.dart';
part 'drag_tool.dart';
part 'stair_tool.dart';
part 'picking.dart';

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

/// What a press on the plan does. One at a time; [EditorTool.browse] is
/// the rest state every other tool goes back to (Esc, the browse button,
/// another tab or floor).
enum EditorTool {
  /// Pan, zoom and tap to pick.
  browse,

  /// Draw walls from point to point; a wall tapped while drawing is edited.
  drawWall,

  /// Pick a wall to edit (phone: under 更多工具).
  selectWall,

  /// Move or retype the picked wall's ends.
  editWall,

  /// Drag a straight line across a room to split it.
  split,

  /// Drag a rectangle to carve a room.
  box,

  /// Drag the outline's handles to change the house size.
  resize,

  /// Tap a wall to put the chosen door or window there.
  placeOpening,

  /// Tap to put the chosen furniture.
  placeFurniture,

  /// Tap to put the chosen socket, switch, light or pipe point.
  placeUtility,

  /// Tap points to measure between them.
  measure,

  /// Drag the picked grid wall to move it (advanced).
  wall,

  /// Select openings (advanced).
  opening,

  /// Edit the grid (advanced).
  grid,

  /// Paint or erase rooms over grid cells (advanced, see `erase`).
  room,

  /// Place a stair (advanced).
  stair,
}

/// The open design's state on disk. An edit makes it unsaved; a save
/// leaves it saved (or saved with the project index still to repair), or
/// unsaved again when it changed meanwhile, or failed, which retries every
/// five seconds until a save works.
enum _SaveStatus {
  saved('已保存'),
  indexPending('已保存，索引待恢复'),
  unsaved('未保存'),
  failed('保存失败');

  const _SaveStatus(this.label);

  /// What screen readers are told, as before.
  final String label;
}

class _HouseEditorState extends State<HouseEditor>
    with WidgetsBindingObserver, TickerProviderStateMixin, VoiceScreen
    implements DesignHost {
  @override
  String get screenId => 'editor.$tab';

  /// Floors as f1, f2…, and on the floor being edited rooms as r1…,
  /// openings as o1… and furniture as u1…, in document order.
  @override
  List<Entity> get entities => [
        for (final (i, f) in history.present.floors.indexed)
          Entity('floor', f.id, alias: 'f${i + 1}', title: f.name),
        for (final (i, r) in floor.rooms.indexed)
          Entity('room', r.id, alias: 'r${i + 1}', title: r.name),
        for (final (i, o) in floor.openings.indexed)
          Entity('opening', o.id,
              alias: 'o${i + 1}', title: openingKindName(o)),
        for (final (i, f) in history.present.extras.furniture
            .where((f) => f.floorId == floor.id)
            .indexed)
          Entity('furniture', f.id,
              alias: 'u${i + 1}', title: furnitureName(f.kind)),
        for (final (i, s) in floor.stairs.indexed)
          Entity('stair', s.id,
              alias: 's${i + 1}', title: tr3('楼梯', 'Баспалдақ', 'Лестница')),
      ];

  @override
  String get scene => designScene(
      doc: history.present,
      derived: derived,
      floorIndex: floorIndex,
      aliases: {for (final e in entities) e.id: e.alias},
      selectedId: selectedFurnitureId ?? selectedOpeningId ?? selectedRoomId);

  /// The tool in hand, so the assistant knows what a tap on the plan does
  /// right now; nothing while browsing.
  @override
  String get summary => browse ? '' : 'tool: ${tool.name}';

  @override
  HouseDocument get document => history.present;

  @override
  FloorBase get floorBase => base;

  @override
  List<String> get actions => [for (final a in designActions) a.id];

  @override
  String get currentFloorId => floor.id;

  @override
  CommandResult runDesign(String kind, Map<String, dynamic> args) =>
      action(kind, args, quiet: true);

  @override
  void beginUndoGroup() => history.beginGroup();

  @override
  void endUndoGroup() => history.endGroup();

  @override
  void replaceDesign(HouseDocument doc) {
    setState(() {
      cancelDrag();
      clearSelection();
      if (history.commit(composeDocument(
          history.present.meta, extractDesignState(doc)))) changed();
      floorIndex = 0;
      dropStaleWallState();
    });
  }

  @override
  Future<void> saveNow() => save();

  @override
  bool select(String id) {
    final room = floor.rooms.any((r) => r.id == id),
        opening = floor.openings.any((o) => o.id == id),
        piece = history.present.extras.furniture
            .any((f) => f.id == id && f.floorId == floor.id);
    if (!room && !opening && !piece) return false;
    setState(() {
      clearSelection();
      clearWallSelection();
      if (room) selectedRoomId = id;
      if (opening) selectedOpeningId = id;
      if (piece) selectedFurnitureId = id;
      panelCollapsed = phoneTools;
      tab = 'plan';
    });
    if (room) revealRoom(id);
    return true;
  }

  @override
  bool showFloor(String floorId) {
    final index = history.present.floors.indexWhere((f) => f.id == floorId);
    if (index < 0) return false;
    setState(() {
      cancelDrag();
      clearSelection();
      clearWallSelection();
      floorIndex = index;
      derive();
    });
    return true;
  }

  @override
  bool undoDesign() {
    final can = history.canUndo;
    undo();
    return can;
  }

  late final DesignHistory history;
  late FloorBase base;
  late DerivedHouse derived;
  // The estimate shown beside the plan, worked out once per change.
  HouseDocument? costChipFor;
  String costChip = '';

  /// How many findings of the issues tab ask for a change (严重 and 建议改),
  /// counted once per document for the plan page's reminder.
  HouseDocument? issueCountFor;
  ({int crit, int warn}) issueCount = (crit: 0, warn: 0);
  /// Current page: plan, ext (3D), walk, site, det, heat, qty, cost, build
  /// or iss.
  String tab = 'plan';
  bool get view3d => tab != 'plan';
  set view3d(bool value) {
    if (value != view3d) tab = value ? 'ext' : 'plan';
  }

  /// Plan layers, the selection shown in the card, and transient marks.
  bool showFurniture = true, showDimensions = true, showFoundation = false;
  bool showUtilities = false;

  /// Utility point being placed, the selected one and its drag preview.
  UtilityKind? placingUtility;
  String? selectedUtilityId;
  UtilityPoint? utilityDraft;
  Offset? utilityDown;

  /// Site page: the selected item ('@house' for the house), where it was
  /// grabbed, its dragged position and issue areas to flash.
  String? selectedSiteId;
  Offset? siteDown;
  ({int x, int y})? siteDraft;
  List<PlanRect> siteHighlights = [];

  /// The schedule stage opened to show its checklist.
  String? expandedStage;
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

  /// The ten pages in the order of their three groups.
  List<(String, String)> get editorTabs => [
        ('plan', tr3('2D 平面', '2D жоспар', '2D-план')),
        ('site', tr3('宅基地', 'Учаске', 'Участок')),
        ('iss', tr3('问题清单', 'Мәселелер тізімі', 'Список замечаний')),
        ('ext', tr3('3D 外观', '3D сыртқы көрініс', '3D-вид снаружи')),
        ('walk', tr3('室内漫游', 'Ішкі серуен', 'Прогулка по дому')),
        ('cost', tr3('预算', 'Смета', 'Смета')),
        ('qty', tr3('门窗与工程量', 'Есік-терезе және көлем', 'Проёмы и объёмы работ')),
        ('build', tr3('施工进度', 'Құрылыс кестесі', 'График строительства')),
        ('det', tr3('构造细节', 'Құрылым бөлшектері', 'Детали конструкции')),
        ('heat', tr3('保温采暖', 'Жылу', 'Тепло')),
      ];

  /// Ten pages are too many to choose from in one row, so they sit in
  /// three groups by what one comes to do: draw, look, or count and build.
  static const tabGroups = {
    'draw': ['plan', 'site', 'iss'],
    'view': ['ext', 'walk'],
    'build': ['cost', 'qty', 'build', 'det', 'heat'],
  };
  String get tabGroup =>
      tabGroups.entries.firstWhere((e) => e.value.contains(tab)).key;

  /// The page last open in each group; its group button returns there.
  final lastInGroup = <String, String>{};

  void showTab(String value) {
    if (value == tab) return;
    setState(() {
      cancelDrag();
      clearWallSelection();
      tab = value;
      lastInGroup[tabGroup] = value;
      if (value != 'plan') {
        tool = EditorTool.browse;
        drawingOrigin = null;
        drawingEnd = null;
        placementHint = null;
      }
    });
  }

  Widget tabBody(bool wide) => switch (tab) {
        'plan' => planTab(wide),
        'ext' || 'walk' => sceneTab(wide),
        'site' => siteTab(wide),
        'det' => detailsTab(wide),
        'heat' => heatTab(wide),
        'qty' => quantitiesTab(wide),
        'cost' => costTab(wide),
        'build' => buildTab(wide),
        _ => issuesTab(wide),
      };

  void clearSelection() {
    selectedRoomId = null;
    selectedOpeningId = null;
    selectedFurnitureId = null;
    selectedUtilityId = null;
    utilityDraft = null;
    utilityDown = null;
    furnitureDraft = null;
    furnitureGrip = null;
  }

  /// Delete key: the selected wall, furniture or door/window.
  void deleteSelection() {
    if (editStart != null) {
      deleteSelectedWall();
    } else if (selectedUtilityId != null) {
      final id = selectedUtilityId!;
      setState(clearSelection);
      action('DeleteUtility', {'utilityId': id});
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
  String displayFloorName(String name) => floorDisplayName(name);

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

  EditorTool tool = EditorTool.browse;

  /// Panning and tapping to pick, nothing being drawn or placed.
  bool get browse => tool == EditorTool.browse;
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

  /// Tool names: Chinese key → (Chinese short, Kazakh full, Kazakh short).
  static const toolText = {
    '浏览': ('浏览', 'Шолу', 'Шолу'),
    '墙体': ('墙体', 'Қабырға салу', 'Қабырға'),
    '独立墙': ('独立墙', 'Бөлек қабырға', 'Бөлек'),
    '拉线分房': ('分房', 'Сызықпен бөлу', 'Бөлу'),
    '拖动划房': ('框房', 'Бөлме сызу', 'Бөлме'),
    '加房间': ('加房间', 'Бөлме қосу', 'Бөлме +'),
    '拖入门': ('门', 'Есік қосу', 'Есік'),
    '拖入窗': ('窗', 'Терезе қосу', 'Терезе'),
    '家具': ('家具', 'Жиһаз қою', 'Жиһаз'),
    '水电': ('水电', 'Су-электр нүктелері', 'Су-электр'),
    '更多工具': ('更多', 'Басқа құралдар', 'Басқа'),
    '墙体调整': ('改墙', 'Қабырғаны түзету', 'Түзету'),
    '房屋尺寸': ('房屋尺寸', 'Үй өлшемі', 'Өлшем'),
  };

  String toolLabel(String label) {
    final text = toolText[label];
    if (text == null) return label;
    return tr(text.$1, text.$3);
  }

  String toolTip(String label) {
    final text = toolText[label];
    return text == null ? label : tr(label, text.$2);
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
                      placingUtility = null;
                      measurePoints = [];
                      roomStamp = null;
                      onTap();
                      if (mounted) setState(() {});
                    },
                    child: SizedBox(
                        // Seven tools fit a phone row at 45 wide.
                        width: math.max(
                            phoneTools ? 45 : 52,
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

  /// Usual sizes to start from, metres (width, depth).
  static const roomSizes = {
    RoomType.living: (4.5, 5.0),
    RoomType.bedroom: (3.6, 4.0),
    RoomType.kitchen: (3.0, 3.6),
    RoomType.bathroom: (1.8, 2.4),
    RoomType.dining: (3.0, 3.6),
    RoomType.hall: (2.0, 2.4),
    RoomType.corridor: (1.2, 3.0),
    RoomType.storage: (1.5, 2.0),
    RoomType.boiler: (2.0, 2.5),
    RoomType.custom: (3.0, 3.0),
  };

  OpeningKind? draggingNewOpening;

  String openingName(Opening o) => switch (o) {
        DoorOpening() => tr3('门', 'есік', 'дверь'),
        WindowOpening() => tr3('窗', 'терезе', 'окно'),
        SlidingOpening() => tr3('推拉门', 'сырғымалы есік', 'раздвижная дверь')
      };

  Map<OpeningKind, String> get openingNames => {
        OpeningKind.door: tr3('门', 'есік', 'дверь'),
        OpeningKind.window: tr3('窗', 'терезе', 'окно'),
        OpeningKind.sliding: tr3('推拉门', 'сырғымалы есік', 'раздвижная дверь')
      };

  /// The dragged door or window floats above the finger so the snapped
  /// preview on the wall stays visible. Its arrow tip, not the finger, is
  /// where it lands.
  static const openingDragAnchor = Offset(36, 104);
  static const openingDropPoint = Offset(36, 76);

  Widget openingTool(OpeningKind kind, IconData icon, String label) {
    final button = basicTool(
        icon, label, tool == EditorTool.placeOpening && placingOpening == kind, () {
      placingOpening = kind;
      tool = EditorTool.placeOpening;
      placementHint = tr3('点一下墙面放置，也可以从工具栏直接拖入', 'Қабырғаны басып қойыңыз, не құралдар жолынан сүйреп әкеліңіз', 'Нажмите на стену, чтобы поставить, или перетащите с панели инструментов');
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

  bool get spatialTool => tool == EditorTool.box || tool == EditorTool.split;

  /// A room of a set size being slid into place: the box tool with the
  /// rectangle given instead of drawn. Null while a rectangle is drawn.
  ({int w, int d})? roomStamp;

  /// Where in the stamp the finger holds it, from its lower left corner.
  Offset stampGrab = Offset.zero;
  bool get stamping => tool == EditorTool.box && roomStamp != null;

  /// The stamp is a stair, not a room; with [movingStairId] one that is
  /// already there, being put somewhere else or given another size.
  bool stampStair = false;
  String? movingStairId;
  bool get stairStamping => stamping && stampStair;

  /// Whether the floor underneath shows through the plan of this one.
  bool showBelow = true;

  /// The stair's width and length typed in; it stays on its corner.
  Future<void> resizeStair(Stair stair) async {
    final at = resolveRect(base.axes, stair.region).rect;
    if (at == null) return;
    final w = await length(tr3('楼梯间的宽（米）', 'Баспалдақ орнының ені (м)', 'Ширина места под лестницу (м)'),
        at.right - at.left);
    if (w == null || !mounted) return;
    final d = await length(tr3('楼梯间的长（米）', 'Баспалдақ орнының ұзындығы (м)', 'Длина места под лестницу (м)'),
        at.top - at.bottom);
    if (d == null || !mounted) return;
    startStairStamp(moving: stair, size: (w: w, d: d));
    setState(() =>
        setStamp(at.left.toDouble(), at.bottom.toDouble(), reach: 0));
  }

  /// Puts the stamp's lower left corner near ([x], [y]): inside the house,
  /// on a wall line when one is close, else on the 100 mm grid.
  void setStamp(double x, double y, {double reach = 250}) {
    final s = roomStamp!, fp = history.present.footprint;
    int place(double low, int length, int extent, List<ResolvedAxis> axes) {
      final v = low.round().clamp(0, math.max(0, extent - length));
      for (final a in axes) {
        if ((a.pos - v).abs() < reach) return a.pos;
      }
      for (final a in axes) {
        if ((a.pos - (v + length)).abs() < reach) return a.pos - length;
      }
      return ((v / 100).round() * 100).clamp(0, math.max(0, extent - length));
    }

    final left = place(x, s.w, fp.width, base.axes.v),
        bottom = place(y, s.d, fp.depth, base.axes.h);
    spatialStart = Offset(left.toDouble(), bottom.toDouble());
    spatialEnd = Offset((left + s.w).toDouble(), (bottom + s.d).toDouble());
    spatialPreview = PlanRect(spatialStart!.dx, spatialStart!.dy,
        spatialEnd!.dx, spatialEnd!.dy);
    validateSpatialPreview();
    if (spatialError == null) placementHint = null;
  }

  /// Starts sliding a [type] room of [w] × [d] mm, first in the corner
  /// asked for, or the first corner where it fits.
  void startStamp(RoomType type, int w, int d, String corner) {
    final fp = history.present.footprint;
    setState(() {
      clearSelection();
      clearWallSelection();
      view3d = false;
      tool = EditorTool.box;
      brush = type;
      stampStair = false;
      movingStairId = null;
      roomStamp = (w: w, d: d);
      for (final c in [corner, 'bl', 'br', 'tl', 'tr']) {
        setStamp(c.endsWith('l') ? 0 : (fp.width - w).toDouble(),
            c.startsWith('b') ? 0 : (fp.depth - d).toDouble());
        if (spatialError == null) break;
      }
    });
    if (spatialPreview != null) reveal(spatialPreview!);
  }

  void cancelStamp() => setState(() {
        roomStamp = null;
        stampStair = false;
        movingStairId = null;
        spatialStart = null;
        spatialEnd = null;
        spatialPreview = null;
        spatialDocument = null;
        spatialBase = null;
        spatialError = null;
        placementHint = null;
        tool = EditorTool.browse;
      });

  /// Builds the room where the stamp lies and shows its card.
  void placeStamp() {
    final r = spatialPreview;
    if (r == null) return;
    if (spatialError != null) {
      notify(spatialError!);
      return;
    }
    final known = {for (final room in floor.rooms) room.id};
    final args = <String, dynamic>{
      'floorId': floor.id,
      'left': r.left.round(),
      'bottom': r.bottom.round(),
      'right': r.right.round(),
      'top': r.top.round(),
      'roomType': brush
    };
    if (stampStair) {
      final moving = movingStairId, before = history.present;
      cancelStamp();
      action('PlaceStair', {...args, if (moving != null) 'stairId': moving}
        ..remove('roomType'));
      if (history.present != before)
        notify(
            moving != null
                ? tr3('楼梯已挪好', 'Баспалдақ жылжытылды', 'Лестница перенесена')
                : tr3('楼梯已放好，楼上自动留出洞口 · 点楼梯可以挪动或换样式',
                    'Баспалдақ қойылды, жоғарғы қабатта ойық қалдырылды · оны басып жылжытуға не түрін өзгертуге болады',
                    'Лестница поставлена, проём наверху оставлен · нажмите на неё, чтобы передвинуть или сменить вид'),
            undo: undo);
      return;
    }
    cancelStamp();
    action('CarveRoom', args);
    final added =
        floor.rooms.where((room) => !known.contains(room.id)).firstOrNull;
    if (added == null) return;
    setState(() {
      selectedRoomId = added.id;
      panelCollapsed = phoneTools;
    });
    revealRoom(added.id);
  }

  Offset? downPoint;

  /// Screen point of a finger that is dragging a wall, door, room edge or
  /// piece of furniture: a magnifier shows what the finger covers.
  Offset? loupeAt;
  final planSheetKey = GlobalKey();
  int floorIndex = 0;
  RoomType brush = RoomType.living;
  bool erase = false, dirty = false, saving = false;
  _SaveStatus status = _SaveStatus.saved;
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

  double lastCanvasZoom = 1;

  /// Ticks when the zoom changes: only the plan canvas listens, so a pinch
  /// rebuilds the drawing (grip and label sizes) and not the whole editor.
  final canvasZoomChanged = ValueNotifier<double>(1);

  /// A pure pan only moves the cached drawing. A zoom change rebuilds the
  /// plan canvas alone; the whole editor is rebuilt only while something
  /// outside the canvas follows the view (the wall menu, the loupe).
  void onCanvasTransformChanged() {
    if (!mounted) return;
    final zoom = canvasZoom;
    final follows = menuWall != null || loupeAt != null;
    if (zoom == lastCanvasZoom && !follows) return;
    lastCanvasZoom = zoom;
    if (follows) {
      setState(() {});
    } else {
      canvasZoomChanged.value = zoom;
    }
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
    canvasZoomChanged.dispose();
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
    if (mounted) setState(() => saving = true);
    try {
      await widget.store.saveProject(widget.entry.id, doc);
      if (mounted)
        setState(() {
          dirty = history.present != doc;
          status = dirty ? _SaveStatus.unsaved : widget.store.indexWarning != null ? _SaveStatus.indexPending : _SaveStatus.saved;
        });
    } catch (_) {
      failed = true;
      if (mounted) {
        final firstFailure = status != _SaveStatus.failed;
        setState(() => status = _SaveStatus.failed);
        if (firstFailure) notify(tr3('没能保存到本机，请检查存储空间；稍后会自动重试，也可导出备份', 'Құрылғыға сақталмады, жадты тексеріңіз; кейін қайталанады, файлды экспорттауға болады', 'Не удалось сохранить. Проверьте место; повторим автоматически. Можно экспортировать файл'));
      }
    } finally {
      saving = false;
      if (failed && mounted)
        timer = Timer(const Duration(seconds: 5), save);
      else if (mounted && dirty && history.present != doc)
        timer = Timer(const Duration(milliseconds: 1500), save);
    }
  }

  void changed() {
    focus = null;
    if (highlights.isNotEmpty) flash(const []);
    derive();
    dirty = true;
    status = _SaveStatus.unsaved;
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 1500), save);
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

  void cancelDrag() {
    wallHoldTimer?.cancel();
    if (pointers.isNotEmpty) cancelledStroke = true;
    spatialStart = null;
    spatialEnd = null;
    spatialPreview = null;
    downPoint = null;
    if (tool == EditorTool.drawWall && drawingStrokeActive)
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
    alignGuide = null;
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
      final filename = '${cleanedName.isEmpty ? tr3('房屋设计', 'Үй жобасы', 'Проект дома') : cleanedName}.house';
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
      notify(tr3('暂时无法导出这个设计', 'Жобаны қазір шығару мүмкін емес', 'Сейчас не удаётся экспортировать проект'));
    }
  }

  void placeOpening(Map<String, dynamic> arguments) {
    final before = history.present;
    final ids = {for (final o in floor.openings) o.id};
    action('AddOpening', arguments);
    if (history.present == before) return;
    // Select it at once: its card says how to change or delete it.
    final added = floor.openings.where((o) => !ids.contains(o.id)).firstOrNull;
    if (added != null) selectOpening(added);
    notify(
          tr3('已放置${openingNames[arguments['kind']]} · 可以直接拖动它调整位置',
              '${openingNames[arguments['kind']]} қойылды · оны сүйреп жылжытуға болады', 'Добавлено: ${openingNames[arguments['kind']]} · можно перетащить, чтобы изменить положение'),
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
            : SnackBarAction(label: tr3('撤销', 'Болдырмау', 'Отменить'), onPressed: undo)),
        snackBarAnimationStyle: Motion.toastStyle);
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
      if (tool == EditorTool.editWall) {
        tool = EditorTool.browse;
      }
    });
    notify(tr3('已撤销上一步', 'Соңғы әрекет болдырылмады', 'Последнее действие отменено'));
  }

  void redo() {
    if (!history.canRedo) return;
    setState(() {
      cancelDrag();
      history.redo();
      changed();
      dropStaleWallState();
      if (tool == EditorTool.editWall) {
        tool = EditorTool.browse;
      }
    });
    notify(tr3('已重做', 'Қайталанды', 'Действие повторено'));
  }

  /// Runs a design command and returns what came of it. A failure is
  /// shown to the user unless [quiet], for callers that report it
  /// themselves.
  CommandResult action(String kind, Map<String, dynamic> args,
      {bool quiet = false}) {
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
    } else if (!quiet) {
      final message = result is Rejected
          ? result.message
          : (result as NeedsResolution).conflict.message;
      notify(message);
    }
    return result;
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
                      child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: Text(tr3('确定', 'Жарайды', 'ОК')))
                ]));
  }

  Future<int?> length(String label, int value) async {
    final result =
        await ask(tr3('$label（米）', '$label (м)', '$label (м)'), (value / 1000).toStringAsFixed(2),
        number: true);
    final parsed = parseNumber(result ?? '');
    if (parsed == null) return null;
    return (parsed * 1000).round();
  }

  /// A floor on top of the house, by a button that says so: empty with
  /// the outer walls, or a copy of the floor under it.
  Future<void> addFloorAbove() async {
    final choice = await showMotionSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              ListTile(
                  key: const Key('add-floor-empty'),
                  leading: const Icon(Icons.crop_square),
                  title: Text(tr3('空的一层', 'Бос қабат', 'Пустой этаж')),
                  subtitle: Text(tr3('只带外墙，楼下的墙会淡淡地显示出来，照着画',
                      'Тек сыртқы қабырғалар; астыңғы қабаттың қабырғалары бозғылт көрінеді',
                      'Только наружные стены; стены нижнего этажа видны бледно, по ним удобно чертить')),
                  onTap: () => Navigator.pop(context, 'AddFloor')),
              ListTile(
                  key: const Key('add-floor-copy'),
                  leading: const Icon(Icons.copy_all_outlined),
                  title: Text(tr3('照楼下复制一层', 'Астыңғы қабатты көшіру', 'Скопировать нижний этаж')),
                  subtitle: Text(tr3('房间、墙和门窗都一样，再改不一样的地方',
                      'Бөлмелер, қабырғалар, есік-терезелер бірдей; кейін өзгертесіз',
                      'Те же комнаты, стены, окна и двери; потом измените, что нужно')),
                  onTap: () => Navigator.pop(context, 'CopyFloor')),
            ])));
    if (choice == null || !mounted) return;
    final before = history.present;
    action(choice, {'floorId': before.floors.last.id});
    if (history.present == before || !mounted) return;
    setState(() {
      cancelDrag();
      clearSelection();
      clearWallSelection();
      drawingOrigin = null;
      floorIndex = history.present.floors.length - 1;
      derive();
    });
    notify(
        tr3('已加上「${displayFloorName(floor.name)}」，现在画的是这一层',
            '«${displayFloorName(floor.name)}» қосылды, енді осы қабатты сызасыз',
            'Добавлен «${displayFloorName(floor.name)}», теперь вы чертите этот этаж'),
        undo: undo);
  }

  /// Show the card of [opening]; it can also be dragged on the plan.
  void selectOpening(Opening opening) => setState(() {
        clearSelection();
        clearWallSelection();
        selectedOpeningId = opening.id;
        panelCollapsed = phoneTools;
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

  /// Dashed alignment guide for the end being dragged (world mm).
  (Offset, Offset)? alignGuide;

  (Offset, Offset)? guideFor(WallEndSnap snap) {
    final v = snap.aligned;
    if (v == null) return null;
    final w = base.axes.v.last.pos.toDouble(), d = base.axes.h.last.pos.toDouble();
    // The end lies on an existing wall line across the drawing direction.
    return snap.horizontal
        ? (Offset(v, 0), Offset(v, d))
        : (Offset(0, v), Offset(w, v));
  }

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
        tool = EditorTool.editWall;
      }
      placementHint = tr3('拖两端改长度 · 拖墙身移动', 'Ұштарын сүйреп ұзындығын, денесін сүйреп орнын өзгертіңіз', 'Перетащите концы, чтобы изменить длину, или саму стену, чтобы переместить');
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
    alignGuide = null;
    editPreviewStart = null;
    editPreviewEnd = null;
    editCommand = null;
    editArgs = null;
    spatialError = null;
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
      if (tool == EditorTool.editWall) {
        tool = EditorTool.browse;
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
    placementHint = tr3('拖两端改长度 · 拖墙身移动', 'Ұштарын сүйреп ұзындығын, денесін сүйреп орнын өзгертіңіз', 'Перетащите концы, чтобы изменить длину, или саму стену, чтобы переместить');
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
    // Start at the left or bottom end, as the dialog names them.
    final ordered = editStart!.dx + editStart!.dy <= editEnd!.dx + editEnd!.dy;
    final start = ordered ? editStart! : editEnd!,
        end = ordered ? editEnd! : editStart!;
    final vertical = start.dx == end.dx;
    // Offer to keep the end that is joined to another wall and move the
    // free one; the user can pick the other end.
    final choice = await showDialog<WallResizeChoice>(
        context: context,
        builder: (_) => WallResizeDialog(
            initial: (end - start).distance.round(),
            vertical: vertical,
            keepEnd: selectedEndJoins(end) && !selectedEndJoins(start)));
    if (choice == null || !mounted) return;
    final value = choice.length, keepEnd = choice.keepEnd;
    final direction = vertical ? const Offset(0, 1) : const Offset(1, 0);
    final from = keepEnd ? end - direction * value.toDouble() : start,
        to = keepEnd ? end : start + direction * value.toDouble();
    final before = history.present;
    action('UpdateDrawnWall', wallEditArguments(from, to));
    if (history.present != before) {
      setState(() => refreshWallSelection(from, to));
      notify(tr3('墙长已改为 ${(value / 1000).toStringAsFixed(2)} 米',
          'Қабырға ұзындығы ${m2dp(value)} м болды', 'Длина стены теперь ${m2dp(value)} м'));
    }
  }

  Future<void> preciseWallPosition() async {
    if (editStart == null || editEnd == null) return;
    final vertical = editStart!.dx == editEnd!.dx;
    final value = await length(vertical ? tr3('墙到左侧外墙的距离', 'Сол сыртқы қабырғаға дейінгі қашықтық', 'Расстояние до левой наружной стены') : tr3('墙到下侧外墙的距离', 'Төменгі сыртқы қабырғаға дейінгі қашықтық', 'Расстояние до нижней наружной стены'),
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
    final seed = tool == EditorTool.drawWall ? drawingOrigin : null;
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
      if (tool == EditorTool.drawWall && drawingOrigin != null)
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
      if (tool == EditorTool.drawWall && drawingOrigin != null) drawingOrigin!,
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
        tool == EditorTool.drawWall ||
        tool == EditorTool.editWall ||
        tool == EditorTool.selectWall)) return;
    // Pressing a plus before dragging is common; it must not open a menu.
    if ((tool == EditorTool.drawWall || tool == EditorTool.selectWall) &&
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
      selectWallForEdit(wall, point.dx, point.dy, keepTool: tool == EditorTool.drawWall);
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
        placementHint = tr3('按住大 ＋ 拖出新墙', 'Үлкен ＋ белгісін ұстап, жаңа қабырға тартыңыз', 'Удерживайте большой ＋ и протяните новую стену');
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

  /// The figure of the dimension chain being typed over.
  DimensionSpan? editingDimension;

  /// The plan rectangle around the cells of the room with [roomId].
  PlanRect? roomBox(String roomId) {
    final cells = [
      for (final e in base.owners.entries)
        if (e.value == roomId) e.key
    ];
    if (cells.isEmpty) return null;
    final v = base.axes.v, h = base.axes.h;
    var box = PlanRect(v[cells.first.i].pos.toDouble(),
        h[cells.first.j].pos.toDouble(), v[cells.first.i + 1].pos.toDouble(),
        h[cells.first.j + 1].pos.toDouble());
    for (final c in cells.skip(1))
      box = PlanRect(
          math.min(box.left, v[c.i].pos.toDouble()),
          math.min(box.bottom, h[c.j].pos.toDouble()),
          math.max(box.right, v[c.i + 1].pos.toDouble()),
          math.max(box.top, h[c.j + 1].pos.toDouble()));
    return box;
  }

  /// Height the folded selection card takes from the bottom of the plan.
  static const foldedCardHeight = 132.0;

  /// Slides the plan, without zooming, until [box] shows above the folded
  /// selection card. A selection the card would cover is no selection.
  void reveal(PlanRect box) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || canvasSize.isEmpty || !phoneTools) return;
      final m = canvasTransform.value;
      final r = MatrixUtils.transformRect(
          m, interactionPainter().rectangle(box, canvasSize));
      final view = Rect.fromLTRB(12, 12, canvasSize.width - 12,
          canvasSize.height - foldedCardHeight);
      if (view.height < 80) return;
      double shift(double lo, double hi, double viewLo, double viewHi) {
        if (hi - lo > viewHi - viewLo)
          return (viewLo + viewHi) / 2 - (lo + hi) / 2;
        if (lo < viewLo) return viewLo - lo;
        if (hi > viewHi) return viewHi - hi;
        return 0;
      }

      final dx = shift(r.left, r.right, view.left, view.right),
          dy = shift(r.top, r.bottom, view.top, view.bottom);
      if (dx == 0 && dy == 0) return;
      canvasTransform.value = Matrix4.translationValues(dx, dy, 0)..multiply(m);
    });
  }

  void revealRoom(String roomId) {
    final box = roomBox(roomId);
    if (box != null) reveal(box);
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

  /// The loose end of the wall just drawn and the way it was heading,
  /// kept while that end is still where the next wall would start.
  ({Offset at, Offset heading})? looseEnd;

  /// Where the wall just drawn would meet the next wall if it ran on,
  /// for the "接到对面" button; null once its end is no longer loose.
  Offset? get reachAcrossPoint {
    final loose = looseEnd, origin = drawingOrigin;
    if (tool != EditorTool.drawWall ||
        drawingStrokeActive ||
        loose == null ||
        origin == null ||
        loose.at != origin) return null;
    return wallAhead(base, loose.at, loose.heading);
  }

  /// The wall a stroke was pulled out of, while its foot may still slide.
  WallSegment? slideHost;

  /// Clear distances along [host] from a new wall at [p] to the walls on
  /// either side of it: the figures the plan will show once it is built.
  (double, double) clearAlong(WallSegment host, double p) {
    final vertical = host.axis.dir == AxisDir.V;
    final c = host.axis.pos.toDouble();
    var lo = host.start.pos.toDouble(), hi = host.end.pos.toDouble();
    for (final w in wallsOf(base, const FoundationSpec())) {
      if (w.horizontal != vertical || w.role == WallRole.temporary) continue;
      final r = w.rect;
      final crosses = vertical
          ? r.left <= c + 1 && r.right >= c - 1
          : r.bottom <= c + 1 && r.top >= c - 1;
      if (!crosses) continue;
      final a = vertical ? r.bottom : r.left, b = vertical ? r.top : r.right;
      if (b <= p && b > lo) lo = b;
      if (a >= p && a < hi) hi = a;
    }
    final half = history.present.defaults.innerWallThickness / 2;
    return (p - half - lo, hi - p - half);
  }

  String? slideNote;

  void slideFoot(double x, double y) {
    final host = slideHost;
    if (host == null) return;
    final vertical = host.axis.dir == AxisDir.V;
    final lo = host.start.pos + 300.0, hi = host.end.pos - 300.0;
    if (hi <= lo) return;
    // Once the finger has left the wall the foot stays where it was put,
    // so a hand that drifts while drawing does not drag the wall along.
    if (((vertical ? x : y) - host.axis.pos).abs() > 500) {
      slideHost = null;
      return;
    }
    final along =
        (((vertical ? y : x) / 100).round() * 100.0).clamp(lo, hi).toDouble();
    final p = vertical
        ? Offset(host.axis.pos.toDouble(), along)
        : Offset(along, host.axis.pos.toDouble());
    if (!canExtendWallFrom(base, derived.floors[floorIndex].openings, p))
      return;
    drawingOrigin = p;
    final (a, b) = clearAlong(host, along);
    slideNote = vertical
        ? tr3('下边 ${m2dp(a)} 米 · 上边 ${m2dp(b)} 米',
            'Төменде ${m2dp(a)} м · жоғарыда ${m2dp(b)} м',
            'Снизу ${m2dp(a)} м · сверху ${m2dp(b)} м')
        : tr3('左边 ${m2dp(a)} 米 · 右边 ${m2dp(b)} 米',
            'Сол жақта ${m2dp(a)} м · оң жақта ${m2dp(b)} м',
            'Слева ${m2dp(a)} м · справа ${m2dp(b)} м');
  }

  void beginWallStroke(Offset local, Size size) {
    drawingStrokeActive = true;
    drawingBefore = drawingOrigin;
    final hit = attachmentAt(local, size);
    strokeFromAttachment = hit != null;
    slideHost = null;
    if (hit != null) {
      drawingOrigin = hit;
      // Pulled from the middle of a wall, the new wall's foot follows the
      // finger along that wall until it is pulled into the room.
      slideHost = base.wallSegments.where((w) {
        final vertical = w.axis.dir == AxisDir.V;
        final along = vertical ? hit.dy : hit.dx,
            cross = vertical ? hit.dx : hit.dy;
        return cross == w.axis.pos &&
            along > w.start.pos &&
            along < w.end.pos;
      }).firstOrNull;
    } else if (placingWallStart) {
      drawingOrigin = wallPoint(local, size);
      placingWallStart = false;
    }
    drawingEnd = null;
    drawConnected = false;
    alignGuide = null;
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
    slideNote = null;
    slideFoot(world.x, world.y);
    final snap = snapWallEnd(base, drawingOrigin!, Offset(world.x, world.y),
        connectRadius: 22 * pixel, alignRadius: 14 * pixel);
    if (snap.end != drawingEnd && snap.connected && !drawConnected)
      HapticFeedback.selectionClick();
    drawingEnd = snap.end;
    drawConnected = snap.connected;
    alignGuide = guideFor(snap);
    if ((drawingEnd! - drawingOrigin!).distance < 300) {
      resetPreview();
      spatialDocument = null;
      spatialBase = null;
      spatialError = null;
      // Still on the wall: say where the new wall would stand.
      if (slideNote != null)
        placementHint = tr3('$slideNote · 往里拖出墙', '$slideNote · ішке тартыңыз',
            '$slideNote · тяните внутрь');
      return;
    }
    final ok = tr3('松手建墙，末端可以继续拖', 'Жіберсеңіз қабырға салынады, ұшынан жалғастыруға болады', 'Отпустите, чтобы построить стену; от её конца можно продолжить');
    schedulePreview('AddDrawnWall', drawingArguments,
        ok: slideNote == null ? ok : '$slideNote · ${tr3('松手建墙', 'жіберіңіз', 'отпустите')}',
        failed: tr3('此处无法建墙', 'Мұнда қабырға салу мүмкін емес', 'Здесь нельзя построить стену'));
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

  String meters(num value) => m2dp(value);

  String get dragOntoWallHint =>
      tr3('拖到墙上，门窗会自动贴合', 'Қабырғаға апарыңыз, есік-терезе өзі орнығады', 'Перетащите на стену — окно или дверь встанет на место');

  bool get floorHasInnerWalls =>
      base.wallSegments.any((w) => w.axis.kind != 'boundary');

  bool get showWallCoach =>
      tool == EditorTool.drawWall &&
      !coachDismissed &&
      !drawingStrokeActive &&
      drawingOrigin == null &&
      menuWall == null &&
      !floorHasInnerWalls;

  bool get showStartCoach =>
      tool == EditorTool.browse &&
      !view3d &&
      !coachDismissed &&
      !floorHasInnerWalls &&
      floor.openings.isEmpty;

  String? get coachText => showWallCoach
      ? tr3('按住橙色 ＋ 往里拖，松手就建好一面墙', 'Сары ＋ белгісін ішке қарай тартыңыз, жіберсеңіз қабырға салынады', 'Удерживайте оранжевый ＋ и тяните внутрь: отпустите, и стена построена')
      : showStartCoach
          ? tr3('先点「墙体」，再按住 ＋ 往里拖', 'Алдымен «Қабырға» батырмасын, сосын ＋ белгісін ішке тартыңыз', 'Сначала нажмите «Стена», затем зажмите ＋ и тяните внутрь')
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
    if (tool == EditorTool.drawWall && drawingEnd != null && drawingOrigin != null)
      return '${meters((drawingEnd! - drawingOrigin!).distance)} $unitM';
    if (wallGrip == null || editPreviewStart == null || editPreviewEnd == null)
      return null;
    if (editCommand == 'MoveDrawnWall' ||
        (wallGrip == 'middle' && editStart != null)) {
      return tr3('移动 ${meters((editPreviewStart! - editStart!).distance)} 米',
          'Жылжыту ${meters((editPreviewStart! - editStart!).distance)} м', 'Сдвиг на ${meters((editPreviewStart! - editStart!).distance)} м');
    }
    return '${meters((editPreviewEnd! - editPreviewStart!).distance)} $unitM';
  }

  /// Live state while drawing or editing a wall: what will happen on release.
  ({String text, IconData icon, Color color})? get liveStatus {
    const good = Color(0xff286b50),
        warn = Color(0xff8a5a00),
        bad = Color(0xffa14539),
        info = Color(0xff4a5548);
    if (tool == EditorTool.drawWall &&
        drawingStrokeActive &&
        drawingOrigin != null &&
        drawingEnd != null) {
      final length = (drawingEnd! - drawingOrigin!).distance;
      if (length < 300)
        return (text: tr3('继续拖动 · 墙至少 0.30 米', 'Тарта беріңіз · қабырға кемінде 0,30 м', 'Тяните дальше · стена не короче 0,30 м'), icon: Icons.straighten, color: info);
      if (spatialError != null)
        return (text: spatialError!, icon: Icons.block, color: bad);
      final direction = drawingEnd!.dy == drawingOrigin!.dy ? tr3('横墙', 'Көлденең қабырға', 'Горизонтальная стена') : tr3('竖墙', 'Тік қабырға', 'Вертикальная стена');
      return drawConnected
          ? (
              text: tr3('$direction ${meters(length)} 米 · 已连到墙', '$direction ${meters(length)} м · қабырғаға жалғанды', '$direction ${meters(length)} м · соединена со стеной'),
              icon: Icons.link,
              color: good
            )
          : (
              text: tr3('$direction ${meters(length)} 米 · 末端没连墙', '$direction ${meters(length)} м · ұшы жалғанбаған', '$direction ${meters(length)} м · конец не соединён'),
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
                  ? tr3('房屋宽 ${meters(width)} 米 · 所有楼层一起改', 'Үй ені ${meters(width)} м · барлық қабат бірге өзгереді', 'Ширина дома ${meters(width)} м · меняются все этажи')
                  : tr3('房屋长 ${meters(depth!)} 米 · 所有楼层一起改', 'Үй ұзындығы ${meters(depth)} м · барлық қабат бірге өзгереді', 'Длина дома ${meters(depth)} м · меняются все этажи'),
              icon: Icons.open_in_full,
              color: good
            )
          : (
              text: placementHint ?? tr3('这个尺寸放不下已有的墙或房间', 'Бұл өлшемге бар қабырға не бөлме сыймайды', 'В этот размер не помещаются существующие стены или комнаты'),
              icon: Icons.block,
              color: bad
            );
    }
    if (draggingOpening != null && dragAttempted) {
      final name = openingName(draggingOpening!.opening);
      return dragValid
          ? (
              text: tr3('松手把$name放在这里', '$name осында қою үшін жіберіңіз', 'Отпустите, чтобы поставить здесь: $name'),
              icon: Icons.check_circle_outline,
              color: good
            )
          : (
              text: placementHint ?? tr3('这里放不下$name', '$name мұнда сыймайды', 'Здесь не помещается: $name'),
              icon: Icons.block,
              color: bad
            );
    }
    if (draggingNewOpening != null) {
      return openingDrop != null
          ? (
              text: tr3('已贴合墙面，松手放下${openingNames[draggingNewOpening]}',
                  'Қабырғаға орнықты, ${openingNames[draggingNewOpening]} қою үшін жіберіңіз', 'Привязано к стене, отпустите, чтобы поставить: ${openingNames[draggingNewOpening]}'),
              icon: Icons.check_circle_outline,
              color: good
            )
          : (
              text: placementHint ?? tr3('拖到墙上，门窗会自动贴合', 'Қабырғаға апарыңыз, есік-терезе өзі орнығады', 'Перетащите на стену — окно или дверь встанет на место'),
              icon: Icons.touch_app_outlined,
              color: warn
            );
    }
    if (wallGrip != null && editPreviewStart != null) {
      if (spatialError != null)
        return (text: spatialError!, icon: Icons.block, color: bad);
      if (editCommand == 'MoveDrawnWall')
        return (
          text: tr3('${wallDraftLabel!} · 相连的墙会跟着伸缩', '${wallDraftLabel!} · жалғас қабырғалар бірге созылады', '${wallDraftLabel!} · соединённые стены изменятся вместе'),
          icon: Icons.open_with,
          color: good
        );
      if (wallGrip == 'middle')
        return (text: wallDraftLabel!, icon: Icons.open_with, color: good);
      return drawConnected
          ? (
              text: tr3('墙长 ${wallDraftLabel!} · 已连到墙', 'Қабырға ${wallDraftLabel!} · қабырғаға жалғанды', 'Стена ${wallDraftLabel!} · соединена со стеной'),
              icon: Icons.link,
              color: good
            )
          : (
              text: tr3('墙长 ${wallDraftLabel!} · 这一端没连墙', 'Қабырға ${wallDraftLabel!} · бұл ұшы жалғанбаған', 'Стена ${wallDraftLabel!} · этот конец не соединён'),
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

  /// Where floating status and menus may start inside the plan sheet.
  double get overlayTop => 52;

  String get interactionHint =>
      (placementHint == null ? null : coreMessage(placementHint!)) ??
      (tool == EditorTool.drawWall
          ? tr3('按住 ＋ 拖出新墙 · 点墙修改 · 拖空白处移动画布', '＋ белгісін ұстап қабырға тартыңыз · қабырғаны басып өзгертіңіз · бос жерді сүйреп жылжытыңыз', 'Зажмите ＋ и вытяните стену · нажмите на стену, чтобы изменить · тяните пустое место, чтобы сдвинуть чертёж')
          : tool == EditorTool.selectWall
              ? tr3('点墙修改 · 拖 ＋ 接墙 · 拖空白处移动画布', 'Қабырғаны басып өзгертіңіз · ＋ белгісінен жалғаңыз · бос жерді сүйреп жылжытыңыз', 'Нажмите на стену, чтобы изменить · тяните ＋, чтобы пристроить стену · тяните пустое место, чтобы сдвинуть чертёж')
              : tool == EditorTool.editWall
                  ? tr3('拖两端改长度 · 拖墙身移动', 'Ұштарын сүйреп ұзындығын, денесін сүйреп орнын өзгертіңіз', 'Перетащите концы, чтобы изменить длину, или саму стену, чтобы переместить')
                  : tool == EditorTool.stair
                      ? tr3('在放楼梯的房间里点一下，或拖过几个格子', 'Баспалдақ тұратын бөлмені басыңыз не бірнеше ұяшықты сүйреңіз', 'Нажмите в комнате, где будет лестница, или проведите по нескольким клеткам')
                  : stairStamping
                      ? tr3('拖动楼梯到想要的位置，一般靠墙角放', 'Баспалдақты керек жерге сүйреңіз, әдетте бұрышқа қойылады', 'Перетащите лестницу на место, обычно её ставят в угол')
                  : stamping
                      ? tr3('拖动房间到想要的位置，靠近墙会自动贴上', 'Бөлмені керек жерге сүйреңіз, қабырғаға жақындаса өзі жабысады', 'Перетащите комнату на место: у стены она прилипнет сама')
                  : spatialTool
                      ? (tool == EditorTool.split ? tr3('拉一条横线或竖线，松手分房', 'Көлденең не тік сызық тартып, жіберсеңіз бөлінеді', 'Проведите горизонтальную или вертикальную линию и отпустите — комната разделится') : tr3('从一角拖到另一角，松手创建房间', 'Бір бұрыштан екіншісіне тартып жіберсеңіз, бөлме жасалады', 'Протяните от одного угла к другому и отпустите — комната будет создана'))
                      : tool == EditorTool.resize
                          ? tr3('拖右边或上边的圆形手柄改长宽 · 所有楼层一起改', 'Оң не жоғарғы дөңгелек тұтқаны сүйреп өлшемін өзгертіңіз · барлық қабат бірге өзгереді', 'Тяните круглую ручку справа или сверху, чтобы изменить размер · меняются все этажи')
                          : tr3('拖动画布 · 点选对象调整 · 双指缩放', 'Сызбаны сүйреп жылжытыңыз · нысанды басып өзгертіңіз · екі саусақпен үлкейтіңіз', 'Тяните, чтобы сдвинуть чертёж · нажмите на объект, чтобы изменить · масштаб двумя пальцами'));

  MouseCursor canvasCursor = MouseCursor.defer;

  /// What the mouse pointer would do here, shown before pressing.
  MouseCursor hoverCursor(Offset local, Size size) {
    if (view3d) return MouseCursor.defer;
    final wallTools = tool == EditorTool.drawWall || tool == EditorTool.editWall;
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
    if (tool == EditorTool.resize) {
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
    if ((tool == EditorTool.drawWall || tool == EditorTool.selectWall) &&
        attachmentAt(local, size) != null) return SystemMouseCursors.click;
    if (openingAt(local, size) != null) return SystemMouseCursors.grab;
    if ((browse || wallTools || tool == EditorTool.selectWall) &&
        wallAtPoint(local, size, radius: 16) != null)
      return SystemMouseCursors.click;
    return browse || wallTools || tool == EditorTool.selectWall
        ? SystemMouseCursors.grab
        : MouseCursor.defer;
  }

  /// Saved state at a glance: icon plus a word, red when saving failed.
  Widget saveIndicator() {
    final failed = status == _SaveStatus.failed,
        color = failed ? Theme.of(context).colorScheme.error : null;
    return Semantics(
        liveRegion: true,
        label: status.label,
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
                      ? tr3('保存中', 'Сақталуда', 'Сохранение')
                      : switch (status) {
                          _SaveStatus.saved => tr3('已保存', 'Сақталды', 'Сохранено'),
                          _SaveStatus.indexPending => tr3('设计已保存，索引待恢复', 'Жоба сақталды, индекс қалпына келеді', 'Проект сохранён, индекс требует восстановления'),
                          _SaveStatus.unsaved => tr3('未保存', 'Сақталмаған', 'Не сохранено'),
                          _SaveStatus.failed => tr3('保存失败', 'Сақталмады', 'Ошибка сохранения'),
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
        if (tool == EditorTool.editWall) {
          tool = EditorTool.browse;
        }
      } else if (tool != EditorTool.browse) {
        tool = EditorTool.browse;
        drawingOrigin = null;
        placingWallStart = false;
        placingUtility = null;
      } else if (selectedUtilityId != null) {
        selectedUtilityId = null;
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
                                      groupedTabs(),
                                    ],
                                    Expanded(child: tabBody(wide)),
                                  ])));
                    }))))));
  }

  /// The plan drawing with all editing gestures; sized by its sheet.
  Widget planCanvas() => ListenableBuilder(
      listenable: canvasZoomChanged,
      builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
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
                                              tool == EditorTool.measure ||
                                              tool == EditorTool.placeFurniture ||
                                              tool == EditorTool.placeUtility) &&
                                          draggingOpening == null &&
                                          furnitureGrip == null &&
                                          utilityDown == null) ||
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
                                                  beginUtilityGesture(
                                                      e.localPosition, size)) {
                                                setState(() {});
                                              } else if (browse &&
                                                  beginFurnitureGesture(
                                                      e.localPosition, size)) {
                                                setState(() {});
                                              } else if (tool == EditorTool.selectWall) {
                                                if (attachmentAt(
                                                        e.localPosition,
                                                        size) !=
                                                    null)
                                                  setState(() {
                                                    tool = EditorTool.drawWall;
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
                                              } else if (tool == EditorTool.drawWall) {
                                                setState(() => beginWallTool(
                                                    e.localPosition, size));
                                              } else if (tool == EditorTool.editWall) {
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
                                                if (stamping) {
                                                  // Held where it is touched;
                                                  // by its middle when the
                                                  // finger lands elsewhere.
                                                  final w = interactionPainter()
                                                      .worldPoint(
                                                          e.localPosition,
                                                          size);
                                                  final r = spatialPreview;
                                                  final inside = r != null &&
                                                      w.x >= r.left &&
                                                      w.x <= r.right &&
                                                      w.y >= r.bottom &&
                                                      w.y <= r.top;
                                                  stampGrab = inside
                                                      ? Offset(w.x - r.left,
                                                          w.y - r.bottom)
                                                      : Offset(
                                                          roomStamp!.w / 2,
                                                          roomStamp!.d / 2);
                                                } else {
                                                  spatialStart = null;
                                                }
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
                                                tool != EditorTool.editWall &&
                                                tool != EditorTool.selectWall &&
                                                tool != EditorTool.drawWall &&
                                                tool != EditorTool.placeOpening &&
                                                tool != EditorTool.resize &&
                                                tool != EditorTool.wall &&
                                                tool != EditorTool.opening &&
                                                tool != EditorTool.grid &&
                                                tool != EditorTool.measure &&
                                                tool != EditorTool.placeFurniture &&
                                                tool != EditorTool.placeUtility)
                                              setState(() => record(
                                                  e.localPosition, size));
                                          },
                                          onPointerMove: (e) {
                                            trackLoupe(e);
                                            if (wallHoldScreen != null &&
                                                (e.position - wallHoldScreen!)
                                                        .distance >
                                                    8) wallHoldTimer?.cancel();
                                            final single = !cancelledStroke &&
                                                pointers.length == 1;
                                            if (single && utilityDown != null) {
                                              setState(() => previewUtility(
                                                  e.localPosition, size));
                                              return;
                                            }
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
                                                tool != EditorTool.editWall &&
                                                tool != EditorTool.selectWall &&
                                                tool != EditorTool.drawWall &&
                                                tool != EditorTool.placeOpening &&
                                                tool != EditorTool.resize &&
                                                tool != EditorTool.wall &&
                                                tool != EditorTool.opening &&
                                                tool != EditorTool.grid &&
                                                tool != EditorTool.measure &&
                                                tool != EditorTool.placeFurniture &&
                                                tool != EditorTool.placeUtility &&
                                                !cancelledStroke &&
                                                pointers.length == 1)
                                              setState(() => record(
                                                  e.localPosition, size));
                                          },
                                          onPointerCancel: (e) {
                                            loupeAt = null;
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
                                            if (loupeAt != null)
                                              setState(() => loupeAt = null);
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
                                            if (single && utilityDown != null) {
                                              final moved = finishUtility();
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              if (!moved)
                                                tapObject(e.localPosition, size);
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
                                                tool == EditorTool.placeFurniture) {
                                              placeFurnitureAt(
                                                  e.localPosition, size);
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (tapped &&
                                                tool == EditorTool.placeUtility) {
                                              placeUtilityAt(
                                                  e.localPosition, size);
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (tapped && tool == EditorTool.measure) {
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
                                            if (tool == EditorTool.drawWall &&
                                                single &&
                                                gesture == 'tap') {
                                              wallToolTap(
                                                  e.localPosition, size);
                                              pointers.remove(e.pointer);
                                              downPoint = null;
                                              return;
                                            }
                                            if (tool == EditorTool.drawWall &&
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
                                            if (tool == EditorTool.drawWall &&
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
                                                  tool = EditorTool.selectWall;
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
                                            if (tool == EditorTool.placeOpening &&
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
                                              // A stamp stays until 放下.
                                              if (stamping) {
                                                setState(() {});
                                              } else {
                                                finishSpatial();
                                              }
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

                                              if (tool == EditorTool.wall)
                                                setState(() {
                                                  tool = EditorTool.browse;
                                                  selectedWall = null;
                                                  placementHint = null;
                                                });
                                              pointers.remove(e.pointer);
                                              lastPoint = null;
                                              downPoint = null;
                                              return;
                                            }
                                            if ((browse ||
                                                    tool == EditorTool.editWall ||
                                                    tool == EditorTool.selectWall ||
                                                    tool == EditorTool.opening ||
                                                    tool == EditorTool.grid) &&
                                                !cancelledStroke &&
                                                pointers.length == 1 &&
                                                downPoint != null &&
                                                (downPoint! - e.localPosition)
                                                        .distance <
                                                    8) {
                                              tapObject(e.localPosition, size);
                                            }
                                            if (tool == EditorTool.stair &&
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
                                              placeStair(AxisRectangle(
                                                  x0: base.axes.v[i0].id,
                                                  x1: base.axes.v[i1].id,
                                                  y0: base.axes.h[j0].id,
                                                  y1: base.axes.h[j1].id));
                                              stroke.clear();
                                            }
                                            if (tool == EditorTool.room &&
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
                                                      ? tr3('没有放上墙：请把${openingNames[details.data]}拖到墙上再松手',
                                                          '${openingNames[details.data]} қабырғаға қойылмады: оны қабырғаға апарып жіберіңіз', 'Не на стене: ${openingNames[details.data]}. Перетащите на стену и отпустите')
                                                      : message);
                                                }
                                              },
                                              // Its own layer: panning the
                                              // sheet moves the cached picture
                                              // instead of redrawing the plan.
                                              builder: (context, candidates, rejected) =>
                                                  RepaintBoundary(child: CustomPaint(
                                                      key: canvasKey,
                                                      size: size,
                                                      painter: FloorPlanPainter(
                                                          displayBase,
                                                          {
                                                            for (final r
                                                                in displayRooms)
                                                              r.id: displayRoomName(r)
                                                          },
                                                          {
                                                            // A room with a use is tinted by it, lightly: the
                                                            // sheet stays a drawing, and uses read at a glance.
                                                            for (final r
                                                                in displayRooms)
                                                              if (r.type !=
                                                                  RoomType
                                                                      .custom)
                                                                r.id: Color.lerp(
                                                                    Tokens.of(
                                                                            context)
                                                                        .room,
                                                                    roomColors[r
                                                                        .type],
                                                                    0.42)!
                                                          },
                                                          viewportInsets:
                                                              canvasInsets,
                                                          openings:
                                                              displayOpenings,
                                                          below: floorIndex > 0 && showBelow
                                                              ? derived.floors[floorIndex - 1].base
                                                              : null,
                                                          belowOpenings: [
                                                            if (floorIndex > 0)
                                                              for (final s in derived.floors[floorIndex - 1].stairs)
                                                                s.opening
                                                          ],
                                                          belowLabel: tr3('楼梯口', 'Баспалдақ ойығы', 'Проём лестницы'),
                                                          stairs: derived
                                                              .floors[
                                                                  floorIndex]
                                                              .stairs,
                                                          northAngleDeg: history
                                                              .present
                                                              .footprint
                                                              .northAngleDeg,
                                                          focus: focus,
                                                          editableWall: (tool == EditorTool.editWall || tool == EditorTool.drawWall) && editStart != null && editEnd != null ? PlanRect((editPreviewStart ?? editStart)!.dx, (editPreviewStart ?? editStart)!.dy, (editPreviewEnd ?? editEnd)!.dx, (editPreviewEnd ?? editEnd)!.dy) : null,
                                                          wallSeed: tool == EditorTool.drawWall ? drawingOrigin : null,
                                                          wallAttachments: (tool == EditorTool.drawWall || tool == EditorTool.selectWall) && drawingEnd == null && editPreviewStart == null ? visibleWallAttachments(size) : const [],
                                                          handleScale: canvasZoom,
                                                          selectedDimension: editingDimension,
                                                          draftLabel: wallDraftLabel,
                                                          draftEnd: tool == EditorTool.drawWall && drawingStrokeActive && drawingEnd != null
                                                              ? drawingEnd
                                                              : wallGrip == 'start'
                                                                  ? editPreviewStart
                                                                  : wallGrip == 'end'
                                                                      ? editPreviewEnd
                                                                      : null,
                                                          draftConnected: drawConnected,
                                                          guides: [
                                                            if (alignGuide case final g?
                                                                when (tool == EditorTool.drawWall && drawingStrokeActive && drawingEnd != null) ||
                                                                    wallGrip == 'start' ||
                                                                    wallGrip == 'end')
                                                              g
                                                          ],
                                                          coach: coachArrow(size),
                                                          draft: tool == EditorTool.drawWall && drawingEnd != null && drawingOrigin != null ? PlanRect(math.min(drawingOrigin!.dx, drawingEnd!.dx), math.min(drawingOrigin!.dy, drawingEnd!.dy), math.max(drawingOrigin!.dx, drawingEnd!.dx), math.max(drawingOrigin!.dy, drawingEnd!.dy)) : spatialPreview,
                                                          showGridDimensions: tool == EditorTool.grid,
                                                          draftInvalid: spatialError != null,
                                                          draftIsLine: tool == EditorTool.split || tool == EditorTool.drawWall,
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
                                                          resizeHandles: tool == EditorTool.resize,
                                                          wallHandle: tool == EditorTool.wall && selectedWall != null ? (selectedWall!.axis.dir == AxisDir.V ? PlanRect((dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.start.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.end.pos.toDouble()) : PlanRect(selectedWall!.start.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.end.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()))) : null,
                                                          tokens: Tokens.of(context),
                                                          bearingMin: history.present.extras.foundation.bearingMin,
                                                          furniture: [for (final f in history.present.extras.furniture) if (f.floorId == floor.id && f.id != furnitureDraft?.id) f],
                                                          furnitureDraft: furnitureDraft,
                                                          utilities: showUtilities ? [for (final u in floorUtilities) u.id == utilityDraft?.id ? utilityDraft! : u] : const [],
                                                          selectedUtility: selectedUtilityId,
                                                          selectedFurniture: selectedFurnitureId,
                                                          selectedRoom: selectedRoomId,
                                                          showFurniture: showFurniture,
                                                          showDimensions: showDimensions,
                                                          foundation: showFoundation && floorIndex == 0 ? foundationTakeoff(history.present, derived) : null,
                                                          sleeves: history.present.extras.sleeves,
                                                          highlights: highlights,
                                                          pulse: pulse,
                                                          measure: measurePoints,
                                                          preview: List.of(stroke))))))));
                            }));
}
