import '../document/house_document.dart';

/// Default plan size, height and elevation of each furniture kind (mm).
const furnitureDefaults = <FurnitureKind, (int w, int d, int h, int z)>{
  FurnitureKind.bed: (2000, 1600, 500, 0),
  FurnitureKind.singleBed: (2000, 900, 500, 0),
  FurnitureKind.wardrobe: (1200, 600, 2200, 0),
  FurnitureKind.table: (1200, 800, 750, 0),
  FurnitureKind.diningTable: (2000, 900, 750, 0),
  FurnitureKind.chair: (450, 450, 900, 0),
  FurnitureKind.sofa: (2200, 900, 800, 0),
  FurnitureKind.desk: (1200, 600, 750, 0),
  FurnitureKind.tvStand: (1600, 450, 500, 0),
  FurnitureKind.shelf: (1000, 400, 1800, 0),
  FurnitureKind.rug: (3000, 2000, 15, 0),
  FurnitureKind.alasha: (1000, 2500, 12, 0),
  FurnitureKind.wallRug: (2000, 40, 1500, 700),
  FurnitureKind.korpe: (2000, 650, 80, 0),
  FurnitureKind.cushion: (250, 500, 300, 80),
  FurnitureKind.dastarkhan: (1400, 1400, 350, 0),
  FurnitureKind.sandyq: (1200, 580, 550, 0),
  FurnitureKind.bench: (2000, 350, 450, 0),
  FurnitureKind.hooks: (850, 60, 250, 1450),
  FurnitureKind.counter: (2400, 600, 900, 0),
  FurnitureKind.stove: (600, 600, 900, 0),
  FurnitureKind.sink: (800, 600, 900, 0),
  FurnitureKind.fridge: (700, 650, 1900, 0),
  FurnitureKind.pantry: (900, 600, 2200, 0),
  FurnitureKind.bathtub: (1700, 700, 550, 0),
  FurnitureKind.shower: (900, 900, 2000, 0),
  FurnitureKind.toilet: (400, 650, 420, 0),
  FurnitureKind.basin: (600, 450, 850, 0),
  FurnitureKind.washer: (600, 600, 850, 0),
  FurnitureKind.boiler: (450, 400, 800, 1000),
  FurnitureKind.shoeCabinet: (700, 350, 1000, 0),
  FurnitureKind.terrace: (4800, 2600, 100, 0),
  FurnitureKind.porch: (3000, 1600, 150, 0),
  FurnitureKind.custom: (1000, 600, 800, 0),
};

/// Edits to [HouseExtras]. Returns null when [kind] is not an extras command.
({UndoableDesignState? state, String? error})? executeExtrasCommand(
    UndoableDesignState state,
    String kind,
    Map<String, dynamic> args,
    String Function() newId) {
  final x = state.extras;
  ({UndoableDesignState? state, String? error}) ok(HouseExtras next) {
    final problems = next.problems();
    if (problems.isNotEmpty) return (state: null, error: problems.first.$2);
    return (state: state.withExtras(next), error: null);
  }

  ({UndoableDesignState? state, String? error}) fail(String message) =>
      (state: null, error: message);
  int? i(String key) => (args[key] as num?)?.round();

  switch (kind) {
    case 'AddFurniture':
      final k = args['kind'] as FurnitureKind;
      final d = furnitureDefaults[k]!;
      final item = FurnitureItem(
          id: args['id'] as String? ?? newId(),
          floorId: args['floorId'] as String,
          kind: k,
          x: i('x') ?? 0,
          y: i('y') ?? 0,
          width: i('width') ?? d.$1,
          depth: i('depth') ?? d.$2,
          height: i('height') ?? d.$3,
          elevation: i('elevation') ?? d.$4,
          variant: i('variant') ?? 0,
          label: args['label'] as String?);
      if (x.furniture.any((f) => f.id == item.id)) return fail('家具 id 重复');
      return ok(x.copyWith(furniture: [...x.furniture, item]));
    case 'UpdateFurniture' || 'DeleteFurniture' || 'RotateFurniture':
      final id = args['furnitureId'] as String;
      final index = x.furniture.indexWhere((f) => f.id == id);
      if (index < 0) return fail('找不到要编辑的对象');
      final list = [...x.furniture];
      if (kind == 'DeleteFurniture') {
        list.removeAt(index);
      } else if (kind == 'RotateFurniture') {
        final f = list[index];
        final cx = f.x + f.width / 2, cy = f.y + f.depth / 2;
        list[index] = f.copyWith(
            width: f.depth,
            depth: f.width,
            x: (cx - f.depth / 2).round(),
            y: (cy - f.width / 2).round());
      } else {
        final f = list[index];
        final label = args['label'];
        list[index] = f.copyWith(
            x: i('x'),
            y: i('y'),
            width: i('width'),
            depth: i('depth'),
            height: i('height'),
            elevation: i('elevation'),
            variant: i('variant'),
            kind: args['kind'] as FurnitureKind?,
            floorId: args['floorId'] as String?,
            label: label is String && label.isNotEmpty ? label : null,
            clearLabel: args.containsKey('label') &&
                (label == null || label == ''));
      }
      return ok(x.copyWith(furniture: list));
    case 'SetRoomInfo':
      final id = args['roomId'] as String;
      final current = x.rooms[id] ?? const RoomInfo();
      final info = RoomInfo(
          note: args.containsKey('note')
              ? (args['note'] as String? ?? '')
              : current.note,
          labelArea: args.containsKey('labelArea')
              ? i('labelArea')
              : current.labelArea);
      return ok(x.copyWith(rooms: {
        ...x.rooms,
        id: info,
      }..removeWhere((_, v) => v.isEmpty)));
    case 'SetOpeningLabel':
      final id = args['openingId'] as String,
          value = (args['value'] as String? ?? '').trim();
      return ok(x.copyWith(
          openingLabels: {...x.openingLabels, id: value}
            ..removeWhere((_, v) => v.isEmpty)));
    case 'SetFoundation':
      var spec = x.foundation;
      if (args['field'] != null) {
        final field = args['field'] as String;
        if (!FoundationSpec.fieldsInt.contains(field))
          return fail('操作参数无效');
        spec = spec.withInt(field, i('value')!);
      }
      if (args['partitions'] != null)
        spec = spec.copyWith(partitions: args['partitions'] as bool);
      if (args['concrete'] != null)
        spec = spec.copyWith(concrete: args['concrete'] as String);
      if (args['reset'] == true) spec = const FoundationSpec();
      return ok(x.copyWith(foundation: spec));
    case 'SetLayers':
      final layers = List<Layer>.of(args['layers'] as List<Layer>);
      if (layers.isEmpty) return fail('至少保留一层构造');
      return ok(switch (args['group'] as String) {
        'wall' => x.copyWith(wallLayers: layers),
        'roof' => x.copyWith(roofLayers: layers),
        _ => x.copyWith(floorLayers: layers),
      });
    case 'AddIssue':
      final issue = UserIssue(
          id: args['id'] as String? ?? newId(),
          level: args['level'] as IssueLevel? ?? IssueLevel.chk,
          title: (args['title'] as String? ?? '').trim(),
          text: (args['text'] as String? ?? '').trim(),
          floorId: args['floorId'] as String?,
          areas: List.of(args['areas'] as List<(int, int, int, int)>? ?? []));
      if (issue.title.isEmpty) return fail('请填写标题');
      return ok(x.copyWith(issues: [...x.issues, issue]));
    case 'UpdateIssue' || 'DeleteIssue':
      final id = args['issueId'] as String;
      final index = x.issues.indexWhere((e) => e.id == id);
      if (index < 0) return fail('找不到要编辑的对象');
      final list = [...x.issues];
      if (kind == 'DeleteIssue') {
        list.removeAt(index);
      } else {
        final title = (args['title'] as String?)?.trim();
        if (title != null && title.isEmpty) return fail('请填写标题');
        list[index] = list[index].copyWith(
            level: args['level'] as IssueLevel?,
            title: title,
            text: (args['text'] as String?)?.trim(),
            floorId: args['floorId'] as String?,
            areas: args['areas'] as List<(int, int, int, int)>?);
      }
      return ok(x.copyWith(issues: list));
    case 'AddSleeve':
      return ok(x.copyWith(sleeves: [
        ...x.sleeves,
        Sleeve(
            id: args['id'] as String? ?? newId(),
            x: i('x')!,
            y: i('y')!,
            diameter: i('diameter') ?? 110,
            kind: args['kind'] as SleeveKind? ?? SleeveKind.sewer)
      ]));
    case 'UpdateSleeve' || 'DeleteSleeve':
      final id = args['sleeveId'] as String;
      final index = x.sleeves.indexWhere((s) => s.id == id);
      if (index < 0) return fail('找不到要编辑的对象');
      final list = [...x.sleeves];
      if (kind == 'DeleteSleeve') {
        list.removeAt(index);
      } else {
        final s = list[index];
        list[index] = Sleeve(
            id: s.id,
            x: i('x') ?? s.x,
            y: i('y') ?? s.y,
            diameter: i('diameter') ?? s.diameter,
            kind: args['kind'] as SleeveKind? ?? s.kind);
      }
      return ok(x.copyWith(sleeves: list));
    case 'SetNote':
      final key = args['key'] as String,
          value = (args['value'] as String? ?? '').trim();
      return ok(x.copyWith(
          notes: {...x.notes, key: value}..removeWhere((_, v) => v.isEmpty)));
  }
  return null;
}
