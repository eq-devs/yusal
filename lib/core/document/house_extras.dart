import 'dart:convert';

/// Content beyond walls, rooms and openings: furniture, room notes,
/// construction specs, user issues and pipe sleeves. Saved in an optional
/// `extras` section (schema version 3) so older files keep their bytes.

enum FurnitureKind {
  bed,
  singleBed,
  wardrobe,
  table,
  diningTable,
  chair,
  sofa,
  desk,
  tvStand,
  shelf,
  rug,
  alasha,
  wallRug,
  korpe,
  cushion,
  dastarkhan,
  sandyq,
  bench,
  hooks,
  counter,
  stove,
  sink,
  fridge,
  pantry,
  bathtub,
  shower,
  toilet,
  basin,
  washer,
  boiler,
  shoeCabinet,
  terrace,
  porch,
  custom
}

enum LayerMaterial { conc, block, ins, earth, sand, plaster, metal, wood, film, gyp }

enum IssueLevel { crit, warn, chk, ok }

enum SleeveKind { sewer, water, power, gas }

typedef Json = Map<String, Object?>;

/// Typed reading of an untrusted JSON tree; problems go to [err].
class JsonReader {
  JsonReader(this.err);
  final void Function(String code, String path, String message) err;
  Json obj(Object? v, String p) {
    if (v is Map<String, Object?>) return v;
    if (v is Map) return v.cast<String, Object?>();
    err('WRONG_TYPE', p, '应为对象');
    return const {};
  }

  List<Object?> list(Object? v, String p) {
    if (v == null) return const [];
    if (v is List) return v;
    err('WRONG_TYPE', p, '应为数组');
    return const [];
  }

  int integer(Object? v, String p, int fallback) {
    if (v == null) return fallback;
    if (v is int && v.abs() <= 2147483647) return v;
    err('NOT_INTEGER', p, '必须是整数');
    return fallback;
  }

  String text(Object? v, String p, [String fallback = '']) {
    if (v == null) return fallback;
    if (v is String) return v;
    err('WRONG_TYPE', p, '应为字符串');
    return fallback;
  }

  String? optionalText(Object? v, String p) =>
      v == null ? null : text(v, p);

  bool flag(Object? v, String p, bool fallback) {
    if (v == null) return fallback;
    if (v is bool) return v;
    err('WRONG_TYPE', p, '应为布尔值');
    return fallback;
  }

  T en<T extends Enum>(Object? v, String p, List<T> values, T fallback) {
    if (v == null) return fallback;
    for (final x in values) if (x.name == v) return x;
    err('UNKNOWN_ENUM', p, '未知枚举值');
    return fallback;
  }
}

class FurnitureItem {
  const FurnitureItem({
    required this.id,
    required this.floorId,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.depth,
    required this.height,
    this.elevation = 0,
    this.label,
    this.variant = 0,
  });

  /// Lower-left corner in plan millimetres (y grows to the top of the plan).
  final int x, y, width, depth, height, elevation, variant;
  final String id, floorId;
  final FurnitureKind kind;
  final String? label;
  int get right => x + width;
  int get top => y + depth;

  FurnitureItem copyWith(
          {int? x,
          int? y,
          int? width,
          int? depth,
          int? height,
          int? elevation,
          int? variant,
          FurnitureKind? kind,
          String? floorId,
          String? label,
          bool clearLabel = false}) =>
      FurnitureItem(
          id: id,
          floorId: floorId ?? this.floorId,
          kind: kind ?? this.kind,
          x: x ?? this.x,
          y: y ?? this.y,
          width: width ?? this.width,
          depth: depth ?? this.depth,
          height: height ?? this.height,
          elevation: elevation ?? this.elevation,
          variant: variant ?? this.variant,
          label: clearLabel ? null : label ?? this.label);

  Json toJson() => {
        'id': id,
        'floorId': floorId,
        'kind': kind.name,
        'x': x,
        'y': y,
        'width': width,
        'depth': depth,
        'height': height,
        if (elevation != 0) 'elevation': elevation,
        if (variant != 0) 'variant': variant,
        if (label != null) 'label': label,
      };

  static FurnitureItem fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    return FurnitureItem(
        id: r.text(m['id'], '$p/id'),
        floorId: r.text(m['floorId'], '$p/floorId'),
        kind: r.en(m['kind'], '$p/kind', FurnitureKind.values,
            FurnitureKind.custom),
        x: r.integer(m['x'], '$p/x', 0),
        y: r.integer(m['y'], '$p/y', 0),
        width: r.integer(m['width'], '$p/width', 0),
        depth: r.integer(m['depth'], '$p/depth', 0),
        height: r.integer(m['height'], '$p/height', 0),
        elevation: r.integer(m['elevation'], '$p/elevation', 0),
        variant: r.integer(m['variant'], '$p/variant', 0),
        label: r.optionalText(m['label'], '$p/label'));
  }
}

/// What the user writes about a room: a note and the area printed on the
/// original drawing (hundredths of a square metre).
class RoomInfo {
  const RoomInfo({this.note = '', this.labelArea});
  final String note;
  final int? labelArea;
  bool get isEmpty => note.isEmpty && labelArea == null;
  Json toJson() => {
        if (note.isNotEmpty) 'note': note,
        if (labelArea != null) 'labelArea': labelArea,
      };
  static RoomInfo fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    final area = m['labelArea'];
    return RoomInfo(
        note: r.text(m['note'], '$p/note'),
        labelArea: area == null ? null : r.integer(area, '$p/labelArea', 0));
  }
}

/// Strip foundation in the drafting-table drawing: concrete section, rebar,
/// cushion and the rule that decides which walls are load-bearing.
class FoundationSpec {
  const FoundationSpec({
    this.width = 450,
    this.height = 800,
    this.plinth = 300,
    this.cushion = 300,
    this.cushionExtra = 100,
    this.cover = 50,
    this.topBars = 3,
    this.bottomBars = 3,
    this.barDia = 12,
    this.stirrupDia = 8,
    this.stirrupStep = 300,
    this.partitions = false,
    this.partitionWidth = 300,
    this.partitionHeight = 600,
    this.partitionBars = 4,
    this.partitionBarDia = 10,
    this.partitionStirrupDia = 6,
    this.bearingMin = 240,
    this.concrete = 'B20 (M250) · W6 · F150',
  });
  final int width,
      height,
      plinth,
      cushion,
      cushionExtra,
      cover,
      topBars,
      bottomBars,
      barDia,
      stirrupDia,
      stirrupStep,
      partitionWidth,
      partitionHeight,
      partitionBars,
      partitionBarDia,
      partitionStirrupDia,
      bearingMin;

  /// Whether partition walls also get (smaller) strips.
  final bool partitions;
  final String concrete;

  static const fieldsInt = [
    'width',
    'height',
    'plinth',
    'cushion',
    'cushionExtra',
    'cover',
    'topBars',
    'bottomBars',
    'barDia',
    'stirrupDia',
    'stirrupStep',
    'partitionWidth',
    'partitionHeight',
    'partitionBars',
    'partitionBarDia',
    'partitionStirrupDia',
    'bearingMin'
  ];

  Map<String, int> get ints => {
        'width': width,
        'height': height,
        'plinth': plinth,
        'cushion': cushion,
        'cushionExtra': cushionExtra,
        'cover': cover,
        'topBars': topBars,
        'bottomBars': bottomBars,
        'barDia': barDia,
        'stirrupDia': stirrupDia,
        'stirrupStep': stirrupStep,
        'partitionWidth': partitionWidth,
        'partitionHeight': partitionHeight,
        'partitionBars': partitionBars,
        'partitionBarDia': partitionBarDia,
        'partitionStirrupDia': partitionStirrupDia,
        'bearingMin': bearingMin,
      };

  FoundationSpec withInt(String field, int value) {
    final m = {...ints, field: value};
    return FoundationSpec(
        width: m['width']!,
        height: m['height']!,
        plinth: m['plinth']!,
        cushion: m['cushion']!,
        cushionExtra: m['cushionExtra']!,
        cover: m['cover']!,
        topBars: m['topBars']!,
        bottomBars: m['bottomBars']!,
        barDia: m['barDia']!,
        stirrupDia: m['stirrupDia']!,
        stirrupStep: m['stirrupStep']!,
        partitions: partitions,
        partitionWidth: m['partitionWidth']!,
        partitionHeight: m['partitionHeight']!,
        partitionBars: m['partitionBars']!,
        partitionBarDia: m['partitionBarDia']!,
        partitionStirrupDia: m['partitionStirrupDia']!,
        bearingMin: m['bearingMin']!,
        concrete: concrete);
  }

  FoundationSpec copyWith({bool? partitions, String? concrete}) {
    final base = withInt('width', width);
    return FoundationSpec(
        width: base.width,
        height: base.height,
        plinth: base.plinth,
        cushion: base.cushion,
        cushionExtra: base.cushionExtra,
        cover: base.cover,
        topBars: base.topBars,
        bottomBars: base.bottomBars,
        barDia: base.barDia,
        stirrupDia: base.stirrupDia,
        stirrupStep: base.stirrupStep,
        partitions: partitions ?? this.partitions,
        partitionWidth: base.partitionWidth,
        partitionHeight: base.partitionHeight,
        partitionBars: base.partitionBars,
        partitionBarDia: base.partitionBarDia,
        partitionStirrupDia: base.partitionStirrupDia,
        bearingMin: base.bearingMin,
        concrete: concrete ?? this.concrete);
  }

  Json toJson() => {
        ...ints,
        'partitions': partitions,
        'concrete': concrete,
      };

  static FoundationSpec fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    var spec = const FoundationSpec();
    for (final f in fieldsInt)
      spec = spec.withInt(f, r.integer(m[f], '$p/$f', spec.ints[f]!));
    return spec.copyWith(
        partitions: r.flag(m['partitions'], '$p/partitions', false),
        concrete: r.text(m['concrete'], '$p/concrete', spec.concrete));
  }

  @override
  bool operator ==(Object other) =>
      other is FoundationSpec &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());
  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// One layer of a wall, roof or floor build-up, outside to inside / top down.
class Layer {
  const Layer(this.name, this.nameKk, this.thickness, this.material);
  final String name, nameKk;
  final int thickness;
  final LayerMaterial material;
  Json toJson() => {
        'name': name,
        'nameKk': nameKk,
        'thickness': thickness,
        'material': material.name,
      };
  static Layer fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    return Layer(
        r.text(m['name'], '$p/name'),
        r.text(m['nameKk'], '$p/nameKk'),
        r.integer(m['thickness'], '$p/thickness', 0),
        r.en(m['material'], '$p/material', LayerMaterial.values,
            LayerMaterial.plaster));
  }
}

const defaultWallLayers = [
  Layer('外饰面 (薄抹灰/装饰板)', 'Сыртқы әрлеу (жұқа сылақ/панель)', 15,
      LayerMaterial.plaster),
  Layer('岩棉保温板', 'Минералды мақта жылытқыш', 100, LayerMaterial.ins),
  Layer('加气混凝土砌块 D500', 'Газоблок D500', 270, LayerMaterial.block),
  Layer('内墙抹灰', 'Ішкі сылақ', 15, LayerMaterial.plaster),
];

const defaultRoofLayers = [
  Layer('防水卷材 2 层 (SBS 改性沥青) 或 PVC 膜',
      'Гидрооқшау: 2 қабат битумды мембрана немесе ПВХ', 8, LayerMaterial.metal),
  Layer('水泥砂浆找平 (配筋网)', 'Цемент тегістеу (тормен)', 40,
      LayerMaterial.plaster),
  Layer('找坡保温 (楔形 XPS / 陶粒) 30–150',
      'Еңіс жасайтын жылытқыш (сына XPS / керамзит) 30–150', 60,
      LayerMaterial.sand),
  Layer('高密度岩棉板', 'Тығыз минералды мақта плита', 150, LayerMaterial.ins),
  Layer('隔汽层', 'Бу оқшаулағыш', 2, LayerMaterial.film),
  Layer('钢筋混凝土屋面板 (现浇或空心板)', 'Темірбетон жабын плитасы (монолит немесе ПК)',
      220, LayerMaterial.conc),
  Layer('顶棚抹灰 / 吊顶', 'Төбе сылағы / аспалы төбе', 15, LayerMaterial.gyp),
];

const defaultFloorLayers = [
  Layer('地板 / 地砖', 'Ламинат / плитка', 12, LayerMaterial.wood),
  Layer('找平层 (可埋地暖管)', 'Тегістеу (жылы еден)', 50, LayerMaterial.plaster),
  Layer('钢筋混凝土板', 'Темірбетон плита', 100, LayerMaterial.conc),
  Layer('XPS 挤塑板', 'XPS жылытқыш', 100, LayerMaterial.ins),
  Layer('防水卷材', 'Гидрооқшау', 2, LayerMaterial.film),
  Layer('砂垫层', 'Құм төсеме', 100, LayerMaterial.sand),
  Layer('碎石垫层', 'Қиыршық тас', 200, LayerMaterial.sand),
  Layer('素土夯实', 'Тығыздалған топырақ', 0, LayerMaterial.earth),
];

/// A problem or remark the user writes down, optionally with plan areas to
/// highlight (millimetres, x0 < x1, y0 < y1).
class UserIssue {
  const UserIssue(
      {required this.id,
      required this.level,
      required this.title,
      this.text = '',
      this.floorId,
      this.areas = const []});
  final String id, title, text;
  final IssueLevel level;
  final String? floorId;
  final List<(int, int, int, int)> areas;
  UserIssue copyWith(
          {IssueLevel? level,
          String? title,
          String? text,
          String? floorId,
          List<(int, int, int, int)>? areas}) =>
      UserIssue(
          id: id,
          level: level ?? this.level,
          title: title ?? this.title,
          text: text ?? this.text,
          floorId: floorId ?? this.floorId,
          areas: areas ?? this.areas);
  Json toJson() => {
        'id': id,
        'level': level.name,
        'title': title,
        if (text.isNotEmpty) 'text': text,
        if (floorId != null) 'floorId': floorId,
        if (areas.isNotEmpty)
          'areas': [
            for (final a in areas) [a.$1, a.$2, a.$3, a.$4]
          ],
      };
  static UserIssue fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    final areas = <(int, int, int, int)>[];
    final raw = r.list(m['areas'], '$p/areas');
    for (var i = 0; i < raw.length; i++) {
      final a = r.list(raw[i], '$p/areas/$i');
      if (a.length != 4) {
        r.err('WRONG_SHAPE', '$p/areas/$i', '区域应为 4 个整数');
        continue;
      }
      final n = [for (var k = 0; k < 4; k++) r.integer(a[k], '$p/areas/$i/$k', 0)];
      areas.add((n[0], n[1], n[2], n[3]));
    }
    return UserIssue(
        id: r.text(m['id'], '$p/id'),
        level: r.en(m['level'], '$p/level', IssueLevel.values, IssueLevel.chk),
        title: r.text(m['title'], '$p/title'),
        text: r.text(m['text'], '$p/text'),
        floorId: r.optionalText(m['floorId'], '$p/floorId'),
        areas: areas);
  }
}

/// A pipe or cable sleeve through the ground-floor foundation.
class Sleeve {
  const Sleeve(
      {required this.id,
      required this.x,
      required this.y,
      required this.diameter,
      required this.kind});
  final String id;
  final int x, y, diameter;
  final SleeveKind kind;
  Json toJson() =>
      {'id': id, 'x': x, 'y': y, 'diameter': diameter, 'kind': kind.name};
  static Sleeve fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    return Sleeve(
        id: r.text(m['id'], '$p/id'),
        x: r.integer(m['x'], '$p/x', 0),
        y: r.integer(m['y'], '$p/y', 0),
        diameter: r.integer(m['diameter'], '$p/diameter', 110),
        kind: r.en(m['kind'], '$p/kind', SleeveKind.values, SleeveKind.sewer));
  }
}

class HouseExtras {
  HouseExtras({
    List<FurnitureItem> furniture = const [],
    Map<String, RoomInfo> rooms = const {},
    Map<String, String> openingLabels = const {},
    this.foundation = const FoundationSpec(),
    List<Layer> wallLayers = defaultWallLayers,
    List<Layer> roofLayers = defaultRoofLayers,
    List<Layer> floorLayers = defaultFloorLayers,
    List<UserIssue> issues = const [],
    List<Sleeve> sleeves = const [],
    Map<String, String> notes = const {},
  })  : furniture = List.unmodifiable(furniture),
        rooms = Map.unmodifiable(rooms),
        openingLabels = Map.unmodifiable(openingLabels),
        wallLayers = List.unmodifiable(wallLayers),
        roofLayers = List.unmodifiable(roofLayers),
        floorLayers = List.unmodifiable(floorLayers),
        issues = List.unmodifiable(issues),
        sleeves = List.unmodifiable(sleeves),
        notes = Map.unmodifiable(notes);

  static final empty = HouseExtras();

  final List<FurnitureItem> furniture;
  final Map<String, RoomInfo> rooms;
  final Map<String, String> openingLabels;
  final FoundationSpec foundation;
  final List<Layer> wallLayers, roofLayers, floorLayers;
  final List<UserIssue> issues;
  final List<Sleeve> sleeves;

  /// Free text per page section, keyed by section name.
  final Map<String, String> notes;

  HouseExtras copyWith({
    List<FurnitureItem>? furniture,
    Map<String, RoomInfo>? rooms,
    Map<String, String>? openingLabels,
    FoundationSpec? foundation,
    List<Layer>? wallLayers,
    List<Layer>? roofLayers,
    List<Layer>? floorLayers,
    List<UserIssue>? issues,
    List<Sleeve>? sleeves,
    Map<String, String>? notes,
  }) =>
      HouseExtras(
          furniture: furniture ?? this.furniture,
          rooms: rooms ?? this.rooms,
          openingLabels: openingLabels ?? this.openingLabels,
          foundation: foundation ?? this.foundation,
          wallLayers: wallLayers ?? this.wallLayers,
          roofLayers: roofLayers ?? this.roofLayers,
          floorLayers: floorLayers ?? this.floorLayers,
          issues: issues ?? this.issues,
          sleeves: sleeves ?? this.sleeves,
          notes: notes ?? this.notes);

  /// Drop references to floors, rooms and openings that no longer exist.
  HouseExtras pruned(
      Set<String> floorIds, Set<String> roomIds, Set<String> openingIds) {
    final f = furniture.where((i) => floorIds.contains(i.floorId)).toList(),
        r = {
          for (final e in rooms.entries)
            if (roomIds.contains(e.key) && !e.value.isEmpty) e.key: e.value
        },
        o = {
          for (final e in openingLabels.entries)
            if (openingIds.contains(e.key) && e.value.isNotEmpty) e.key: e.value
        },
        i = [
          for (final x in issues)
            x.floorId == null || floorIds.contains(x.floorId)
                ? x
                : UserIssue(
                    id: x.id,
                    level: x.level,
                    title: x.title,
                    text: x.text,
                    areas: x.areas)
        ];
    if (f.length == furniture.length &&
        r.length == rooms.length &&
        o.length == openingLabels.length &&
        !issues.any((x) => x.floorId != null && !floorIds.contains(x.floorId)))
      return this;
    return copyWith(furniture: f, rooms: r, openingLabels: o, issues: i);
  }

  Json toJson() {
    String layersKey(List<Layer> l) => jsonEncode([for (final x in l) x.toJson()]);
    return {
      if (furniture.isNotEmpty)
        'furniture': [for (final f in furniture) f.toJson()],
      if (rooms.isNotEmpty)
        'rooms': {
          for (final k in (rooms.keys.toList()..sort())) k: rooms[k]!.toJson()
        },
      if (openingLabels.isNotEmpty)
        'openingLabels': {
          for (final k in (openingLabels.keys.toList()..sort()))
            k: openingLabels[k]
        },
      if (foundation != const FoundationSpec())
        'foundation': foundation.toJson(),
      if (layersKey(wallLayers) != layersKey(defaultWallLayers))
        'wallLayers': [for (final l in wallLayers) l.toJson()],
      if (layersKey(roofLayers) != layersKey(defaultRoofLayers))
        'roofLayers': [for (final l in roofLayers) l.toJson()],
      if (layersKey(floorLayers) != layersKey(defaultFloorLayers))
        'floorLayers': [for (final l in floorLayers) l.toJson()],
      if (issues.isNotEmpty) 'issues': [for (final i in issues) i.toJson()],
      if (sleeves.isNotEmpty) 'sleeves': [for (final s in sleeves) s.toJson()],
      if (notes.isNotEmpty)
        'notes': {
          for (final k in (notes.keys.toList()..sort())) k: notes[k]
        },
    };
  }

  late final String _key = jsonEncode(toJson());
  bool get isEmpty => _key == '{}';

  static HouseExtras fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    const known = {
      'furniture',
      'rooms',
      'openingLabels',
      'foundation',
      'wallLayers',
      'roofLayers',
      'floorLayers',
      'issues',
      'sleeves',
      'notes'
    };
    for (final k in m.keys)
      if (!known.contains(k)) r.err('UNKNOWN_FIELD', '$p/$k', '未知字段 $k');
    List<T> items<T>(String key, T Function(Object?, String, JsonReader) f) {
      final raw = r.list(m[key], '$p/$key');
      return [for (var i = 0; i < raw.length; i++) f(raw[i], '$p/$key/$i', r)];
    }

    Map<String, T> keyed<T>(String key, T Function(Object?, String) f) {
      if (m[key] == null) return const {};
      final raw = r.obj(m[key], '$p/$key');
      return {for (final e in raw.entries) e.key: f(e.value, '$p/$key/${e.key}')};
    }

    return HouseExtras(
        furniture: items('furniture', FurnitureItem.fromJson),
        rooms: keyed('rooms', (v, path) => RoomInfo.fromJson(v, path, r)),
        openingLabels: keyed('openingLabels', (v, path) => r.text(v, path)),
        foundation: m['foundation'] == null
            ? const FoundationSpec()
            : FoundationSpec.fromJson(m['foundation'], '$p/foundation', r),
        wallLayers: m['wallLayers'] == null
            ? defaultWallLayers
            : items('wallLayers', Layer.fromJson),
        roofLayers: m['roofLayers'] == null
            ? defaultRoofLayers
            : items('roofLayers', Layer.fromJson),
        floorLayers: m['floorLayers'] == null
            ? defaultFloorLayers
            : items('floorLayers', Layer.fromJson),
        issues: items('issues', UserIssue.fromJson),
        sleeves: items('sleeves', Sleeve.fromJson),
        notes: keyed('notes', (v, path) => r.text(v, path)));
  }

  /// Structural problems; references to missing objects are pruned instead.
  List<(String, String)> problems() {
    final out = <(String, String)>[];
    final ids = <String>{};
    for (var i = 0; i < furniture.length; i++) {
      final f = furniture[i];
      if (f.id.isEmpty || !ids.add(f.id))
        out.add(('/extras/furniture/$i/id', '家具 id 无效或重复'));
      if (f.width <= 0 || f.depth <= 0 || f.height <= 0)
        out.add(('/extras/furniture/$i', '家具尺寸必须大于零'));
      if (f.width > 50000 || f.depth > 50000 || f.height > 20000)
        out.add(('/extras/furniture/$i', '家具尺寸过大'));
      if (f.x.abs() > 200000 || f.y.abs() > 200000)
        out.add(('/extras/furniture/$i', '家具位置超出范围'));
      if (f.elevation < 0 || f.elevation > 10000)
        out.add(('/extras/furniture/$i/elevation', '离地高度超出范围'));
    }
    for (final e in rooms.entries)
      if ((e.value.labelArea ?? 0) < 0)
        out.add(('/extras/rooms/${e.key}/labelArea', '标注面积不得为负'));
    final f = foundation;
    for (final e in f.ints.entries)
      if (e.value < 0 || e.value > 5000)
        out.add(('/extras/foundation/${e.key}', '基础参数超出范围'));
    if (f.width <= 0 || f.height <= 0 || f.stirrupStep <= 0)
      out.add(('/extras/foundation', '基础宽、高和箍筋间距必须大于零'));
    for (final (key, layers) in [
      ('wallLayers', wallLayers),
      ('roofLayers', roofLayers),
      ('floorLayers', floorLayers)
    ])
      for (var i = 0; i < layers.length; i++)
        if (layers[i].thickness < 0 || layers[i].thickness > 5000)
          out.add(('/extras/$key/$i/thickness', '层厚超出范围'));
    final issueIds = <String>{};
    for (var i = 0; i < issues.length; i++) {
      if (issues[i].id.isEmpty || !issueIds.add(issues[i].id))
        out.add(('/extras/issues/$i/id', '问题 id 无效或重复'));
      for (final a in issues[i].areas)
        if (a.$1 > a.$3 || a.$2 > a.$4)
          out.add(('/extras/issues/$i/areas', '区域坐标顺序错误'));
    }
    final sleeveIds = <String>{};
    for (var i = 0; i < sleeves.length; i++) {
      if (sleeves[i].id.isEmpty || !sleeveIds.add(sleeves[i].id))
        out.add(('/extras/sleeves/$i/id', '套管 id 无效或重复'));
      if (sleeves[i].diameter <= 0 || sleeves[i].diameter > 1000)
        out.add(('/extras/sleeves/$i/diameter', '套管直径超出范围'));
    }
    return out;
  }

  @override
  bool operator ==(Object other) => other is HouseExtras && other._key == _key;
  @override
  int get hashCode => _key.hashCode;
}
