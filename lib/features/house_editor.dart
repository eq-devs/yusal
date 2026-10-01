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
import '../core/geometry/derived_house.dart';
import '../core/checks/check_engine.dart';
import '../render3d/house_viewer.dart';
import '../render2d/floor_plan_painter.dart';
import '../render2d/project_preview.dart';
import '../storage/project_store.dart';
import '../storage/house_import.dart';
import 'footprint_sketch.dart';
import 'wall_length_dialog.dart';
import 'wall_attachment_points.dart';

class HouseHome extends StatefulWidget {
  const HouseHome({super.key});
  @override
  State<HouseHome> createState() => _HouseHomeState();
}

class _HouseHomeState extends State<HouseHome> {
  final store = ProjectStore(previewRenderer: renderProjectPreview);
  static const importChannel = MethodChannel('yusal/house_import');
  List<ProjectEntry> projects = [];
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
    if (!kIsWeb) {
      importChannel.setMethodCallHandler((call) async {
        if (call.method == 'importFile') await receiveFile(call.arguments);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final pending =
              await importChannel.invokeListMethod<Object?>('getPending');
          for (final file in pending ?? <Object?>[]) {
            await receiveFile(file);
          }
        } on MissingPluginException {
          /* Widget tests and unsupported desktop platforms. */
        }
      });
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) importChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> receiveFile(Object? payload) async {
    if (!mounted || payload is! Map) return;
    if (payload['bytes'] is! Uint8List) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(payload['error'] == 'FILE_TOO_LARGE'
              ? '文件超过 10 MiB，无法打开'
              : '无法读取设计文件')));
      return;
    }
    final loaded = loadHouse(payload['bytes'] as Uint8List);
    if (!loaded.isSuccess) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这个文件的内容有误，无法打开')));
      return;
    }
    try {
      final id = await store.createProject(loaded.document!);
      if (mounted) await open(ProjectEntry(id, loaded.document!));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法保存导入的设计')));
    }
  }

  Future<void> refresh() async {
    try {
      final list = await store.listProjects();
      if (mounted)
        setState(() {
          projects = list;
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法读取设计，请稍后重试');
    }
  }

  Future<void> open(ProjectEntry entry) async {
    try {
      final document = await store.openProject(entry.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => HouseEditor(
              entry: ProjectEntry(entry.id, document), store: store)));
      await refresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('这个设计无法打开，请检查文件')));
    }
  }

  Future<void> createFromTemplate() async {
    final key = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final entry
                  in houseTemplates.entries.where((e) => e.key != 'blank'))
                ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(context, entry.key))
            ])));
    if (key == null) return;
    try {
      final doc = createTemplate(key, DateTime.now().toUtc().toIso8601String(),
          () => const Uuid().v4());
      final id = await store.createProject(doc);
      if (mounted) await open(ProjectEntry(id, doc));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法创建，请检查存储空间')));
    }
  }

  Future<void> create() async {
    final name = TextEditingController(text: '我的房屋'),
        width = TextEditingController(text: '12.00'),
        depth = TextEditingController(text: '10.00');
    const columns = 1, rows = 1;
    String? validation;
    var sketchRequested = false;
    var doc = await showDialog<HouseDocument>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialog) => AlertDialog(
                    title: const Text('新建设计'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: '设计名称')),
                      TextField(
                          controller: width,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: '宽（米，左右方向）')),
                      TextField(
                          controller: depth,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: '长（米，上下方向）')),
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('先确定外形，进入画布后直接拖动划分房间。')),
                      if (validation != null)
                        Text(validation!,
                            style: const TextStyle(color: Colors.red))
                    ])),
                    actions: [
                      TextButton.icon(
                          onPressed: () {
                            sketchRequested = true;
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.crop_square),
                          label: const Text('直接拖出外形')),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () {
                            final w = double.tryParse(width.text),
                                d = double.tryParse(depth.text);
                            if (w == null ||
                                d == null ||
                                !w.isFinite ||
                                !d.isFinite ||
                                w < 3 ||
                                w > 100 ||
                                d < 3 ||
                                d > 100 ||
                                w * 1000 / columns < 300 ||
                                d * 1000 / rows < 300) {
                              setDialog(() =>
                                  validation = '尺寸需在 3–100 米之间，每格至少 0.30 米');
                              return;
                            }
                            Navigator.pop(
                                context,
                                createHouse(
                                    name: name.text,
                                    width: (w * 1000).round(),
                                    depth: (d * 1000).round(),
                                    columns: columns,
                                    rows: rows,
                                    initialRoom: true,
                                    timestamp: DateTime.now()
                                        .toUtc()
                                        .toIso8601String(),
                                    newId: () => const Uuid().v4()));
                          },
                          child: const Text('开始设计'))
                    ])));
    // The controllers stay alive until the dialog exit animation completes.
    if (sketchRequested && mounted) {
      final dimensions = await Navigator.of(context).push<FootprintDimensions>(
          MaterialPageRoute(builder: (_) => const FootprintSketch()));
      if (dimensions == null) return;
      doc = createHouse(
          name: name.text,
          width: dimensions.width,
          depth: dimensions.depth,
          columns: 1,
          rows: 1,
          initialRoom: true,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          newId: () => const Uuid().v4());
    }
    if (doc == null) return;
    try {
      final id = await store.createProject(doc);
      if (mounted) await open(ProjectEntry(id, doc));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法创建，请检查存储空间')));
    }
  }

  Future<void> import() async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(
            label: '房屋设计',
            extensions: ['house'],
            uniformTypeIdentifiers: ['public.data'])
      ]);
      if (file == null) return;
      if (await file.length() > maxHouseBytes) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('文件超过 10 MiB，无法打开')));
        return;
      }
      final loaded = await loadHouseStream(file.openRead(0, maxHouseBytes + 1),
          length: await file.length());
      if (!loaded.isSuccess) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('这个文件的内容有误，无法打开')));
        return;
      }
      final id = await store.createProject(loaded.document!);
      if (mounted) await open(ProjectEntry(id, loaded.document!));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法导入设计')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('自建房设计工具'), actions: [
        IconButton(
            onPressed: import,
            tooltip: '导入 .house',
            icon: const Icon(Icons.file_open_outlined))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                const Text('从长宽开始，设计你的家',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('定长宽 · 拖动分房 · 放门窗'),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: create,
                    icon: const Icon(Icons.add),
                    label: const Padding(
                        padding: EdgeInsets.all(12), child: Text('新建设计'))),
                TextButton.icon(
                    onPressed: createFromTemplate,
                    icon: const Icon(Icons.auto_awesome_mosaic_outlined),
                    label: const Text('也可以从示例开始')),
                const SizedBox(height: 32),
                const Text('最近设计',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (error != null) Text(error!),
                if (projects.isEmpty)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text('还没有设计，创建你的第一栋房屋。')),
                for (final entry in store.corruptProjects.entries)
                  Card(
                      child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: Text(entry.key),
                          subtitle: Text(entry.value),
                          trailing: IconButton(
                              tooltip: '删除损坏的设计',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                            title: const Text('删除无法打开的设计？'),
                                            content: Text(entry.key),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, false),
                                                  child: const Text('取消')),
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, true),
                                                  child: const Text('删除'))
                                            ]));
                                if (yes == true) {
                                  await store.deleteProject(entry.key);
                                  await refresh();
                                }
                              }))),
                for (final entry in projects)
                  Card(
                      child: ListTile(
                          onTap: () => open(entry),
                          leading: entry.preview == null
                              ? const Icon(Icons.other_houses_outlined)
                              : Image.memory(Uint8List.fromList(entry.preview!),
                                  width: 56, height: 56, fit: BoxFit.contain),
                          title: Text(entry.document.meta.name),
                          subtitle: Text(
                              '${entry.document.footprint.width / 1000} × ${entry.document.footprint.depth / 1000} 米 · ${entry.document.floors.length} 层'),
                          trailing: IconButton(
                              tooltip: '删除设计',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                            title: const Text('删除这个设计？'),
                                            content:
                                                Text(entry.document.meta.name),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, false),
                                                  child: const Text('取消')),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, true),
                                                  child: const Text('删除'))
                                            ]));
                                if (yes == true) {
                                  await store.deleteProject(entry.id);
                                  await refresh();
                                }
                              })))
              ]))));
}

class HouseEditor extends StatefulWidget {
  const HouseEditor(
      {super.key,
      required this.entry,
      required this.store,
      this.initialView3d = false,
      this.initialTool});
  final bool initialView3d;
  final String? initialTool;
  final ProjectEntry entry;
  final ProjectStore store;
  @override
  State<HouseEditor> createState() => _HouseEditorState();
}

class _HouseEditorState extends State<HouseEditor> with WidgetsBindingObserver {
  late final DesignHistory history;
  late FloorBase base;
  late DerivedHouse derived;
  bool view3d = false;
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
  EdgeInsets get canvasInsets {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final bottom = MediaQuery.textScalerOf(context).scale(12) > 16
        ? (wide ? 150.0 : 210.0)
        : wide
            ? 112.0
            : MediaQuery.sizeOf(context).width < 350
                ? 180.0
                : 138.0;
    return EdgeInsets.fromLTRB(12, 112, 68, bottom + 36);
  }

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
      placementHint = '拖到墙上，门窗会自动贴合';
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
        extractDesignState(history.present),
        DesignCommand('AddOpening', arguments),
        CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
    if (result is Applied) {
      openingDrop = arguments;
      derived =
          deriveHouse(composeDocument(history.present.meta, result.newState));
      base = derived.floors[floorIndex].base;
      placementHint = '已贴合墙面，松手放置';
    } else {
      placementHint = result is Rejected ? result.message : '此处无法放置';
    }
  }

  String toolLabel(String label) => switch (label) {
        '拉线分房' => '分房',
        '拖动划房' => '框房',
        '拖入门' => '门',
        '拖入窗' => '窗',
        '更多工具' => '更多',
        '墙体调整' => '改墙',
        '墙设置' => '设置',
        _ => label
      };

  Widget basicTool(
          IconData icon, String label, bool selected, VoidCallback onTap) =>
      Semantics(
          button: true,
          selected: selected,
          label: label,
          child: Tooltip(
              message: label,
              child: Material(
                  color: selected
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        cancelDrag();
                        spatialDocument = null;
                        spatialBase = null;
                        spatialError = null;
                        spatialStart = null;
                        spatialEnd = null;
                        spatialPreview = null;
                        placementHint = null;
                        onTap();
                        if (mounted) setState(() {});
                      },
                      child: SizedBox(
                          width: math.max(
                              48,
                              MediaQuery.textScalerOf(context).scale(12) *
                                      toolLabel(label).length +
                                  4),
                          height: math.max(58,
                              MediaQuery.textScalerOf(context).scale(12) + 44),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon, size: 24),
                                const SizedBox(height: 4),
                                Text(toolLabel(label),
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 12))
                              ]))))));

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
                              const Text('房屋长宽',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600)),
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text('外形尺寸用于全部楼层。内部房间位置保持不变。')),
                              TextField(
                                  controller: width,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: '宽（米，左右方向）')),
                              TextField(
                                  controller: depth,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: '长（米，上下方向）')),
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
                                      update(() => error = '长宽需在 3–100 米之间');
                                      return;
                                    }
                                    final args = <String, dynamic>{
                                      'width': (w * 1000).round(),
                                      'depth': (d * 1000).round()
                                    };
                                    final result = executeCommand(
                                        extractDesignState(history.present),
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
                                  child: const Text('应用尺寸')),
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
                                  label: const Text('拖动外边框调整')),
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
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('更多工具',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600))),
                  for (final entry in {
                    'fit': '恢复画布视角',
                    'grid': '网格',
                    'opening': '门窗',
                    'stair': '楼梯',
                    for (final type in RoomType.values)
                      type.name: roomNames[type]!,
                    'erase': '擦除'
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

  Widget openingTool(OpeningKind kind, IconData icon, String label) {
    final button = basicTool(
        icon, label, tool == 'placeOpening' && placingOpening == kind, () {
      placingOpening = kind;
      browse = false;
      tool = 'placeOpening';
      placementHint = '点一下墙面放置，也可以从工具栏直接拖入';
    });
    return Draggable<OpeningKind>(
        data: kind,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
            color: Colors.transparent,
            child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 32))),
        onDragEnd: (_) => setState(() {
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
        extractDesignState(history.present),
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
          count > floor.rooms.length + 1 ? '分房后会得到 $count 个独立空间，松手完成' : null;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
  @override
  void initState() {
    super.initState();
    canvasTransform.addListener(onCanvasTransformChanged);
    view3d = widget.initialView3d;
    if (view3d) toolCategory = 2;
    history = DesignHistory(widget.entry.document);
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
        if (mounted) showWallContext(wall, point);
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
    wallHoldTimer?.cancel();
    canvasTransform.removeListener(onCanvasTransformChanged);
    canvasTransform.dispose();
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
    saving = true;
    try {
      await widget.store.saveProject(widget.entry.id, doc);
      if (mounted)
        setState(() {
          dirty = history.present != doc;
          status = dirty ? '未保存' : '已保存';
        });
    } catch (_) {
      if (mounted) setState(() => status = '保存失败，请检查存储空间');
    } finally {
      saving = false;
      if (dirty && history.present != doc)
        timer = Timer(const Duration(milliseconds: 1500), save);
    }
  }

  void changed() {
    focus = null;
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
      if ((point - painter.point(width, depth / 2, size)).distance <= 24) {
        draggingAxis = base.axes.v.last;
      } else if ((point - painter.point(width / 2, depth, size)).distance <=
          24) {
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
      draggingOpening = derived.floors[floorIndex].openings.where((p) {
        final along = p.axis.dir == AxisDir.H ? x : y,
            cross = p.axis.dir == AxisDir.H ? y : x;
        return along >= p.start - tolerance &&
            along <= p.end + tolerance &&
            (cross - p.axis.pos).abs() <= tolerance;
      }).firstOrNull;
    }
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
        placementHint = '拖到另一面墙，门窗会自动贴合';
        return;
      }
      final along = wall.axis.dir == AxisDir.H ? x : y;
      final available = wall.end.pos - wall.start.pos - opening.opening.width;
      if (available < 0) {
        placementHint = '这段墙放不下这个门窗';
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
        extractDesignState(history.present),
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
    spatialDocument = null;
    spatialBase = null;
    draggingAxis = null;
    draggingOpening = null;
    dragArguments = null;
    dragKind = null;
    dragged = false;
    dragAttempted = false;
    dragValid = false;
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
      final filename = '${cleanedName.isEmpty ? '房屋设计' : cleanedName}.house';
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法导出这个设计')));
    }
  }

  void action(String kind, Map<String, dynamic> args) {
    final result = executeCommand(
        extractDesignState(history.present),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('确定'))
                ]));
  }

  Future<int?> length(String label, int value) async {
    final result =
        await ask('$label（米）', (value / 1000).toStringAsFixed(2), number: true);
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
                'AddFloor': '新增空层',
                'CopyFloor': '复制本层',
                'RenameFloor': '楼层名称',
                'SetFloorHeight': '层高',
                'DeleteFloor': '删除本层'
              }.entries)
                ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(context, entry.key))
            ])));
    if (choice == null) return;
    if (choice == 'SetFloorHeight') {
      final value = await length('层高', floor.height);
      if (value != null) action(choice, {'floorId': floor.id, 'value': value});
    } else if (choice == 'RenameFloor') {
      final value = await ask('楼层名称', floor.name);
      if (value != null) action(choice, {'floorId': floor.id, 'value': value});
    } else {
      if (choice == 'DeleteFloor') {
        final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('删除本层及其全部内容？'),
                    content: const Text('本层房间和门窗将删除。删除顶层时，下层通向本层的楼梯也会删除。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('删除'))
                    ]));
        if (yes != true) return;
      }
      action(choice, {
        'floorId': floor.id,
        if (choice == 'DeleteFloor') 'deleteStairs': true
      });
    }
  }

  Future<void> settings() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final e in {
                'width': '房屋宽度',
                'depth': '房屋进深',
                'north': '正北方向',
                'flat': '平屋顶',
                'gable': '双坡屋顶',
                'grid': '编辑网格',
                'defaults': '默认尺寸'
              }.entries)
                ListTile(
                    title: Text(e.value),
                    onTap: () => Navigator.pop(context, e.key))
            ])));
    if (choice == 'width' || choice == 'depth') {
      final value = await length(
          choice == 'width' ? '房屋宽度' : '房屋进深',
          choice == 'width'
              ? history.present.footprint.width
              : history.present.footprint.depth);
      if (value != null) action('SetFootprintSize', {choice!: value});
    }
    if (choice == 'flat') {
      final height =
          await length('女儿墙高度', history.present.roof.parapetHeight ?? 900);
      if (height != null)
        action('SetRoof', {
          'roof': {'type': 'flat', 'parapetHeight': height}
        });
    }
    if (choice == 'gable') {
      final pitchText = await ask(
          '屋顶坡度（5–60°）', '${history.present.roof.pitchDeg ?? 30}',
          number: true);
      if (pitchText == null) return;
      final pitch = int.tryParse(pitchText);
      if (pitch == null) return;
      final overhang =
          await length('屋檐伸出', history.present.roof.overhang ?? 500);
      if (overhang == null) return;
      final direction = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                ListTile(
                    title: const Text('屋脊沿进深方向'),
                    onTap: () => Navigator.pop(context, 'V')),
                ListTile(
                    title: const Text('屋脊沿宽度方向'),
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
        'outerWallThickness': '外墙厚度',
        'innerWallThickness': '内墙厚度',
        'slabThickness': '楼板厚度',
        'stairRiserMax': '楼梯最大步高',
        'stairTread': '楼梯踏步进深',
        'stairWidthMin': '楼梯最小宽度',
        'floorHeight': '默认层高',
        'doorWidth': '默认门宽',
        'doorHeight': '默认门高',
        'windowWidth': '默认窗宽',
        'windowHeight': '默认窗高',
        'windowSill': '默认窗台高度'
      };
      final field = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final entry in labels.entries)
                  ListTile(
                      title: Text(entry.value),
                      subtitle:
                          Text('${(defaults[entry.key] as int) / 1000} 米'),
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
                      title: Text('正北指向 $angle°'),
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
                      title: const Text('新增竖向分隔线'),
                      onTap: () => Navigator.pop(context, AxisDir.V)),
                  ListTile(
                      title: const Text('新增横向分隔线'),
                      onTap: () => Navigator.pop(context, AxisDir.H)),
                  for (final axis
                      in base.axes.all.where((a) => a.kind != 'boundary'))
                    ListTile(
                        title: Text(
                            '${axis.dir == AxisDir.V ? '竖' : '横'}线 · ${(axis.pos / 1000).toStringAsFixed(2)} 米'),
                        onTap: () => Navigator.pop(context, axis))
                ]))));
    if (selected is AxisDir) {
      final value = await length(
          '新分隔线位置',
          selected == AxisDir.V
              ? history.present.footprint.width ~/ 2
              : history.present.footprint.depth ~/ 2);
      if (value != null) {
        final scope = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  ListTile(
                      title: const Text('所有楼层'),
                      onTap: () => Navigator.pop(context, 'global')),
                  ListTile(
                      title: const Text('仅本层'),
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
              title: const Text('修改位置'),
              onTap: () => Navigator.pop(context, 'move')),
          if (selected.kind == 'floor')
            ListTile(
                title: const Text('同步到所有楼层'),
                onTap: () => Navigator.pop(context, 'promote')),
          ListTile(
              title: const Text('删除分隔线'),
              onTap: () => Navigator.pop(context, 'delete')),
        ])),
      );
      if (operation == 'move') {
        final value = await length('分隔线位置', selected.pos);
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
                    title: const Text('删除分隔线'),
                    content: Text(
                        '${result.message}\n${result.hasHosted ? '这条线上的门窗和墙设置将删除。\n' : ''}${result.hasStairs ? '受影响的楼梯将删除。\n' : ''}请选择合并后保留的房间。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      for (final entry in {
                        'mergeRooms': '合并房间',
                        'keepLowSide': '保留左 / 下侧',
                        'keepHighSide': '保留右 / 上侧'
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
            if (history.commit(result.document!)) changed();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.message ?? '无法删除分隔线')));
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

  void checks() {
    final results = runChecks(history.present, derived);
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.7,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('设计检查',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (results.isEmpty) const ListTile(title: Text('没有需要处理的提示')),
                  for (final result in results)
                    ListTile(
                        leading: Icon(
                            result.level == 'important'
                                ? Icons.error_outline
                                : Icons.lightbulb_outline,
                            color: result.level == 'important'
                                ? Colors.red
                                : Colors.orange),
                        title: Text(result.message),
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            final index = history.present.floors
                                .indexWhere((f) => f.id == result.floorId);
                            if (index >= 0) floorIndex = index;
                            view3d = false;
                            derive();
                            focus = result.focus;
                          });
                        }),
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('这些阈值属于设计建议，不代表当地建筑法规或结构安全的合规结论。',
                          style: TextStyle(fontSize: 12)))
                ]))));
  }

  Future<void> tapObject(Offset point, Size size) async {
    final painter = interactionPainter(), scale = painter.scale(size);
    final x = painter.worldPoint(point, size).x,
        y = painter.worldPoint(point, size).y,
        tolerance = 12 / scale;
    final placements = derived.floors[floorIndex].openings;
    final opening = placements.where((p) {
      final along = p.axis.dir == AxisDir.H ? x : y,
          cross = p.axis.dir == AxisDir.H ? y : x;
      return along >= p.start - tolerance &&
          along <= p.end + tolerance &&
          (cross - p.axis.pos).abs() < tolerance;
    }).firstOrNull;
    if (opening != null && tool != 'selectWall') {
      openingOptions(opening.opening);
      return;
    }
    final wall = base.wallSegments.where((w) {
      final along = w.axis.dir == AxisDir.H ? x : y,
          cross = w.axis.dir == AxisDir.H ? y : x;
      return along >= w.start.pos - tolerance &&
          along <= w.end.pos + tolerance &&
          (cross - w.axis.pos).abs() < tolerance;
    }).firstOrNull;
    if (wall != null) {
      if (wall.axis.kind != 'boundary') {
        selectWallForEdit(wall, x, y);
        return;
      }
      final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final entry in {
                  'door': '门',
                  'window': '窗',
                  'sliding': '推拉门',
                  if (wall.axis.kind != 'boundary') 'move': '拖动这段墙',
                  if (wall.axis.kind != 'boundary') 'position': '精确调整这段墙',
                  'open': '开放（无墙）',
                  'thickness': '调整墙厚',
                  'default': '恢复默认墙'
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
            wall.axis.dir == AxisDir.V ? '距左侧外墙' : '距下侧外墙', wall.axis.pos);
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
          thickness = await length('墙厚', wall.thickness.round());
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
    final i = base.axes.v.indexWhere((a) => a.pos > x) - 1,
        j = base.axes.h.indexWhere((a) => a.pos > y) - 1;
    final id = base.owners[Cell(i, j)];
    final room = floor.rooms.where((r) => r.id == id).firstOrNull;
    if (room != null) {
      final geometry = base.roomGeometry.firstWhere((g) => g.id == room.id);
      final clear =
          geometry.clearRects.length == 1 ? geometry.clearRects.single : null;
      final details = clear == null
          ? '净面积 ${(geometry.clearArea / 1000000).toStringAsFixed(1)} ㎡'
          : '净宽 ${((clear.right - clear.left) / 1000).toStringAsFixed(2)} 米 · 净长 ${((clear.top - clear.bottom) / 1000).toStringAsFixed(2)} 米 · ${(geometry.clearArea / 1000000).toStringAsFixed(1)} ㎡';
      final choice = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (context) => SafeArea(
              child: SizedBox(
                  height:
                      math.min(420, MediaQuery.sizeOf(context).height * 0.75),
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Text(room.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(details)),
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('这个房间用来做什么？')),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final type in RoomType.values)
                        ChoiceChip(
                            label: Text(roomNames[type]!),
                            selected: room.type == type,
                            onSelected: (_) =>
                                Navigator.pop(context, type.name))
                    ]),
                    const Divider(height: 24),
                    ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('修改名称'),
                        onTap: () => Navigator.pop(context, 'rename')),
                    ListTile(
                        leading: const Icon(Icons.join_inner),
                        title: const Text('与相邻房间合并'),
                        onTap: () => Navigator.pop(context, 'merge')),
                    ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('删除房间'),
                        onTap: () => Navigator.pop(context, 'delete')),
                  ]))));
      if (choice == 'rename') {
        final value = await ask('房间名称', room.name);
        if (value != null)
          action('RenameRoom', {'roomId': room.id, 'value': value});
      } else if (choice == 'merge') {
        final adjacent = floor.rooms
            .where((r) =>
                r.id != room.id &&
                isConnected({
                  ...regionCells(base.axes, room.regions).cells,
                  ...regionCells(base.axes, r.regions).cells
                }))
            .toList();
        if (adjacent.isEmpty) {
          if (mounted)
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('没有可以合并的相邻房间')));
          return;
        }
        final target = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  for (final other in adjacent)
                    ListTile(
                        title: Text(other.name),
                        onTap: () => Navigator.pop(context, other.id)),
                ])));
        if (target != null) {
          final arguments = <String, dynamic>{
            'roomIdA': room.id,
            'roomIdB': target
          };
          final preview = executeCommand(
              extractDesignState(history.present),
              DesignCommand('MergeRooms', arguments),
              CommandContext(
                  newId: () => const Uuid().v4(), now: () => 'unused'));
          if (preview is NeedsResolution && mounted) {
            final proceed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                        title: const Text('合并这两个房间？'),
                        content: Text(preview.conflict.message),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('合并并移除这些门窗'))
                        ]));
            if (proceed != true) return;
            arguments['deleteHostedObjects'] = true;
          }
          action('MergeRooms', arguments);
        }
      } else if (choice == 'delete') {
        final updated = paintCells(
            history.present,
            floor.id,
            regionCells(base.axes, room.regions).cells.toList(),
            room.type,
            () => const Uuid().v4(),
            erase: true);
        setState(() {
          if (history.commit(updated)) changed();
        });
      } else if (choice != null) {
        action('SetRoomType',
            {'roomId': room.id, 'value': RoomType.values.byName(choice)});
      }
      return;
    }
    final stair = floor.stairs.where((s) => s.id == id).firstOrNull;
    if (stair != null) {
      final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final e in {
                  'straight': '直梯',
                  'L': 'L 型楼梯',
                  'U': 'U 型楼梯',
                  'turn': '切换转向',
                  'start': '切换起步边',
                  'delete': '删除楼梯'
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

  Future<void> openingOptions(Opening opening) async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final e in {
                'width': '宽度',
                'height': '高度',
                'sill': '窗台高度',
                'center': '沿墙居中',
                'offset': '距墙起点',
                'kind': '门窗类型',
                if (opening is DoorOpening) 'hinge': '切换铰链位置',
                if (opening is DoorOpening) 'entrance': '设为主入口',
                if (opening is DoorOpening) 'flip': '切换开向',
                'delete': '删除门窗'
              }.entries)
                ListTile(
                    title: Text(e.value),
                    onTap: () => Navigator.pop(context, e.key))
            ])));
    if (choice == null) return;
    if (['width', 'height', 'sill'].contains(choice)) {
      final value = await length(
          choice == 'width'
              ? '宽度'
              : choice == 'height'
                  ? '高度'
                  : '窗台高度',
          choice == 'width'
              ? opening.width
              : choice == 'height'
                  ? opening.height
                  : opening.sill);
      if (value != null)
        action('ResizeOpening', {'openingId': opening.id, choice: value});
    }
    if (choice == 'center')
      action('MoveOpening', {
        'openingId': opening.id,
        'position': {'type': 'center'}
      });
    if (choice == 'offset') {
      final value = await length('距墙起点', 200);
      if (value != null)
        action('MoveOpening', {
          'openingId': opening.id,
          'position': {'type': 'fromStart', 'd': value}
        });
    }
    if (choice == 'kind') {
      final kind = await showModalBottomSheet<OpeningKind>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final entry in {
                  OpeningKind.door: '门',
                  OpeningKind.window: '窗',
                  OpeningKind.sliding: '推拉门'
                }.entries)
                  ListTile(
                      title: Text(entry.value),
                      onTap: () => Navigator.pop(context, entry.key)),
              ])));
      if (kind != null)
        action('SetOpeningKind', {'openingId': opening.id, 'kind': kind});
    }
    if (choice == 'hinge' && opening is DoorOpening)
      action('FlipDoor', {
        'openingId': opening.id,
        'hinge': opening.hinge == Hinge.start ? 'end' : 'start'
      });
    if (choice == 'entrance')
      action('SetMainEntrance', {'openingId': opening.id});
    if (choice == 'flip' && opening is DoorOpening)
      action('FlipDoor', {
        'openingId': opening.id,
        'opensTo': opening.opensTo == OpeningSide.positiveSide
            ? 'negativeSide'
            : 'positiveSide'
      });
    if (choice == 'delete') action('DeleteOpening', {'openingId': opening.id});
  }

  Offset? drawingOrigin, drawingEnd;
  int toolCategory = 0;
  int viewResetToken = 0;
  Duration get motionDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 200);

  Widget floatingSurface(Widget child) => Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: child);

  void chooseCategory(int value) {
    setState(() {
      cancelDrag();
      spatialStart = null;
      spatialEnd = null;
      spatialPreview = null;
      toolCategory = value;
      if (value != 2) view3d = false;
      tool = 'browse';
      browse = true;
      drawingOrigin = null;
      drawingEnd = null;
      placementHint = null;
    });
  }

  String? selectedDrawnId;
  BoundaryAnchor? selectedDrawnAnchor;
  Offset? editStart, editEnd, editPreviewStart, editPreviewEnd, editDown;
  String? wallGrip;

  void selectWallForEdit(WallSegment wall, double x, double y) {
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
      toolCategory = 1;
      tool = 'editWall';
      browse = false;
      placementHint = '拖两端改长度 · 拖中间移动墙';
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
    if (editStart == null || editEnd == null) return;
    final painter = interactionPainter();
    final a = painter.point(editStart!.dx, editStart!.dy, size),
        b = painter.point(editEnd!.dx, editEnd!.dy, size);
    final handles = {'middle': (a + b) / 2, 'start': a, 'end': b}
        .entries
        .toList()
      ..sort((x, y) =>
          (local - x.value).distance.compareTo((local - y.value).distance));
    wallGrip = (local - handles.first.value).distance * canvasZoom <= 24
        ? handles.first.key
        : null;
    editDown = wallPoint(local, size);
    editPreviewStart = null;
    editPreviewEnd = null;
    spatialError = null;
  }

  void previewWallEdit(Offset local, Size size) {
    if (wallGrip == null ||
        editDown == null ||
        editStart == null ||
        editEnd == null) return;
    final exclude = <String>{
      if (selectedDrawnAnchor != null) selectedDrawnAnchor!.axisId,
      if (wallGrip == 'start' && selectedDrawnAnchor != null)
        selectedDrawnAnchor!.startAxisId,
      if (wallGrip == 'end' && selectedDrawnAnchor != null)
        selectedDrawnAnchor!.endAxisId
    };
    final delta = wallPoint(local, size, excludeAxes: exclude) - editDown!;
    final vertical = editStart!.dx == editEnd!.dx;
    editPreviewStart = wallGrip == 'middle'
        ? editStart! + delta
        : wallGrip == 'start'
            ? editStart! +
                (vertical ? Offset(0, delta.dy) : Offset(delta.dx, 0))
            : editStart;
    editPreviewEnd = wallGrip == 'middle'
        ? editEnd! + delta
        : wallGrip == 'end'
            ? editEnd! + (vertical ? Offset(0, delta.dy) : Offset(delta.dx, 0))
            : editEnd;
    final result = executeCommand(
        extractDesignState(history.present),
        DesignCommand('UpdateDrawnWall',
            wallEditArguments(editPreviewStart!, editPreviewEnd!)),
        CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
    if (result is Applied) {
      spatialDocument = composeDocument(history.present.meta, result.newState);
      spatialBase = deriveFloorBase(spatialDocument!, floor.id);
      spatialError = null;
      placementHint = '松手完成，支持撤销';
    } else {
      spatialDocument = null;
      spatialBase = null;
      spatialError = result is Rejected ? result.message : '无法移动这段墙';
      placementHint = spatialError;
    }
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
      selectedDrawnId = null;
      selectedDrawnAnchor = null;
      tool = 'browse';
      browse = true;
      return;
    }
    selectedDrawnId = solid.id;
    selectedDrawnAnchor = solid.anchor;
    editStart = start;
    editEnd = end;
  }

  void finishWallEdit() {
    final start = editPreviewStart, end = editPreviewEnd, error = spatialError;
    final args = start != null && end != null && error == null
        ? wallEditArguments(start, end)
        : null;
    cancelDrag();
    spatialError = null;
    if (args != null) {
      final before = history.present;
      action('UpdateDrawnWall', args);
      if (history.present != before) refreshWallSelection(start!, end!);
    }
    if (error != null)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    placementHint = '拖两端改长度 · 拖中间移动墙';
    setState(() {});
  }

  Future<void> preciseWallLength() async {
    if (editStart == null || editEnd == null) return;
    final value = await length('墙长', (editEnd! - editStart!).distance.round());
    if (value == null) return;
    final vertical = editStart!.dx == editEnd!.dx;
    final end = vertical
        ? Offset(editStart!.dx, editStart!.dy + value)
        : Offset(editStart!.dx + value, editStart!.dy);
    final before = history.present;
    action('UpdateDrawnWall', wallEditArguments(editStart!, end));
    if (history.present != before)
      setState(() => refreshWallSelection(editStart!, end));
  }

  Future<void> preciseWallPosition() async {
    if (editStart == null || editEnd == null) return;
    final vertical = editStart!.dx == editEnd!.dx;
    final value = await length(vertical ? '距左侧的位置' : '距下侧的位置',
        (vertical ? editStart!.dx : editStart!.dy).round());
    if (value == null) return;
    final start = vertical
        ? Offset(value.toDouble(), editStart!.dy)
        : Offset(editStart!.dx, value.toDouble());
    final end = vertical
        ? Offset(value.toDouble(), editEnd!.dy)
        : Offset(editEnd!.dx, value.toDouble());
    final before = history.present;
    action('UpdateDrawnWall', wallEditArguments(start, end));
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
                      title: const Text('调整墙厚'),
                      onTap: () => Navigator.pop(context, 'thickness')),
                  ListTile(
                      title: const Text('恢复默认墙厚'),
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
      value = await length('墙厚', thickness);
      if (value == null) return;
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
                  title: const Text('删除墙及其门窗？'),
                  content: Text('这段墙上的 $hosted 个门窗也会删除，可通过撤销恢复。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除'))
                  ]));
      if (yes != true) return;
    }
    final args = wallEditArguments(editStart!, editEnd!)
      ..['deleteHostedObjects'] = true;
    final before = history.present;
    action('DeleteDrawnWall', args);
    if (history.present != before)
      setState(() {
        cancelDrag();
        tool = 'browse';
        browse = true;
        selectedWall = null;
        selectedDrawnId = null;
        selectedDrawnAnchor = null;
        editStart = null;
        editEnd = null;
        placementHint = null;
      });
  }

  Offset? drawingBefore;
  bool placingWallStart = false;
  bool drawingStrokeActive = false;
  bool wallFromAdjust = false;
  Timer? wallHoldTimer;
  Offset? wallHoldScreen;
  double get canvasZoom => canvasTransform.value.getMaxScaleOnAxis();

  List<Offset> visibleWallAttachments(Size size) {
    final painter = interactionPainter();
    final result = <Offset>[];
    for (final p
        in wallAttachmentPoints(base, derived.floors[floorIndex].openings)) {
      final local = painter.point(p.dx, p.dy, size);
      if (result.every((q) =>
          (local - painter.point(q.dx, q.dy, size)).distance * canvasZoom >=
          42)) result.add(p);
    }
    return result;
  }

  WallSegment? wallAtPoint(Offset local, Size size) {
    final painter = interactionPainter(),
        world = painter.worldPoint(local, size);
    final tolerance = 18 / (painter.scale(size) * canvasZoom);
    final walls = base.wallSegments.where((w) {
      final along = w.axis.dir == AxisDir.H ? world.x : world.y;
      final cross = w.axis.dir == AxisDir.H ? world.y : world.x;
      return along >= w.start.pos - tolerance &&
          along <= w.end.pos + tolerance &&
          (cross - w.axis.pos).abs() <= tolerance;
    }).toList();
    walls.sort((a, b) =>
        (a.axis.dir == AxisDir.H ? world.y - a.axis.pos : world.x - a.axis.pos)
            .abs()
            .compareTo((b.axis.dir == AxisDir.H
                    ? world.y - b.axis.pos
                    : world.x - b.axis.pos)
                .abs()));
    return walls.firstOrNull;
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
    final wall = wallAtPoint(local, size);
    if (wall == null) return;
    wallHoldTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || pointers.length != 1 || cancelledStroke) return;
      final point = attachmentOnWall(wall, local, size);
      setState(cancelDrag);
      showWallContext(wall, point);
    });
  }

  Future<void> showWallContext(WallSegment wall, Offset point) async {
    final inner = wall.axis.kind != 'boundary';
    if (inner) selectWallForEdit(wall, point.dx, point.dy);
    final wallLength = inner
        ? (editEnd! - editStart!).distance
        : (wall.end.pos - wall.start.pos).toDouble();
    final openingAtPoint = derived.floors[floorIndex].openings.any((o) {
      final along = o.axis.dir == AxisDir.H ? point.dx : point.dy;
      final cross = o.axis.dir == AxisDir.H ? point.dy : point.dx;
      return o.status == 'ok' &&
          cross == o.axis.pos &&
          along >= o.start &&
          along <= o.end;
    });
    final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              ListTile(
                  title: const Text('墙体操作'),
                  subtitle: Text(
                      '${inner ? "内墙" : "外墙"} · ${(wallLength / 1000).toStringAsFixed(2)} 米')),
              ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('从这里接墙'),
                  subtitle: openingAtPoint ? const Text('此处有门窗，请换个接墙位置') : null,
                  onTap: openingAtPoint
                      ? null
                      : () => Navigator.pop(context, 'add')),
              if (inner) ...[
                ListTile(
                    title: const Text('调整长度'),
                    onTap: () => Navigator.pop(context, 'length')),
                ListTile(
                    title: const Text('移动墙体'),
                    onTap: () => Navigator.pop(context, 'move')),
                ListTile(
                    title: const Text('修改墙厚'),
                    onTap: () => Navigator.pop(context, 'thickness')),
                ListTile(
                    title: const Text('删除墙体'),
                    onTap: () => Navigator.pop(context, 'delete')),
              ] else
                ListTile(
                    title: const Text('调整房屋长宽'),
                    onTap: () => Navigator.pop(context, 'footprint')),
            ])));
    if (choice == null || !mounted) return;
    if (choice == 'add') {
      setState(() {
        startWallDrawing();
        drawingOrigin = point;
      });
      return;
    }
    if (choice == 'footprint') {
      await footprintOptions();
      return;
    }
    selectWallForEdit(wall, point.dx, point.dy);
    if (choice == 'length') await preciseWallLength();
    if (choice == 'move') await preciseWallPosition();
    if (choice == 'thickness') await wallSettings(directThickness: true);
    if (choice == 'delete') await deleteSelectedWall();
  }

  Offset wallPoint(Offset local, Size size,
      {Set<String> excludeAxes = const {}}) {
    final painter = interactionPainter(),
        world = painter.worldPoint(local, size);
    final tolerance = 14 / (painter.scale(size) * canvasZoom);
    double snap(double value, List<ResolvedAxis> axes) {
      ResolvedAxis? best;
      var distance = tolerance;
      for (final axis in axes)
        if (!excludeAxes.contains(axis.id) &&
            (axis.pos - value).abs() < distance) {
          best = axis;
          distance = (axis.pos - value).abs();
        }
      return best?.pos.toDouble() ?? (value / 100).round() * 100.0;
    }

    return Offset(snap(world.x, base.axes.v), snap(world.y, base.axes.h));
  }

  void beginWallStroke(Offset local, Size size) {
    drawingStrokeActive = true;
    drawingBefore = drawingOrigin;
    final painter = interactionPainter();
    final candidates = [
      if (drawingOrigin != null) drawingOrigin!,
      ...visibleWallAttachments(size)
    ];
    candidates.sort((a, b) => (painter.point(a.dx, a.dy, size) - local)
        .distance
        .compareTo((painter.point(b.dx, b.dy, size) - local).distance));
    if (candidates.isNotEmpty &&
        (painter.point(candidates.first.dx, candidates.first.dy, size) - local)
                    .distance *
                canvasZoom <=
            24) {
      drawingOrigin = candidates.first;
    } else if (placingWallStart) {
      drawingOrigin = wallPoint(local, size);
      placingWallStart = false;
    } else {
      final wall = wallAtPoint(local, size);
      drawingOrigin = wall == null ? null : attachmentOnWall(wall, local, size);
      if (wall == null) placementHint = '从墙上的 ➕ 拖出新墙；独立起墙请点“独立墙”';
    }
    drawingEnd = null;
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
    final raw = interactionPainter().worldPoint(local, size);
    final horizontal =
        (raw.x - drawingOrigin!.dx).abs() >= (raw.y - drawingOrigin!.dy).abs();
    final exclude = <String>{
      for (final axis in horizontal ? base.axes.v : base.axes.h)
        if (axis.pos == (horizontal ? drawingOrigin!.dx : drawingOrigin!.dy))
          axis.id
    };
    final end = wallPoint(local, size, excludeAxes: exclude),
        delta = end - drawingOrigin!;
    drawingEnd = delta.dx.abs() >= delta.dy.abs()
        ? Offset(end.dx, drawingOrigin!.dy)
        : Offset(drawingOrigin!.dx, end.dy);
    if ((drawingEnd! - drawingOrigin!).distance < 300) {
      spatialDocument = null;
      spatialBase = null;
      spatialError = null;
      return;
    }
    final result = executeCommand(
        extractDesignState(history.present),
        DesignCommand('AddDrawnWall', drawingArguments),
        CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
    if (result is Applied) {
      spatialDocument = composeDocument(history.present.meta, result.newState);
      spatialBase = deriveFloorBase(spatialDocument!, floor.id);
      spatialError = null;
      placementHint = '松手创建墙，末端可继续拖动';
    } else {
      spatialDocument = null;
      spatialBase = null;
      spatialError = result is Rejected ? result.message : '此处无法绘墙';
      placementHint = spatialError;
    }
  }

  void finishWallStroke() {
    final end = drawingEnd, error = spatialError;
    if (drawingOrigin == null) drawingOrigin = drawingBefore;
    final accepted = end != null &&
        drawingOrigin != null &&
        (end - drawingOrigin!).distance >= 300 &&
        error == null;
    final args = accepted ? drawingArguments : null;
    spatialDocument = null;
    spatialBase = null;
    spatialError = null;
    drawingStrokeActive = false;
    drawingBefore = null;
    drawingEnd = null;
    if (args != null) {
      action('AddDrawnWall', args);
      drawingOrigin = end;
    }
    if (error != null)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    placementHint = '从墙上的 ➕ 拖出新墙 · 长按墙体可修改';
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
    toolCategory = 0;
    drawingOrigin = null;
    placingWallStart = false;
    drawingEnd = null;
    placementHint = '拖墙上的 ➕ 接墙 · 长按墙体修改';
  }

  Widget floatingHeader() => floatingSurface(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          BackButton(),
          Expanded(
              child: Text(history.present.meta.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15))),
          IconButton(
              tooltip: '撤销',
              icon: const Icon(Icons.undo, size: 21),
              onPressed: history.canUndo
                  ? () {
                      setState(() {
                        cancelDrag();
                        history.undo();
                        selectedWall = null;
                        drawingEnd = null;
                        changed();
                      });
                    }
                  : null),
          IconButton(
              tooltip: '重做',
              icon: const Icon(Icons.redo, size: 21),
              onPressed: history.canRedo
                  ? () {
                      setState(() {
                        cancelDrag();
                        history.redo();
                        selectedWall = null;
                        drawingEnd = null;
                        changed();
                      });
                    }
                  : null),
          IconButton(
              tooltip: '平面 / 3D',
              icon: Icon(view3d ? Icons.grid_view : Icons.view_in_ar, size: 21),
              onPressed: () => setState(() {
                    cancelDrag();
                    view3d = !view3d;
                    toolCategory = view3d ? 2 : 0;
                    tool = 'browse';
                    browse = true;
                    drawingEnd = null;
                    selectedWall = null;
                  })),
          PopupMenuButton<String>(
              tooltip: '更多操作',
              onSelected: (value) {
                if (value == 'checks') checks();
                if (value == 'settings') settings();
                if (value == 'export') export();
              },
              itemBuilder: (context) => const [
                    PopupMenuItem(value: 'checks', child: Text('设计检查')),
                    PopupMenuItem(value: 'settings', child: Text('设置')),
                    PopupMenuItem(value: 'export', child: Text('导出 .house'))
                  ])
        ]),
        Row(children: [
          const SizedBox(width: 12),
          DropdownButton<int>(
              value: floorIndex,
              underline: const SizedBox.shrink(),
              items: [
                for (var i = 0; i < history.present.floors.length; i++)
                  DropdownMenuItem(
                      value: i,
                      child: Text(history.present.floors[i].name,
                          style: const TextStyle(fontSize: 13)))
              ],
              onChanged: (value) => setState(() {
                    cancelDrag();
                    floorIndex = value!;
                    tool = 'browse';
                    browse = true;
                    selectedWall = null;
                    drawingOrigin = null;
                    drawingEnd = null;
                    derive();
                  })),
          IconButton(
              tooltip: '楼层操作',
              onPressed: floorOptions,
              icon: const Icon(Icons.layers_outlined, size: 20)),
          Expanded(
              child: TextButton(
                  onPressed: footprintOptions,
                  child: Tooltip(
                      message: '房屋长宽',
                      child: Text(
                          '${(base.axes.v.last.pos / 1000).toStringAsFixed(1)} × ${(base.axes.h.last.pos / 1000).toStringAsFixed(1)} 米',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12))))),
          IconButton(
              tooltip: '立即保存',
              onPressed: save,
              icon: const Icon(Icons.save_outlined, size: 20)),
        ])
      ])));

  List<Widget> categoryTools() {
    if (tool == 'editWall' && editStart != null && editEnd != null)
      return [
        TextButton.icon(
            onPressed: preciseWallLength,
            icon: const Icon(Icons.straighten, size: 18),
            label: Text(
                '${((editEnd! - editStart!).distance / 1000).toStringAsFixed(2)} 米')),
        basicTool(Icons.open_with, '墙位置', false, preciseWallPosition),
        basicTool(Icons.add, '继续绘墙', false, () {
          final end = editEnd;
          startWallDrawing();
          drawingOrigin = end;
          toolCategory = 0;
        }),
        basicTool(Icons.delete_outline, '删除墙', false, deleteSelectedWall),
        basicTool(Icons.more_horiz, '墙设置', false, wallSettings)
      ];
    if (toolCategory == 0)
      return [
        basicTool(
            Icons.add_outlined, '墙体', tool == 'drawWall', startWallDrawing),
        basicTool(Icons.vertical_split_outlined, '拉线分房', tool == 'split', () {
          view3d = false;
          browse = false;
          tool = 'split';
        }),
        if (tool == 'drawWall')
          basicTool(Icons.add_box_outlined, '独立墙', placingWallStart, () {
            drawingOrigin = null;
            placingWallStart = true;
            placementHint = '在空白处拖出独立墙，或点一下选起点';
          })
        else
          basicTool(Icons.crop_square, '拖动划房', tool == 'box', () {
            view3d = false;
            browse = false;
            tool = 'box';
            brush = RoomType.custom;
          }),
        openingTool(OpeningKind.door, Icons.door_front_door_outlined, '拖入门'),
        openingTool(OpeningKind.window, Icons.window_outlined, '拖入窗'),
        basicTool(Icons.more_horiz, '更多工具', false, moreTools)
      ];
    if (toolCategory == 1)
      return [
        basicTool(Icons.pan_tool_outlined, '浏览', browse, () {
          tool = 'browse';
          browse = true;
        }),
        basicTool(Icons.view_week_outlined, '墙体调整', tool == 'selectWall', () {
          view3d = false;
          tool = 'selectWall';
          browse = false;
        }),
        basicTool(Icons.straighten, '房屋尺寸', tool == 'resize', footprintOptions),
        basicTool(Icons.more_horiz, '更多工具', false, moreTools)
      ];
    return [
      basicTool(Icons.center_focus_strong, '恢复画布视角', false, () {
        if (view3d) viewResetToken++;
        canvasTransform.value = Matrix4.identity();
      }),
      basicTool(Icons.layers_outlined, '楼层操作', false, floorOptions),
      basicTool(Icons.fact_check_outlined, '设计检查', false, checks)
    ];
  }

  Widget categoryRail() => floatingSurface(Padding(
      padding: const EdgeInsets.all(4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Semantics(
              selected: toolCategory == i,
              button: true,
              label: ['建造分类', '调整分类', '查看分类'][i],
              child: Tooltip(
                  message: ['建造分类', '调整分类', '查看分类'][i],
                  child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => chooseCategory(i),
                      child: AnimatedContainer(
                          duration: motionDuration,
                          width: 48,
                          padding: EdgeInsets.symmetric(
                              vertical: MediaQuery.sizeOf(context).height < 450
                                  ? 6
                                  : 10),
                          decoration: BoxDecoration(
                              color: toolCategory == i
                                  ? Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16)),
                          child: Column(children: [
                            Icon(
                                [
                                  Icons.add_box_outlined,
                                  Icons.tune,
                                  Icons.visibility_outlined
                                ][i],
                                size: 22),
                            const SizedBox(height: 3),
                            Text(['建造', '调整', '查看'][i],
                                style: const TextStyle(fontSize: 11))
                          ])))))
      ])));

  String get interactionHint =>
      placementHint ??
      (tool == 'drawWall'
          ? '拖墙上的 ➕ 接墙 · 长按墙体修改'
          : tool == 'selectWall'
              ? '点墙修改 · 拖 ➕ 接墙 · 双指移动'
              : spatialTool
                  ? (tool == 'split' ? '拉一条横线或竖线，松手分房' : '从一角拖到另一角，松手创建房间')
                  : tool == 'resize'
                      ? '拖动外框手柄 · 作用于全部楼层'
                      : '拖动画布 · 点选对象调整 · 双指缩放');

  Widget floatingTools() {
    final tools = Wrap(
        key: ValueKey('$toolCategory:$tool'),
        alignment: WrapAlignment.center,
        spacing: 2,
        runSpacing: 4,
        children: categoryTools());
    final reduced = MediaQuery.disableAnimationsOf(context);
    final content = Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          reduced
              ? tools
              : AnimatedSwitcher(
                  duration: motionDuration,
                  layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          clipBehavior: Clip.none,
                          children: [
                            for (final child in previous)
                              Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                      child: ExcludeSemantics(child: child))),
                            if (current != null) current
                          ]),
                  child: tools),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
                child: Text(view3d ? '单指旋转 · 双指缩放和平移' : interactionHint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11))),
            if (tool == 'drawWall')
              IconButton(
                  tooltip: '输入墙长',
                  onPressed: drawingOrigin == null ? null : addWallByLength,
                  icon: const Icon(Icons.straighten, size: 18)),
            if (tool == 'drawWall')
              TextButton(
                  onPressed: () => setState(() {
                        cancelDrag();
                        tool = 'browse';
                        browse = true;
                        drawingOrigin = null;
                        drawingEnd = null;
                        placementHint = null;
                      }),
                  child: const Text('结束')),
            Text(status, style: const TextStyle(fontSize: 10))
          ])
        ]));
    return floatingSurface(reduced
        ? content
        : AnimatedSize(
            duration: motionDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: content));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final bottomReserve = MediaQuery.textScalerOf(context).scale(12) > 16
        ? (wide ? 150.0 : 210.0)
        : (wide
            ? 112.0
            : MediaQuery.sizeOf(context).width < 350
                ? 180.0
                : 138.0);
    return PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop) {
            await save();
            if (mounted && !dirty) Navigator.pop(context);
          }
        },
        child: Scaffold(
            body: SafeArea(
                child: Stack(children: [
          SizedBox.expand(
              child: view3d
                  ? Padding(
                      padding: canvasInsets,
                      child: HouseViewer(
                          house: derived,
                          onPick: pick3d,
                          showHint: false,
                          resetToken: viewResetToken))
                  : LayoutBuilder(builder: (context, constraints) {
                      final size =
                          Size(constraints.maxWidth, constraints.maxHeight);
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
                          panEnabled: (browse && draggingOpening == null) ||
                              pointers.length > 1,
                          minScale: 0.4,
                          maxScale: 5,
                          child: Listener(
                              onPointerDown: (e) {
                                if (pointers.isEmpty) {
                                  cancelledStroke = false;
                                  wallFromAdjust = false;
                                }
                                pointers.add(e.pointer);
                                if (pointers.length == 1)
                                  scheduleWallHold(
                                      e.localPosition, e.position, size);
                                downPoint = e.localPosition;
                                if (pointers.length == 1) {
                                  if (tool == 'selectWall') {
                                    final painter = interactionPainter();
                                    final hit = visibleWallAttachments(size)
                                        .any((p) =>
                                            (painter.point(p.dx, p.dy, size) -
                                                        e.localPosition)
                                                    .distance *
                                                canvasZoom <=
                                            24);
                                    if (hit)
                                      setState(() {
                                        tool = 'drawWall';
                                        browse = false;
                                        wallFromAdjust = true;
                                        beginWallStroke(e.localPosition, size);
                                      });
                                  } else if (tool == 'drawWall') {
                                    setState(() =>
                                        beginWallStroke(e.localPosition, size));
                                  } else if (tool == 'editWall') {
                                    setState(() =>
                                        beginWallEdit(e.localPosition, size));
                                  } else if (spatialTool) {
                                    spatialStart = null;
                                    setState(() =>
                                        updateSpatial(e.localPosition, size));
                                  } else {
                                    setState(
                                        () => beginDrag(e.localPosition, size));
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
                                    tool != 'grid')
                                  setState(() => record(e.localPosition, size));
                              },
                              onPointerMove: (e) {
                                if (wallHoldScreen != null &&
                                    (e.position - wallHoldScreen!).distance > 8)
                                  wallHoldTimer?.cancel();
                                if (tool == 'editWall' &&
                                    !cancelledStroke &&
                                    pointers.length == 1)
                                  setState(() =>
                                      previewWallEdit(e.localPosition, size));
                                if (tool == 'drawWall' &&
                                    !cancelledStroke &&
                                    pointers.length == 1)
                                  setState(() =>
                                      previewWallStroke(e.localPosition, size));
                                if (spatialTool &&
                                    !cancelledStroke &&
                                    pointers.length == 1) {
                                  setState(() =>
                                      updateSpatial(e.localPosition, size));
                                }
                                if (!cancelledStroke &&
                                    pointers.length == 1 &&
                                    (draggingAxis != null ||
                                        draggingOpening != null))
                                  setState(
                                      () => previewDrag(e.localPosition, size));
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
                                    !cancelledStroke &&
                                    pointers.length == 1)
                                  setState(() => record(e.localPosition, size));
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
                                if (tool == 'editWall' &&
                                    wallGrip != null &&
                                    !cancelledStroke &&
                                    pointers.length == 1) {
                                  finishWallEdit();
                                  pointers.remove(e.pointer);
                                  downPoint = null;
                                  return;
                                }
                                if (tool == 'drawWall' &&
                                    !cancelledStroke &&
                                    pointers.length == 1) {
                                  final tapFromAdjust = wallFromAdjust &&
                                      downPoint != null &&
                                      (downPoint! - e.localPosition).distance *
                                              canvasZoom <
                                          8;
                                  if (tapFromAdjust) {
                                    setState(() {
                                      cancelDrag();
                                      tool = 'selectWall';
                                    });
                                    tapObject(e.localPosition, size);
                                  } else {
                                    finishWallStroke();
                                    if (wallFromAdjust) toolCategory = 0;
                                  }
                                  pointers.remove(e.pointer);
                                  downPoint = null;
                                  return;
                                }
                                if (tool == 'placeOpening' &&
                                    !cancelledStroke &&
                                    pointers.length == 1 &&
                                    downPoint != null &&
                                    (downPoint! - e.localPosition).distance <
                                        8) {
                                  final box = canvasKey.currentContext!
                                      .findRenderObject() as RenderBox;
                                  previewOpening(placingOpening!,
                                      box.localToGlobal(e.localPosition));
                                  final args = openingDrop;
                                  derive();
                                  if (args != null)
                                    action('AddOpening', args);
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                              SnackBar(content: Text(message)));
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
                                    (downPoint! - e.localPosition).distance <
                                        8) {
                                  tapObject(e.localPosition, size);
                                }
                                if (tool == 'stair' &&
                                    !cancelledStroke &&
                                    stroke.isNotEmpty &&
                                    pointers.length == 1) {
                                  final first = stroke.first,
                                      last = stroke.last;
                                  final i0 = math.min(first.i, last.i),
                                      i1 = math.max(first.i, last.i) + 1,
                                      j0 = math.min(first.j, last.j),
                                      j1 = math.max(first.j, last.j) + 1;
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
                                  action(erase ? 'EraseCells' : 'PaintCells', {
                                    'floorId': floor.id,
                                    'cells': cells,
                                    'roomType': brush
                                  });
                                }
                                pointers.remove(e.pointer);
                                lastPoint = null;
                              },
                              child: DragTarget<OpeningKind>(
                                  onWillAcceptWithDetails: (_) => true,
                                  onMove: (details) => setState(() => previewOpening(
                                      details.data, details.offset)),
                                  onLeave: (_) => setState(() {
                                        openingDrop = null;
                                        placementHint = null;
                                        derive();
                                      }),
                                  onAcceptWithDetails: (details) {
                                    previewOpening(
                                        details.data, details.offset);
                                    final arguments = openingDrop;
                                    openingDrop = null;
                                    placementHint = null;
                                    derive();
                                    if (arguments != null)
                                      action('AddOpening', arguments);
                                    else
                                      setState(() {});
                                  },
                                  builder: (context, candidates, rejected) =>
                                      CustomPaint(
                                          key: canvasKey,
                                          size: size,
                                          painter: FloorPlanPainter(
                                              displayBase,
                                              {
                                                for (final r in displayRooms)
                                                  r.id: r.name
                                              },
                                              {
                                                for (final r in displayRooms)
                                                  r.id: roomColors[r.type]!
                                              },
                                              viewportInsets: canvasInsets,
                                              openings: displayOpenings,
                                              stairs: derived
                                                  .floors[floorIndex].stairs,
                                              northAngleDeg: history.present
                                                  .footprint.northAngleDeg,
                                              focus: focus,
                                              editableWall: tool == 'editWall' &&
                                                      editStart != null &&
                                                      editEnd != null
                                                  ? PlanRect(
                                                      (editPreviewStart ??
                                                              editStart)!
                                                          .dx,
                                                      (editPreviewStart ??
                                                              editStart)!
                                                          .dy,
                                                      (editPreviewEnd ?? editEnd)!.dx,
                                                      (editPreviewEnd ?? editEnd)!.dy)
                                                  : null,
                                              wallSeed: tool == 'drawWall' ? drawingOrigin : null,
                                              wallAttachments: (tool == 'drawWall' || tool == 'selectWall') ? visibleWallAttachments(size) : const [],
                                              handleScale: canvasZoom,
                                              draftLabel: tool == 'drawWall' && drawingEnd != null && drawingOrigin != null ? '${((drawingEnd! - drawingOrigin!).distance / 1000).toStringAsFixed(2)} 米' : null,
                                              draft: tool == 'drawWall' && drawingEnd != null && drawingOrigin != null ? PlanRect(math.min(drawingOrigin!.dx, drawingEnd!.dx), math.min(drawingOrigin!.dy, drawingEnd!.dy), math.max(drawingOrigin!.dx, drawingEnd!.dx), math.max(drawingOrigin!.dy, drawingEnd!.dy)) : spatialPreview,
                                              showGridDimensions: tool == 'grid',
                                              draftInvalid: spatialError != null,
                                              draftIsLine: tool == 'split' || tool == 'drawWall',
                                              viewport: draggingAxis?.kind == 'boundary' && dragAttempted && dragCoordinatePainter != null
                                                  ? (
                                                      scale:
                                                          dragCoordinatePainter!
                                                              .scale(size),
                                                      origin:
                                                          dragCoordinatePainter!
                                                              .origin(size)
                                                    )
                                                  : null,
                                              resizeHandles: tool == 'resize',
                                              wallHandle: tool == 'wall' && selectedWall != null ? (selectedWall!.axis.dir == AxisDir.V ? PlanRect((dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.start.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.end.pos.toDouble()) : PlanRect(selectedWall!.start.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.end.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()))) : null,
                                              preview: List.of(stroke))))));
                    })),
          Positioned(
              top: 12,
              left: 12,
              right: wide ? 80 : 12,
              child: floatingHeader()),
          Positioned(
              right: 12,
              top: wide ? 12 : 112,
              bottom: wide ? 12 : bottomReserve,
              child: Align(
                  alignment: Alignment.centerRight, child: categoryRail())),
          Positioned(
              left: 12,
              right: wide ? 80 : 12,
              bottom: 12,
              child: floatingTools()),
        ]))));
  }
}
