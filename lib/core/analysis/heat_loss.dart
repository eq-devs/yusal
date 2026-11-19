import 'dart:math' as math;
import '../document/house_document.dart';
import '../geometry/derived_house.dart';
import '../geometry/floor_base.dart';
import '../checks/construction_checks.dart';
import 'house_analysis.dart';

/// Steady-state heat loss at the design temperature, after the usual
/// hand method: U·A·ΔT through each part of the envelope plus air change,
/// the ground floor by EN ISO 13370 (simplified). Internal and solar gains
/// are left out, so the figures err on the warm side. Pure Dart; W, m, m².

/// Surface resistances, m²K/W: inside for walls, roofs (heat up) and
/// floors (heat down), and outside.
const rsiWall = 0.13, rsiRoof = 0.10, rsiFloor = 0.17, rse = 0.04;

/// Thermal conductivity of the ground, W/(m·K).
const groundLambda = 2.0;

/// Heat per unit of fuel, kWh: coal and wood per kg, gas per m³.
const fuelEnergy = {
  FuelKind.coal: 5.5,
  FuelKind.gas: 9.3,
  FuelKind.electricity: 1.0,
  FuelKind.wood: 4.0,
};

/// Usual boiler sizes, kW.
const boilerSizes = [6, 9, 12, 16, 20, 24, 28, 32, 40, 50, 60, 80, 100, 150];

/// Heat output of one radiator section, W.
const radiatorSection = 150.0;

/// Thermal resistance of [layers], m²K/W, leaving out the ground.
double layersResistance(List<Layer> layers) => layers
    .where((l) => l.thickness > 0 && l.material != LayerMaterial.earth)
    .fold(0.0, (r, l) => r + l.thickness / l.conductivity);

double wallU(List<Layer> layers) =>
    1 / (rsiWall + layersResistance(layers) + rse);

double roofU(List<Layer> layers) =>
    1 / (rsiRoof + layersResistance(layers) + rse);

/// Ground floor slab: [area] m², exposed [perimeter] m, walls [wall] m.
double groundFloorU(List<Layer> layers, double area, double perimeter,
    double wall) {
  if (area <= 0 || perimeter <= 0) return 0;
  final b = area / (0.5 * perimeter);
  final dt = wall + groundLambda * (rsiFloor + layersResistance(layers) + rse);
  return dt < b
      ? 2 * groundLambda / (math.pi * b + dt) * math.log(math.pi * b / dt + 1)
      : groundLambda / (0.457 * b + dt);
}

/// Loss of one space at the design temperature, W.
class SpaceHeat {
  const SpaceHeat(
      {required this.id,
      required this.floorIndex,
      required this.area,
      required this.walls,
      required this.windows,
      required this.doors,
      required this.roof,
      required this.floor,
      required this.air});

  /// Room, stair or '' for undivided space.
  final String id;
  final int floorIndex;

  /// Floor area, m².
  final double area;
  final double walls, windows, doors, roof, floor, air;
  double get total => walls + windows + doors + roof + floor + air;

  /// Aluminium radiator sections to cover the loss.
  int get sections => total <= 0 ? 0 : (total / radiatorSection).ceil();
}

class HeatLoss {
  const HeatLoss(
      {required this.spec,
      required this.wallU,
      required this.roofU,
      required this.floorU,
      required this.spaces,
      required this.wallArea,
      required this.windowArea,
      required this.doorArea,
      required this.roofArea,
      required this.floorArea,
      required this.volume});
  final HeatSpec spec;
  final double wallU, roofU, floorU;
  final List<SpaceHeat> spaces;

  /// Envelope areas, m², and the heated volume, m³.
  final double wallArea, windowArea, doorArea, roofArea, floorArea, volume;

  double get windowU => spec.windowU / 100;
  double get doorU => spec.doorU / 100;
  double get deltaT => (spec.indoor - spec.outdoor).toDouble();
  double _sum(double Function(SpaceHeat s) f) =>
      spaces.fold(0.0, (t, s) => t + f(s));
  double get walls => _sum((s) => s.walls);
  double get windows => _sum((s) => s.windows);
  double get doors => _sum((s) => s.doors);
  double get roof => _sum((s) => s.roof);
  double get floor => _sum((s) => s.floor);
  double get air => _sum((s) => s.air);

  /// Design heat load, W.
  double get total => walls + windows + doors + roof + floor + air;

  /// Heated floor area over all floors, m².
  double get heatedArea => _sum((s) => s.area);
  double get perArea => heatedArea <= 0 ? 0 : total / heatedArea;

  /// Smallest usual boiler covering the load with 15% to spare, kW.
  int get boilerKw {
    final need = total * 1.15 / 1000;
    return boilerSizes.firstWhere((s) => s >= need,
        orElse: () => (need / 10).ceil() * 10);
  }

  /// Heat needed over a season, kWh, from the degree-days.
  double get seasonKwh =>
      deltaT <= 0 ? 0 : total / deltaT * spec.degreeDays * 24 / 1000;

  /// Fuel for a season: tonnes of coal or wood, m³ of gas or kWh.
  double get fuel {
    final kwh = seasonKwh / (spec.efficiency / 100) / fuelEnergy[spec.fuel]!;
    return switch (spec.fuel) {
      FuelKind.coal || FuelKind.wood => kwh / 1000,
      _ => kwh,
    };
  }
}

/// Cells of each owner (room, stair, or '' when undivided) and their area.
Map<String, double> _ownerAreas(FloorBase base) {
  final out = <String, double>{};
  for (final e in base.owners.entries) {
    final c = e.key;
    if (base.outside.contains(c)) continue;
    final a = (base.axes.v[c.i + 1].pos - base.axes.v[c.i].pos) *
        (base.axes.h[c.j + 1].pos - base.axes.h[c.j].pos) /
        1e6;
    out[e.value ?? ''] = (out[e.value ?? ''] ?? 0) + a;
  }
  return out;
}

HeatLoss heatLoss(HouseDocument doc, DerivedHouse derived) {
  final x = doc.extras, spec = x.heat;
  final dT = (spec.indoor - spec.outdoor).toDouble();
  final uw = wallU(x.wallLayers), ur = roofU(x.roofLayers);
  final ground = derived.floors.first.base;
  var groundArea = 0.0, perimeter = 0.0;
  for (final a in _ownerAreas(ground).values) groundArea += a;
  for (final e in ground.edges.where((e) => e.kind == 'exterior'))
    perimeter += (e.end.pos - e.start.pos) / 1000;
  final uf = groundFloorU(x.floorLayers, groundArea, perimeter,
      doc.defaults.outerWallThickness / 1000);
  final uWin = spec.windowU / 100, uDoor = spec.doorU / 100;
  final airFactor = 0.34 * spec.airChange / 100;
  final spaces = <SpaceHeat>[];
  var wallArea = 0.0, windowArea = 0.0, doorArea = 0.0, volume = 0.0;
  final top = doc.floors.length - 1;
  for (var f = 0; f < doc.floors.length; f++) {
    final g = derived.floors[f], base = g.base;
    final h = doc.floors[f].height / 1000;
    final clear = (doc.floors[f].height - doc.defaults.slabThickness) / 1000;
    final areas = _ownerAreas(base);
    final outside = <String, double>{};
    for (final e in base.edges.where((e) => e.kind == 'exterior')) {
      // The building's side of the outline.
      final cell = e.negative == null || base.outside.contains(e.negative)
          ? e.positive
          : e.negative;
      final owner = base.owners[cell] ?? '';
      outside[owner] = (outside[owner] ?? 0) + (e.end.pos - e.start.pos) / 1000;
    }
    final glass = <String, double>{}, doors = <String, double>{};
    for (final p in g.openings) {
      if (p.status != 'ok' || p.host?.kind != 'exterior') continue;
      final (neg, pos) = roomsBeside(p, base);
      final owner = neg ?? pos ?? '';
      final a = p.opening.width * p.opening.height / 1e6;
      if (p.opening.kind == OpeningKind.door)
        doors[owner] = (doors[owner] ?? 0) + a;
      else
        glass[owner] = (glass[owner] ?? 0) + a;
    }
    for (final id in {...areas.keys, ...outside.keys}) {
      final area = areas[id] ?? 0;
      final win = glass[id] ?? 0, door = doors[id] ?? 0;
      final wall = math.max(0.0, (outside[id] ?? 0) * h - win - door);
      wallArea += wall;
      windowArea += win;
      doorArea += door;
      volume += area * clear;
      spaces.add(SpaceHeat(
          id: id,
          floorIndex: f,
          area: area,
          walls: uw * wall * dT,
          windows: uWin * win * dT,
          doors: uDoor * door * dT,
          roof: f == top ? ur * area * dT : 0,
          floor: f == 0 ? uf * area * dT : 0,
          air: airFactor * area * clear * dT));
    }
  }
  final topArea = _ownerAreas(derived.floors.last.base)
      .values
      .fold(0.0, (s, a) => s + a);
  return HeatLoss(
      spec: spec,
      wallU: uw,
      roofU: ur,
      floorU: uf,
      spaces: List.unmodifiable(spaces),
      wallArea: wallArea,
      windowArea: windowArea,
      doorArea: doorArea,
      roofArea: topArea,
      floorArea: groundArea,
      volume: volume);
}

/// Advice on the envelope for the issue list.
List<ConstructionIssue> heatChecks(HouseDocument doc, HeatLoss loss) {
  final out = <ConstructionIssue>[];
  String u(double v) => v.toStringAsFixed(2);
  if (loss.wallU > 0.40)
    out.add(ConstructionIssue(
        'H01',
        IssueLevel.warn,
        ('外墙保温偏弱', 'Сыртқы қабырға жылуы әлсіз', 'Слабое утепление наружных стен'),
        (
          '外墙传热系数 U = ${u(loss.wallU)} W/(m²·K)，寒冷地区宜不大于 0.40，严寒地区 0.30 左右。加厚保温层（如岩棉 100 → 150 mm）最划算。',
          'Сыртқы қабырға U = ${u(loss.wallU).replaceAll('.', ',')} Вт/(м²·К); суық аймақта 0,40-тан аспағаны жөн, қатты суықта шамамен 0,30. Жылытқышты қалыңдату (мысалы, 100 → 150 мм) ең тиімді.', 'Наружная стена: U = ${u(loss.wallU).replaceAll('.', ',')} Вт/(м²·К); в холодном климате лучше не выше 0,40, в суровом — около 0,30. Эффективнее всего утолстить утеплитель (например, 100 → 150 мм).')));
  if (loss.roofU > 0.30)
    out.add(ConstructionIssue(
        'H02',
        IssueLevel.warn,
        ('屋顶保温偏弱', 'Шатыр жылуы әлсіз', 'Слабое утепление крыши'),
        (
          '屋顶传热系数 U = ${u(loss.roofU)} W/(m²·K)，宜不大于 0.25。热空气往上走，屋顶保温不足时冬天最费燃料。',
          'Шатыр U = ${u(loss.roofU).replaceAll('.', ',')} Вт/(м²·К), 0,25-тен аспағаны жөн. Жылы ауа жоғары көтеріледі, шатыр жылуы аз болса отын көп жұмсалады.', 'Крыша: U = ${u(loss.roofU).replaceAll('.', ',')} Вт/(м²·К), лучше не выше 0,25. Тёплый воздух поднимается вверх: при слабом утеплении крыши уходит много топлива.')));
  if (loss.floorU > 0.40)
    out.add(ConstructionIssue(
        'H03',
        IssueLevel.chk,
        ('地面保温偏弱', 'Еден жылуы әлсіз', 'Слабое утепление пола'),
        (
          '首层地面传热系数 U = ${u(loss.floorU)} W/(m²·K)。全家席地而坐，地面温度很重要，建议地坪下 XPS 不少于 100 mm 并连续铺设。',
          'Бірінші қабат едені U = ${u(loss.floorU).replaceAll('.', ',')} Вт/(м²·К). Еденде отыратын болғандықтан еден жылуы маңызды, астына кемінде 100 мм XPS үзіліссіз төсеңіз.', 'Пол первого этажа: U = ${u(loss.floorU).replaceAll('.', ',')} Вт/(м²·К). На полу сидят, поэтому его утепление важно: уложите под него сплошной слой XPS не тоньше 100 мм.')));
  if (loss.windowU > 1.6)
    out.add(ConstructionIssue(
        'H04',
        IssueLevel.chk,
        ('窗户保温偏弱', 'Терезе жылуы әлсіз', 'Слабая теплозащита окон'),
        (
          '窗传热系数 U = ${u(loss.windowU)} W/(m²·K)。三玻两腔 PVC 窗约 1.0–1.2，单层中空玻璃窗约 2.7，冬天窗边会结露。',
          'Терезе U = ${u(loss.windowU).replaceAll('.', ',')} Вт/(м²·К). Үш әйнекті ПВХ терезе шамамен 1,0–1,2, бір камералы шамамен 2,7 — қыста терезе жиегі терлейді.', 'Окна: U = ${u(loss.windowU).replaceAll('.', ',')} Вт/(м²·К). У трёхстекольного ПВХ-окна около 1,0–1,2, у однокамерного около 2,7 — зимой по краям окна будет конденсат.')));
  final share = loss.total <= 0 ? 0.0 : loss.windows / loss.total;
  if (share > 0.35)
    out.add(ConstructionIssue(
        'H05',
        IssueLevel.chk,
        ('窗户失热占比大', 'Терезеден жылу көп кетеді', 'Через окна уходит много тепла'),
        (
          '窗户失热占全屋的 ${(share * 100).round()}%。北面的大窗可以缩小，或换用保温更好的窗。',
          'Үйдің жылу шығынының ${(share * 100).round()}%-ы терезеден. Солтүстіктегі үлкен терезені кішірейтіңіз не жылырақ терезе қойыңыз.', '${(share * 100).round()} % теплопотерь дома приходится на окна. Уменьшите большое окно на северной стороне или поставьте более тёплые окна.')));
  return out;
}
