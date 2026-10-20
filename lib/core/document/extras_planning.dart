import 'dart:convert';
import 'house_extras.dart';

/// Planning content added in schema version 4: prices for the cost
/// estimate, climate for the heat-loss calculation, electrical and plumbing
/// points, the plot with its outbuildings, and the building schedule.
/// Each part is written only when it differs from its default.

enum Currency { cny, kzt }

enum FuelKind { coal, gas, electricity, wood }

enum UtilityKind { panel, socket, lightSwitch, light, vent, water, drain, radiator }

enum SiteKind {
  barn,
  bathhouse,
  garage,
  toilet,
  shed,
  greenhouse,
  well,
  septic,
  garden,
  yard,
  gate,
  custom
}

enum StageStatus { todo, doing, done }

/// A line the user adds to the estimate: quantity in hundredths.
class CostItem {
  const CostItem(
      {required this.id,
      required this.name,
      this.unit = '',
      this.quantity = 100,
      this.price = 0});
  final String id, name, unit;
  final int quantity, price;
  CostItem copyWith({String? name, String? unit, int? quantity, int? price}) =>
      CostItem(
          id: id,
          name: name ?? this.name,
          unit: unit ?? this.unit,
          quantity: quantity ?? this.quantity,
          price: price ?? this.price);
  Json toJson() => {
        'id': id,
        'name': name,
        if (unit.isNotEmpty) 'unit': unit,
        'quantity': quantity,
        'price': price,
      };
  static CostItem fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    return CostItem(
        id: r.text(m['id'], '$p/id'),
        name: r.text(m['name'], '$p/name'),
        unit: r.text(m['unit'], '$p/unit'),
        quantity: r.integer(m['quantity'], '$p/quantity', 100),
        price: r.integer(m['price'], '$p/price', 0));
  }
}

/// Unit prices and markups. Prices left out use the built-in examples of
/// [currency]; a null currency follows the interface language.
class CostSpec {
  CostSpec(
      {this.currency,
      Map<String, int> prices = const {},
      this.labourPct = 35,
      this.contingencyPct = 10,
      List<CostItem> items = const []})
      : prices = Map.unmodifiable(prices),
        items = List.unmodifiable(items);
  final Currency? currency;
  final Map<String, int> prices;
  final int labourPct, contingencyPct;
  final List<CostItem> items;

  CostSpec copyWith(
          {Currency? currency,
          Map<String, int>? prices,
          int? labourPct,
          int? contingencyPct,
          List<CostItem>? items}) =>
      CostSpec(
          currency: currency ?? this.currency,
          prices: prices ?? this.prices,
          labourPct: labourPct ?? this.labourPct,
          contingencyPct: contingencyPct ?? this.contingencyPct,
          items: items ?? this.items);

  Json toJson() => {
        if (currency != null) 'currency': currency!.name,
        if (prices.isNotEmpty)
          'prices': {
            for (final k in (prices.keys.toList()..sort())) k: prices[k]
          },
        if (labourPct != 35) 'labourPct': labourPct,
        if (contingencyPct != 10) 'contingencyPct': contingencyPct,
        if (items.isNotEmpty) 'items': [for (final i in items) i.toJson()],
      };
  bool get isDefault => toJson().isEmpty;

  static CostSpec fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    final prices = <String, int>{};
    if (m['prices'] != null)
      for (final e in r.obj(m['prices'], '$p/prices').entries)
        prices[e.key] = r.integer(e.value, '$p/prices/${e.key}', 0);
    final raw = r.list(m['items'], '$p/items');
    return CostSpec(
        currency: m['currency'] == null
            ? null
            : r.en(m['currency'], '$p/currency', Currency.values, Currency.cny),
        prices: prices,
        labourPct: r.integer(m['labourPct'], '$p/labourPct', 35),
        contingencyPct: r.integer(m['contingencyPct'], '$p/contingencyPct', 10),
        items: [
          for (var i = 0; i < raw.length; i++)
            CostItem.fromJson(raw[i], '$p/items/$i', r)
        ]);
  }
}

/// Default boiler or stove efficiency per fuel, percent.
const fuelEfficiency = {
  FuelKind.coal: 75,
  FuelKind.gas: 92,
  FuelKind.electricity: 100,
  FuelKind.wood: 70,
};

/// Climate and equipment for the heat-loss calculation. U-values and the
/// air change rate are in hundredths (110 = 1.10 W/m²K, 50 = 0.5 per hour).
class HeatSpec {
  const HeatSpec(
      {this.outdoor = -25,
      this.indoor = 20,
      this.degreeDays = 4500,
      this.airChange = 50,
      this.windowU = 110,
      this.doorU = 150,
      this.fuel = FuelKind.coal,
      this.efficiency = 75});

  /// Design temperatures, °C.
  final int outdoor, indoor;

  /// Heating degree-days, K·day.
  final int degreeDays, airChange, windowU, doorU;
  final FuelKind fuel;

  /// Boiler or stove efficiency, percent.
  final int efficiency;

  static const fields = [
    'outdoor',
    'indoor',
    'degreeDays',
    'airChange',
    'windowU',
    'doorU',
    'efficiency'
  ];

  Map<String, int> get ints => {
        'outdoor': outdoor,
        'indoor': indoor,
        'degreeDays': degreeDays,
        'airChange': airChange,
        'windowU': windowU,
        'doorU': doorU,
        'efficiency': efficiency,
      };

  HeatSpec withInt(String field, int value) {
    final m = {...ints, field: value};
    return HeatSpec(
        outdoor: m['outdoor']!,
        indoor: m['indoor']!,
        degreeDays: m['degreeDays']!,
        airChange: m['airChange']!,
        windowU: m['windowU']!,
        doorU: m['doorU']!,
        fuel: fuel,
        efficiency: m['efficiency']!);
  }

  HeatSpec withFuel(FuelKind value) => HeatSpec(
      outdoor: outdoor,
      indoor: indoor,
      degreeDays: degreeDays,
      airChange: airChange,
      windowU: windowU,
      doorU: doorU,
      fuel: value,
      efficiency: efficiency);

  Json toJson() {
    const d = HeatSpec();
    return {
      for (final e in ints.entries)
        if (e.value != d.ints[e.key]) e.key: e.value,
      if (fuel != d.fuel) 'fuel': fuel.name,
    };
  }

  bool get isDefault => toJson().isEmpty;

  static HeatSpec fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    var spec = const HeatSpec();
    for (final f in fields)
      spec = spec.withInt(f, r.integer(m[f], '$p/$f', spec.ints[f]!));
    return spec.withFuel(
        r.en(m['fuel'], '$p/fuel', FuelKind.values, FuelKind.coal));
  }

  @override
  bool operator ==(Object other) =>
      other is HeatSpec && jsonEncode(toJson()) == jsonEncode(other.toJson());
  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// An electrical or plumbing point on a floor plan (plan millimetres).
class UtilityPoint {
  const UtilityPoint(
      {required this.id,
      required this.floorId,
      required this.kind,
      required this.x,
      required this.y,
      this.label});
  final String id, floorId;
  final UtilityKind kind;
  final int x, y;
  final String? label;
  UtilityPoint copyWith(
          {int? x, int? y, UtilityKind? kind, String? label, bool clearLabel = false}) =>
      UtilityPoint(
          id: id,
          floorId: floorId,
          kind: kind ?? this.kind,
          x: x ?? this.x,
          y: y ?? this.y,
          label: clearLabel ? null : label ?? this.label);
  Json toJson() => {
        'id': id,
        'floorId': floorId,
        'kind': kind.name,
        'x': x,
        'y': y,
        if (label != null) 'label': label,
      };
  static UtilityPoint fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    return UtilityPoint(
        id: r.text(m['id'], '$p/id'),
        floorId: r.text(m['floorId'], '$p/floorId'),
        kind: r.en(m['kind'], '$p/kind', UtilityKind.values, UtilityKind.socket),
        x: r.integer(m['x'], '$p/x', 0),
        y: r.integer(m['y'], '$p/y', 0),
        label: r.optionalText(m['label'], '$p/label'));
  }
}

/// An outbuilding, area or gate on the plot (plot millimetres, lower-left
/// corner, y towards the back of the plot).
class SiteItem {
  const SiteItem(
      {required this.id,
      required this.kind,
      required this.x,
      required this.y,
      required this.width,
      required this.depth,
      this.label});
  final String id;
  final SiteKind kind;
  final int x, y, width, depth;
  final String? label;
  int get right => x + width;
  int get top => y + depth;
  SiteItem copyWith(
          {int? x,
          int? y,
          int? width,
          int? depth,
          SiteKind? kind,
          String? label,
          bool clearLabel = false}) =>
      SiteItem(
          id: id,
          kind: kind ?? this.kind,
          x: x ?? this.x,
          y: y ?? this.y,
          width: width ?? this.width,
          depth: depth ?? this.depth,
          label: clearLabel ? null : label ?? this.label);
  Json toJson() => {
        'id': id,
        'kind': kind.name,
        'x': x,
        'y': y,
        'width': width,
        'depth': depth,
        if (label != null) 'label': label,
      };
  static SiteItem fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    return SiteItem(
        id: r.text(m['id'], '$p/id'),
        kind: r.en(m['kind'], '$p/kind', SiteKind.values, SiteKind.custom),
        x: r.integer(m['x'], '$p/x', 0),
        y: r.integer(m['y'], '$p/y', 0),
        width: r.integer(m['width'], '$p/width', 0),
        depth: r.integer(m['depth'], '$p/depth', 0),
        label: r.optionalText(m['label'], '$p/label'));
  }
}

/// The plot: its size, where the house stands on it (lower-left corner of
/// the footprint), the fence and the outbuildings. The street is along the
/// bottom edge.
class SitePlan {
  SitePlan(
      {required this.width,
      required this.depth,
      required this.houseX,
      required this.houseY,
      this.fence = true,
      List<SiteItem> items = const []})
      : items = List.unmodifiable(items);
  final int width, depth, houseX, houseY;
  final bool fence;
  final List<SiteItem> items;

  SitePlan copyWith(
          {int? width,
          int? depth,
          int? houseX,
          int? houseY,
          bool? fence,
          List<SiteItem>? items}) =>
      SitePlan(
          width: width ?? this.width,
          depth: depth ?? this.depth,
          houseX: houseX ?? this.houseX,
          houseY: houseY ?? this.houseY,
          fence: fence ?? this.fence,
          items: items ?? this.items);

  Json toJson() => {
        'width': width,
        'depth': depth,
        'houseX': houseX,
        'houseY': houseY,
        'fence': fence,
        if (items.isNotEmpty) 'items': [for (final i in items) i.toJson()],
      };

  static SitePlan fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    final raw = r.list(m['items'], '$p/items');
    return SitePlan(
        width: r.integer(m['width'], '$p/width', 0),
        depth: r.integer(m['depth'], '$p/depth', 0),
        houseX: r.integer(m['houseX'], '$p/houseX', 0),
        houseY: r.integer(m['houseY'], '$p/houseY', 0),
        fence: r.flag(m['fence'], '$p/fence', true),
        items: [
          for (var i = 0; i < raw.length; i++)
            SiteItem.fromJson(raw[i], '$p/items/$i', r)
        ]);
  }
}

/// Built-in building stages, in order.
const stageKeys = [
  'prep',
  'found',
  'walls',
  'roof',
  'openings',
  'mep',
  'finish',
  'site',
  'handover'
];

/// Default duration of each built-in stage, days.
const stageDays = {
  'prep': 14,
  'found': 21,
  'walls': 30,
  'roof': 21,
  'openings': 7,
  'mep': 21,
  'finish': 45,
  'site': 14,
  'handover': 7,
};

/// One stage of the build: progress, dates, money spent and ticked checks.
/// Built-in stages use their [key] from [stageKeys]; added ones have a
/// key starting with "own-" and a [name].
class BuildStage {
  BuildStage(
      {required this.key,
      this.name = '',
      this.status = StageStatus.todo,
      this.start,
      int? days,
      this.spent = 0,
      this.note = '',
      List<int> checks = const []})
      : days = days ?? stageDays[key] ?? 14,
        checks = List.unmodifiable(checks.toSet().toList()..sort());
  final String key, name, note;
  final StageStatus status;

  /// Planned start, "YYYY-MM-DD"; null follows the previous stage.
  final String? start;
  final int days, spent;

  /// Indexes of the stage's checklist items that are done.
  final List<int> checks;
  bool get custom => !stageKeys.contains(key);

  BuildStage copyWith(
          {String? name,
          StageStatus? status,
          String? start,
          bool clearStart = false,
          int? days,
          int? spent,
          String? note,
          List<int>? checks}) =>
      BuildStage(
          key: key,
          name: name ?? this.name,
          status: status ?? this.status,
          start: clearStart ? null : start ?? this.start,
          days: days ?? this.days,
          spent: spent ?? this.spent,
          note: note ?? this.note,
          checks: checks ?? this.checks);

  Json toJson() => {
        'key': key,
        if (name.isNotEmpty) 'name': name,
        if (status != StageStatus.todo) 'status': status.name,
        if (start != null) 'start': start,
        'days': days,
        if (spent != 0) 'spent': spent,
        if (note.isNotEmpty) 'note': note,
        if (checks.isNotEmpty) 'checks': checks,
      };

  static BuildStage fromJson(Object? v, String p, JsonReader r) {
    final m = r.obj(v, p);
    final raw = r.list(m['checks'], '$p/checks');
    return BuildStage(
        key: r.text(m['key'], '$p/key'),
        name: r.text(m['name'], '$p/name'),
        status:
            r.en(m['status'], '$p/status', StageStatus.values, StageStatus.todo),
        start: r.optionalText(m['start'], '$p/start'),
        days: r.integer(m['days'], '$p/days', 14),
        spent: r.integer(m['spent'], '$p/spent', 0),
        note: r.text(m['note'], '$p/note'),
        checks: [
          for (var i = 0; i < raw.length; i++)
            r.integer(raw[i], '$p/checks/$i', 0)
        ]);
  }
}

/// The schedule before the user changes anything.
List<BuildStage> defaultSchedule() => [for (final k in stageKeys) BuildStage(key: k)];

final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Problems in the planning parts, as (path, message).
List<(String, String)> planningProblems(
    {required CostSpec cost,
    required HeatSpec heat,
    required List<UtilityPoint> utilities,
    required SitePlan? site,
    required List<BuildStage> schedule}) {
  final out = <(String, String)>[];
  for (final e in cost.prices.entries)
    if (e.value < 0 || e.value > 1000000000)
      out.add(('/extras/cost/prices/${e.key}', '单价超出范围'));
  if (cost.labourPct < 0 || cost.labourPct > 300)
    out.add(('/extras/cost/labourPct', '人工比例超出范围'));
  if (cost.contingencyPct < 0 || cost.contingencyPct > 100)
    out.add(('/extras/cost/contingencyPct', '预备费比例超出范围'));
  final itemIds = <String>{};
  for (var i = 0; i < cost.items.length; i++) {
    final item = cost.items[i];
    if (item.id.isEmpty || !itemIds.add(item.id))
      out.add(('/extras/cost/items/$i/id', '预算项 id 无效或重复'));
    if (item.quantity < 0 || item.price < 0)
      out.add(('/extras/cost/items/$i', '数量和单价不得为负'));
  }
  if (heat.outdoor < -60 || heat.outdoor > 20)
    out.add(('/extras/heat/outdoor', '室外计算温度应在 -60 到 20 °C 之间'));
  if (heat.indoor < 10 || heat.indoor > 30)
    out.add(('/extras/heat/indoor', '室内温度应在 10 到 30 °C 之间'));
  if (heat.indoor <= heat.outdoor)
    out.add(('/extras/heat/indoor', '室内温度应高于室外'));
  if (heat.degreeDays < 0 || heat.degreeDays > 15000)
    out.add(('/extras/heat/degreeDays', '采暖度日数超出范围'));
  if (heat.airChange < 0 || heat.airChange > 500)
    out.add(('/extras/heat/airChange', '换气次数超出范围'));
  if (heat.windowU <= 0 || heat.windowU > 1000)
    out.add(('/extras/heat/windowU', '窗传热系数超出范围'));
  if (heat.doorU <= 0 || heat.doorU > 1000)
    out.add(('/extras/heat/doorU', '门传热系数超出范围'));
  if (heat.efficiency < 10 || heat.efficiency > 110)
    out.add(('/extras/heat/efficiency', '效率应在 10% 到 110% 之间'));
  final utilityIds = <String>{};
  for (var i = 0; i < utilities.length; i++) {
    final u = utilities[i];
    if (u.id.isEmpty || !utilityIds.add(u.id))
      out.add(('/extras/utilities/$i/id', '点位 id 无效或重复'));
    if (u.x.abs() > 200000 || u.y.abs() > 200000)
      out.add(('/extras/utilities/$i', '点位位置超出范围'));
  }
  if (site != null) {
    if (site.width < 3000 ||
        site.depth < 3000 ||
        site.width > 500000 ||
        site.depth > 500000)
      out.add(('/extras/site', '宅基地长宽应在 3 到 500 米之间'));
    if (site.houseX.abs() > 500000 || site.houseY.abs() > 500000)
      out.add(('/extras/site', '房屋位置超出范围'));
    final ids = <String>{};
    for (var i = 0; i < site.items.length; i++) {
      final item = site.items[i];
      if (item.id.isEmpty || !ids.add(item.id))
        out.add(('/extras/site/items/$i/id', '附属设施 id 无效或重复'));
      if (item.width <= 0 ||
          item.depth <= 0 ||
          item.width > 200000 ||
          item.depth > 200000)
        out.add(('/extras/site/items/$i', '附属设施尺寸超出范围'));
      if (item.x.abs() > 500000 || item.y.abs() > 500000)
        out.add(('/extras/site/items/$i', '附属设施位置超出范围'));
    }
  }
  final keys = <String>{};
  for (var i = 0; i < schedule.length; i++) {
    final s = schedule[i];
    if (s.key.isEmpty || !keys.add(s.key))
      out.add(('/extras/schedule/$i/key', '施工阶段重复'));
    if (s.days < 1 || s.days > 3650)
      out.add(('/extras/schedule/$i/days', '工期应在 1 到 3650 天之间'));
    if (s.spent < 0) out.add(('/extras/schedule/$i/spent', '花费不得为负'));
    if (s.start != null && !_date.hasMatch(s.start!))
      out.add(('/extras/schedule/$i/start', '日期格式应为 YYYY-MM-DD'));
    if (s.checks.any((c) => c < 0 || c > 99))
      out.add(('/extras/schedule/$i/checks', '检查项编号无效'));
  }
  return out;
}
