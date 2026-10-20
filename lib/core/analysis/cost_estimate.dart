import 'dart:math' as math;
import '../document/house_document.dart';
import '../geometry/derived_house.dart';
import '../geometry/floor_base.dart';
import 'house_analysis.dart';
import 'site_analysis.dart';
import 'utility_plan.dart';

/// A rough building budget: quantities from the model times unit prices,
/// labour as a share of materials and a contingency on top. The example
/// prices are ballpark village figures for 2026 that the user replaces
/// with local quotes. Pure Dart.

/// Stages of the estimate, in building order; they match the schedule.
const costStages = [
  'found',
  'walls',
  'roof',
  'openings',
  'mep',
  'finish',
  'site',
  'other'
];

/// Example unit prices per currency.
const defaultPrices = <Currency, Map<String, int>>{
  Currency.cny: {
    'excavation': 35,
    'cushion': 120,
    'concrete': 480,
    'rebar': 4200,
    'formwork': 45,
    'xps': 40,
    'dampproof': 30,
    'blind': 150,
    'masonryExt': 300,
    'masonryInt': 300,
    'wallIns': 70,
    'facade': 90,
    'floorSlab': 900,
    'roofSlab': 900,
    'roofMembrane': 60,
    'roofIns': 90,
    'parapetWp': 60,
    'roofCover': 120,
    'roofFrame': 160,
    'atticIns': 70,
    'windows': 650,
    'doorEntry': 3000,
    'doorsInt': 900,
    'elecPoint': 60,
    'cable': 6,
    'pipe': 30,
    'radiator': 600,
    'boiler': 7000,
    'sanitary': 1200,
    'groundFloor': 180,
    'finishArea': 350,
    'fence': 150,
    'gate': 2500,
    'outbuilding': 900,
    'paving': 90,
    'well': 6000,
    'septic': 5000,
  },
  Currency.kzt: {
    'excavation': 2500,
    'cushion': 9000,
    'concrete': 35000,
    'rebar': 380000,
    'formwork': 3000,
    'xps': 3200,
    'dampproof': 2200,
    'blind': 10000,
    'masonryExt': 30000,
    'masonryInt': 30000,
    'wallIns': 5500,
    'facade': 6500,
    'floorSlab': 65000,
    'roofSlab': 65000,
    'roofMembrane': 4500,
    'roofIns': 6500,
    'parapetWp': 4500,
    'roofCover': 9000,
    'roofFrame': 12000,
    'atticIns': 5000,
    'windows': 45000,
    'doorEntry': 200000,
    'doorsInt': 60000,
    'elecPoint': 4500,
    'cable': 450,
    'pipe': 2000,
    'radiator': 40000,
    'boiler': 450000,
    'sanitary': 80000,
    'groundFloor': 13000,
    'finishArea': 25000,
    'fence': 12000,
    'gate': 180000,
    'outbuilding': 60000,
    'paving': 6000,
    'well': 400000,
    'septic': 350000,
  },
};

/// Unit of each line: m, m2, m3, t or pcs.
const costUnits = {
  'excavation': 'm3',
  'cushion': 'm3',
  'concrete': 'm3',
  'rebar': 't',
  'formwork': 'm2',
  'xps': 'm2',
  'dampproof': 'm2',
  'blind': 'm2',
  'masonryExt': 'm3',
  'masonryInt': 'm3',
  'wallIns': 'm2',
  'facade': 'm2',
  'floorSlab': 'm3',
  'roofSlab': 'm3',
  'roofMembrane': 'm2',
  'roofIns': 'm2',
  'parapetWp': 'm2',
  'roofCover': 'm2',
  'roofFrame': 'm2',
  'atticIns': 'm2',
  'windows': 'm2',
  'doorEntry': 'pcs',
  'doorsInt': 'pcs',
  'elecPoint': 'pcs',
  'cable': 'm',
  'pipe': 'm',
  'radiator': 'pcs',
  'boiler': 'pcs',
  'sanitary': 'pcs',
  'groundFloor': 'm2',
  'finishArea': 'm2',
  'fence': 'm',
  'gate': 'pcs',
  'outbuilding': 'm2',
  'paving': 'm2',
  'well': 'pcs',
  'septic': 'pcs',
};

class CostLine {
  const CostLine(
      {required this.key,
      required this.stage,
      required this.quantity,
      required this.unit,
      required this.price,
      this.estimated = false,
      this.name,
      this.custom = false});

  /// Price key, or the item id for the user's own lines.
  final String key, stage, unit;
  final double quantity;
  final int price;

  /// The quantity is a rule of thumb, not measured from the model.
  final bool estimated;

  /// The user's own line and its name.
  final bool custom;
  final String? name;
  double get total => quantity * price;
}

class CostEstimate {
  const CostEstimate(
      {required this.currency,
      required this.lines,
      required this.labourPct,
      required this.contingencyPct,
      required this.buildingArea});
  final Currency currency;
  final List<CostLine> lines;
  final int labourPct, contingencyPct;

  /// Floor area over all floors, m².
  final double buildingArea;

  double stageMaterials(String stage) => lines
      .where((l) => l.stage == stage)
      .fold(0.0, (s, l) => s + l.total);

  /// Labour on the measured lines; the user's own lines are taken as quoted.
  double stageLabour(String stage) => lines
      .where((l) => l.stage == stage && !l.custom)
      .fold(0.0, (s, l) => s + l.total * labourPct / 100);
  double stageTotal(String stage) =>
      stageMaterials(stage) + stageLabour(stage);
  double get materials => lines.fold(0.0, (s, l) => s + l.total);
  double get labour => costStages.fold(0.0, (s, k) => s + stageLabour(k));
  double get contingency => (materials + labour) * contingencyPct / 100;
  double get total => materials + labour + contingency;
  double get perArea => buildingArea <= 0 ? 0 : total / buildingArea;
}

/// [currency] decides when the design has not chosen one.
CostEstimate estimateCost(HouseDocument doc, DerivedHouse derived,
    {Currency currency = Currency.cny}) {
  final x = doc.extras, spec = x.cost;
  final cur = spec.currency ?? currency;
  final prices = defaultPrices[cur]!;
  final lines = <CostLine>[];
  void line(String key, String stage, double quantity,
      {bool estimated = false}) {
    if (quantity <= 0) return;
    lines.add(CostLine(
        key: key,
        stage: stage,
        quantity: quantity,
        unit: costUnits[key]!,
        price: spec.prices[key] ?? prices[key]!,
        estimated: estimated));
  }

  final fd = foundationTakeoff(doc, derived), wt = wallTakeoff(doc, derived);
  final f = x.foundation;
  final rebar = (fd.mainBarLength / 1000 * barKgPerM(f.barDia) +
          fd.partitionBarLength / 1000 * barKgPerM(f.partitionBarDia) +
          fd.stirrupLength / 1000 * barKgPerM(f.stirrupDia) +
          fd.partitionStirrupLength / 1000 * barKgPerM(f.partitionStirrupDia)) /
      1000;
  line('excavation', 'found', fd.excavation / 1e9);
  line('cushion', 'found', fd.cushion / 1e9);
  line('concrete', 'found', fd.concrete * 1.03 / 1e9);
  line('rebar', 'found', rebar);
  line('formwork', 'found', fd.formwork / 1e6);
  line('xps', 'found', fd.xps / 1e6);
  line('dampproof', 'found', fd.waterproofing / 1e6);
  line('blind', 'found', fd.blinding / 1e6);

  // Walls: the structural layers of the outside wall, then inner walls.
  final net = math.max(0.0, wt.exteriorGross - wt.exteriorOpenings) / 1e6;
  final structural = x.wallLayers
      .where((l) =>
          l.material == LayerMaterial.block || l.material == LayerMaterial.conc)
      .fold(0, (s, l) => s + l.thickness);
  line('masonryExt', 'walls',
      net * (structural > 0 ? structural : doc.defaults.outerWallThickness) / 1000);
  line('masonryInt', 'walls', (wt.bearingVolume + wt.partitionVolume) / 1e9);
  if (x.wallLayers.any((l) => l.material == LayerMaterial.ins))
    line('wallIns', 'walls', net);
  line('facade', 'walls', net);

  final ground = derived.floors.first.base, top = derived.floors.last.base;
  double cellArea(FloorBase base) => footprintArea(base) / 1e6;
  final groundArea = cellArea(ground), topArea = cellArea(top);
  final slab = doc.defaults.slabThickness / 1000;
  var upperArea = 0.0;
  for (var i = 1; i < derived.floors.length; i++)
    upperArea += cellArea(derived.floors[i].base);
  line('floorSlab', 'walls', upperArea * slab);

  // Roof.
  final roof = doc.roof;
  final w = doc.footprint.width / 1000, d = doc.footprint.depth / 1000;
  final t = doc.defaults.outerWallThickness / 1000;
  final outerWalls = wallsOf(top, x.foundation)
      .where((wall) => wall.role == WallRole.exterior)
      .fold(0.0, (s, wall) => s + wall.rect.area / 1e6);
  final innerTop = math.max(0.0, topArea - outerWalls);
  if (roof.type == RoofType.flat) {
    line('roofSlab', 'roof', topArea * slab);
    line('roofMembrane', 'roof', innerTop);
    if (x.roofLayers.any((l) => l.material == LayerMaterial.ins))
      line('roofIns', 'roof', innerTop);
    final perimeter = top.edges
        .where((e) => e.kind == 'exterior')
        .fold(0.0, (s, e) => s + (e.end.pos - e.start.pos) / 1000);
    line('parapetWp', 'roof', math.max(0.0, perimeter - 8 * t) * 0.3);
  } else {
    final o = roof.overhang! / 1000;
    final area =
        (w + 2 * o) * (d + 2 * o) / math.cos(roof.pitchDeg! * math.pi / 180);
    line('roofCover', 'roof', area);
    line('roofFrame', 'roof', area);
    line('atticIns', 'roof', innerTop);
  }

  // Doors and windows.
  var glass = 0.0, entry = 0, inner = 0;
  for (final g in derived.floors)
    for (final p in g.openings) {
      if (p.opening.kind == OpeningKind.door) {
        p.host?.kind == 'exterior' ? entry++ : inner++;
      } else {
        glass += p.opening.width * p.opening.height / 1e6;
      }
    }
  line('windows', 'openings', glass);
  line('doorEntry', 'openings', entry.toDouble());
  line('doorsInt', 'openings', inner.toDouble());

  // Services: measured from the points when there are any.
  var rooms = 0, wetRooms = 0, windows = 0;
  var clear = 0.0;
  for (var i = 0; i < doc.floors.length; i++) {
    final g = derived.floors[i];
    for (final r in doc.floors[i].rooms) {
      rooms++;
      if (r.type == RoomType.kitchen || r.type == RoomType.bathroom) wetRooms++;
    }
    for (final s in g.base.roomGeometry) clear += s.clearArea / 1e6;
    windows += g.openings
        .where((p) =>
            p.opening.kind != OpeningKind.door && p.host?.kind == 'exterior')
        .length;
  }
  final u = utilityTakeoff(doc);
  final measured = !u.isEmpty;
  final fixtures =
      x.furniture.where((f) => wetFurniture.contains(f.kind)).length;
  final points = measured ? u.electrical.toDouble() : (clear * 0.5).roundToDouble();
  line('elecPoint', 'mep', points, estimated: !measured);
  line('cable', 'mep',
      measured ? u.lightCable + u.powerCable : points * 8,
      estimated: !measured);
  line('pipe', 'mep',
      measured
          ? u.waterPipe + u.drainPipe + u.heatingPipe
          : wetRooms * 15.0 + windows * 8.0,
      estimated: !measured);
  line(
      'radiator',
      'mep',
      measured && u.count(UtilityKind.radiator) > 0
          ? u.count(UtilityKind.radiator).toDouble()
          : windows.toDouble(),
      estimated: !(measured && u.count(UtilityKind.radiator) > 0));
  line('boiler', 'mep', rooms > 0 ? 1 : 0);
  line('sanitary', 'mep',
      fixtures > 0 ? fixtures.toDouble() : wetRooms * 2.0,
      estimated: fixtures == 0);

  // Floors and finishes.
  final outerGround = wallsOf(ground, x.foundation)
      .where((wall) => wall.role == WallRole.exterior)
      .fold(0.0, (s, wall) => s + wall.rect.area / 1e6);
  line('groundFloor', 'finish', math.max(0.0, groundArea - outerGround));
  line('finishArea', 'finish', clear > 0 ? clear : groundArea - outerGround);

  // The plot.
  final site = x.site;
  if (site != null) {
    final areas = siteAreas(site);
    final gates = site.items.where((i) => i.kind == SiteKind.gate);
    if (site.fence)
      line(
          'fence',
          'site',
          math.max(
              0.0,
              2 * (site.width + site.depth) / 1000 -
                  gates.fold(0.0, (s, g) => s + math.max(g.width, g.depth) / 1000)));
    line('gate', 'site', gates.length.toDouble());
    line('outbuilding', 'site',
        siteBuildings.fold(0.0, (s, k) => s + (areas[k] ?? 0)));
    line('paving', 'site', areas[SiteKind.yard] ?? 0);
    line('well', 'site',
        site.items.where((i) => i.kind == SiteKind.well).length.toDouble());
    line('septic', 'site',
        site.items.where((i) => i.kind == SiteKind.septic).length.toDouble());
  }

  for (final item in spec.items)
    lines.add(CostLine(
        key: item.id,
        stage: 'other',
        quantity: item.quantity / 100,
        unit: item.unit,
        price: item.price,
        name: item.name,
        custom: true));

  var area = 0.0;
  for (final g in derived.floors) area += cellArea(g.base);
  return CostEstimate(
      currency: cur,
      lines: List.unmodifiable(lines),
      labourPct: spec.labourPct,
      contingencyPct: spec.contingencyPct,
      buildingArea: area);
}
