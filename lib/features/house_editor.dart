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

  Future<void> create() async {
    final start = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final entry in houseTemplates.entries)
                ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(context, entry.key)),
            ])));
    if (start == null) return;
    if (start != 'blank') {
      try {
        final doc = createTemplate(start,
            DateTime.now().toUtc().toIso8601String(), () => const Uuid().v4());
        final id = await store.createProject(doc);
        if (mounted) await open(ProjectEntry(id, doc));
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法创建，请检查存储空间')));
      }
      return;
    }
    final name = TextEditingController(text: '我的房屋'),
        width = TextEditingController(text: '12.00'),
        depth = TextEditingController(text: '10.00');
    var columns = 3, rows = 2;
    String? validation;
    final doc = await showDialog<HouseDocument>(
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
                              const InputDecoration(labelText: '房屋宽度（米）')),
                      TextField(
                          controller: depth,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: '房屋进深（米）')),
                      Row(children: [
                        const Text('分成几间？'),
                        const Spacer(),
                        IconButton(
                            onPressed: columns > 1
                                ? () => setDialog(() => columns--)
                                : null,
                            icon: const Icon(Icons.remove)),
                        Text('$columns'),
                        IconButton(
                            onPressed: columns < 12
                                ? () => setDialog(() => columns++)
                                : null,
                            icon: const Icon(Icons.add))
                      ]),
                      Row(children: [
                        const Text('分成几段？'),
                        const Spacer(),
                        IconButton(
                            onPressed:
                                rows > 1 ? () => setDialog(() => rows--) : null,
                            icon: const Icon(Icons.remove)),
                        Text('$rows'),
                        IconButton(
                            onPressed: rows < 12
                                ? () => setDialog(() => rows++)
                                : null,
                            icon: const Icon(Icons.add))
                      ]),
                      if (validation != null)
                        Text(validation!,
                            style: const TextStyle(color: Colors.red))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () {
                            final w = double.tryParse(width.text),
                                d = double.tryParse(depth.text);
                            if (w == null ||
                                d == null ||
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
                                    timestamp: DateTime.now()
                                        .toUtc()
                                        .toIso8601String(),
                                    newId: () => const Uuid().v4()));
                          },
                          child: const Text('开始设计'))
                    ])));
    // The controllers stay alive until the dialog exit animation completes.
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
                const Text('从几个格子，搭出你的家',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('分格子 · 填房间 · 看尺寸'),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: create,
                    icon: const Icon(Icons.add),
                    label: const Padding(
                        padding: EdgeInsets.all(12), child: Text('新建设计'))),
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
  const HouseEditor({super.key, required this.entry, required this.store});
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
  String tool = 'room';
  PlanRect? focus;
  Offset? downPoint;
  int floorIndex = 0;
  RoomType brush = RoomType.living;
  bool browse = false, erase = false, dirty = false, saving = false;
  String status = '已保存';
  final stroke = <Cell>[];
  final pointers = <int>{};
  bool cancelledStroke = false;
  Offset? lastPoint;
  ResolvedAxis? draggingAxis;
  OpeningPlacement? draggingOpening;
  Map<String, dynamic>? dragArguments;
  String? dragKind;
  bool dragged = false;
  Timer? timer;
  Future<void>? pendingSave;
  Floor get floor => history.present.floors[floorIndex];
  @override
  void initState() {
    super.initState();
    history = DesignHistory(widget.entry.document);
    derive();
    WidgetsBinding.instance.addObserver(this);
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
    draggingAxis = null;
    draggingOpening = null;
    dragArguments = null;
    dragKind = null;
    dragged = false;
    final painter = FloorPlanPainter(base, {}, {}), scale = painter.scale(size);
    final x = painter.worldPoint(point, size).x,
        y = painter.worldPoint(point, size).y,
        tolerance = 12 / scale;
    if (tool == 'grid') {
      final axes = base.axes.all
          .where((a) =>
              a.kind != 'boundary' &&
              ((a.dir == AxisDir.V ? x : y) - a.pos).abs() <= tolerance)
          .toList();
      axes.sort((a, b) => ((a.dir == AxisDir.V ? x : y) - a.pos)
          .abs()
          .compareTo(((b.dir == AxisDir.V ? x : y) - b.pos).abs()));
      draggingAxis = axes.firstOrNull;
    } else if (tool == 'opening') {
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
    final painter = FloorPlanPainter(base, {}, {});
    final x = painter.worldPoint(point, size).x,
        y = painter.worldPoint(point, size).y;
    if (draggingAxis != null) {
      final axis = draggingAxis!;
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
    } else if (draggingOpening != null) {
      final opening = draggingOpening!;
      final axes = resolveFloorAxes(history.present, floor.id)!;
      final chain = resolveAnchor(axes, opening.opening.anchor).chain!;
      final along = opening.axis.dir == AxisDir.H ? x : y;
      dragKind = 'MoveOpening';
      dragArguments = {
        'openingId': opening.opening.id,
        'position': {
          'type': 'fromStart',
          'd': math.max(
              0, (along - chain.startPos - opening.opening.width / 2).round())
        }
      };
    } else {
      return;
    }
    var id = 0;
    final result = executeCommand(
        extractDesignState(history.present),
        DesignCommand(dragKind!, dragArguments!),
        CommandContext(
            newId: () => '__preview_${++id}',
            now: () => '1970-01-01T00:00:00Z'));
    if (result is Applied) {
      dragged = true;
      derived =
          deriveHouse(composeDocument(history.present.meta, result.newState));
      base = derived.floors[floorIndex].base;
    }
  }

  void cancelDrag() {
    draggingAxis = null;
    draggingOpening = null;
    dragArguments = null;
    dragKind = null;
    dragged = false;
    derive();
  }

  void sample(Offset p, Size size) {
    final painter = FloorPlanPainter(base, {}, {});
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
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
    final painter = FloorPlanPainter(base, {}, {}), scale = painter.scale(size);
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
    if (opening != null) {
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
      final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final entry in {
                  'door': '门',
                  'window': '窗',
                  'sliding': '推拉门',
                  'open': '开放（无墙）',
                  'thickness': '调整墙厚',
                  'default': '恢复默认墙'
                }.entries)
                  ListTile(
                      title: Text(entry.value),
                      onTap: () => Navigator.pop(context, entry.key))
              ])));
      if (choice == null) return;
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
      final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    title: Text(room.name),
                    subtitle: const Text('修改名称'),
                    onTap: () => Navigator.pop(context, 'rename')),
                for (final type in RoomType.values)
                  ListTile(
                      title: Text(roomNames[type]!),
                      selected: room.type == type,
                      onTap: () => Navigator.pop(context, type.name)),
                ListTile(
                    title: const Text('与相邻房间合并'),
                    onTap: () => Navigator.pop(context, 'merge')),
                ListTile(
                    title: const Text('删除房间'),
                    onTap: () => Navigator.pop(context, 'delete')),
              ])));
      if (choice == 'rename') {
        final value = await ask('房间名称', room.name);
        if (value != null)
          action('RenameRoom', {'roomId': room.id, 'value': value});
      } else if (choice == 'merge') {
        final target = await showModalBottomSheet<String>(
            context: context,
            builder: (context) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  for (final other in floor.rooms.where((r) => r.id != room.id))
                    ListTile(
                        title: Text(other.name),
                        onTap: () => Navigator.pop(context, other.id)),
                ])));
        if (target != null)
          action('MergeRooms', {'roomIdA': room.id, 'roomIdB': target});
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
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

  @override
  Widget build(BuildContext context) {
    final roomMap = {for (final r in floor.rooms) r.id: r};
    return PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop) {
            await save();
            if (mounted && !dirty) Navigator.pop(context);
          }
        },
        child: Scaffold(
            appBar: AppBar(title: Text(history.present.meta.name), actions: [
              IconButton(
                  tooltip: '撤销',
                  onPressed: history.canUndo
                      ? () => setState(() {
                            history.undo();
                            changed();
                          })
                      : null,
                  icon: const Icon(Icons.undo)),
              IconButton(
                  tooltip: '重做',
                  onPressed: history.canRedo
                      ? () => setState(() {
                            history.redo();
                            changed();
                          })
                      : null,
                  icon: const Icon(Icons.redo)),
              IconButton(
                  tooltip: '平面 / 3D',
                  onPressed: () => setState(() => view3d = !view3d),
                  icon: Icon(view3d ? Icons.grid_view : Icons.view_in_ar)),
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
                  PopupMenuItem(value: 'export', child: Text('导出 .house')),
                ],
              )
            ]),
            body: Column(children: [
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    DropdownButton<int>(
                        value: floorIndex,
                        items: [
                          for (var i = 0;
                              i < history.present.floors.length;
                              i++)
                            DropdownMenuItem(
                                value: i,
                                child: Text(history.present.floors[i].name))
                        ],
                        onChanged: (value) => setState(() {
                              floorIndex = value!;
                              derive();
                            })),
                    IconButton(
                        tooltip: '楼层操作',
                        onPressed: floorOptions,
                        icon: const Icon(Icons.layers_outlined)),
                    const Spacer(),
                    Text(status, style: const TextStyle(fontSize: 12)),
                    IconButton(
                        tooltip: '立即保存',
                        onPressed: save,
                        icon: const Icon(Icons.save_outlined))
                  ])),
              Expanded(
                  child: view3d
                      ? HouseViewer(house: derived, onPick: pick3d)
                      : LayoutBuilder(builder: (context, constraints) {
                          final size =
                              Size(constraints.maxWidth, constraints.maxHeight);
                          return InteractiveViewer(
                              panEnabled: browse || pointers.length > 1,
                              minScale: 0.4,
                              maxScale: 5,
                              child: Listener(
                                  onPointerDown: (e) {
                                    if (pointers.isEmpty)
                                      cancelledStroke = false;
                                    pointers.add(e.pointer);
                                    downPoint = e.localPosition;
                                    if (pointers.length == 1)
                                      beginDrag(e.localPosition, size);
                                    if (pointers.length > 1) {
                                      cancelledStroke = true;
                                      setState(() {
                                        stroke.clear();
                                        cancelDrag();
                                      });
                                      lastPoint = null;
                                      return;
                                    }
                                    if (!browse &&
                                        tool != 'opening' &&
                                        tool != 'grid')
                                      setState(
                                          () => record(e.localPosition, size));
                                  },
                                  onPointerMove: (e) {
                                    if (!cancelledStroke &&
                                        pointers.length == 1 &&
                                        (draggingAxis != null ||
                                            draggingOpening != null))
                                      setState(() =>
                                          previewDrag(e.localPosition, size));
                                    if (!browse &&
                                        tool != 'opening' &&
                                        tool != 'grid' &&
                                        !cancelledStroke &&
                                        pointers.length == 1)
                                      setState(
                                          () => record(e.localPosition, size));
                                  },
                                  onPointerCancel: (e) {
                                    pointers.remove(e.pointer);
                                    setState(() {
                                      stroke.clear();
                                      cancelDrag();
                                    });
                                    lastPoint = null;
                                  },
                                  onPointerUp: (e) {
                                    if (dragged &&
                                        !cancelledStroke &&
                                        pointers.length == 1) {
                                      final kind = dragKind!,
                                          arguments = dragArguments!;
                                      cancelDrag();
                                      action(kind, arguments);
                                      pointers.remove(e.pointer);
                                      lastPoint = null;
                                      downPoint = null;
                                      return;
                                    }
                                    if ((browse ||
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
                                      setState(() {
                                        final next = paintCells(
                                            history.present,
                                            floor.id,
                                            List.of(stroke),
                                            brush,
                                            () => const Uuid().v4(),
                                            erase: erase);
                                        if (history.commit(next)) changed();
                                        stroke.clear();
                                      });
                                    }
                                    pointers.remove(e.pointer);
                                    lastPoint = null;
                                  },
                                  child: CustomPaint(
                                      size: size,
                                      painter: FloorPlanPainter(
                                          base,
                                          {
                                            for (final r in roomMap.values)
                                              r.id: r.name
                                          },
                                          {
                                            for (final r in roomMap.values)
                                              r.id: roomColors[r.type]!
                                          },
                                          openings: derived
                                              .floors[floorIndex].openings,
                                          stairs:
                                              derived.floors[floorIndex].stairs,
                                          northAngleDeg: history
                                              .present.footprint.northAngleDeg,
                                          focus: focus,
                                          preview: List.of(stroke)))));
                        })),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        ChoiceChip(
                            label: const Text('浏览'),
                            selected: browse,
                            onSelected: (_) => setState(() {
                                  browse = true;
                                  tool = 'browse';
                                })),
                        const SizedBox(width: 8),
                        ChoiceChip(
                            label: const Text('网格'),
                            selected: tool == 'grid',
                            onSelected: (_) => setState(() {
                                  browse = false;
                                  tool = 'grid';
                                })),
                        const SizedBox(width: 8),
                        ChoiceChip(
                            label: const Text('门窗'),
                            selected: tool == 'opening',
                            onSelected: (_) => setState(() {
                                  tool = 'opening';
                                  browse = false;
                                })),
                        const SizedBox(width: 8),
                        ChoiceChip(
                            label: const Text('楼梯'),
                            selected: tool == 'stair',
                            onSelected: (_) => setState(() {
                                  tool = 'stair';
                                  browse = false;
                                })),
                        const SizedBox(width: 8),
                        for (final type in RoomType.values)
                          Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                  label: Text(roomNames[type]!),
                                  avatar: CircleAvatar(
                                      radius: 6,
                                      backgroundColor: roomColors[type]),
                                  selected: tool == 'room' &&
                                      !browse &&
                                      !erase &&
                                      brush == type,
                                  onSelected: (_) => setState(() {
                                        browse = false;
                                        tool = 'room';
                                        erase = false;
                                        brush = type;
                                      }))),
                        ChoiceChip(
                            label: const Text('擦除'),
                            selected: tool == 'room' && !browse && erase,
                            onSelected: (_) => setState(() {
                                  browse = false;
                                  tool = 'room';
                                  erase = true;
                                }))
                      ]))),
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                      tool == 'grid'
                          ? '拖动分隔线 · 双指缩放和平移'
                          : tool == 'opening'
                              ? '点墙添加门窗 · 拖动门窗调整位置'
                              : '单指刷房间 · 双指缩放和平移',
                      style: const TextStyle(fontSize: 12)))
            ])));
  }
}
