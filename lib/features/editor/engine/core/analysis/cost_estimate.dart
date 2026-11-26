import 'dart:math' as math;
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/analysis/house_analysis.dart';
import 'package:yusal/features/editor/engine/core/analysis/site_analysis.dart';
import 'package:yusal/features/editor/engine/core/analysis/utility_plan.dart';

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
  'general',
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
    'finishTileArea': 390,
    'fence': 150,
    'gate': 2500,
    'outbuilding': 900,
    'paving': 90,
    'well': 6000,
    'septic': 5000,
    'ringBeam': 1100,
    'lintel': 100,
    'gutter': 60,
    'scaffold': 10,
    'delivery': 300,
    'connection': 6000,
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
    'finishTileArea': 28000,
    'fence': 12000,
    'gate': 180000,
    'outbuilding': 60000,
    'paving': 6000,
    'well': 400000,
    'septic': 350000,
    'ringBeam': 85000,
    'lintel': 8000,
    'gutter': 4500,
    'scaffold': 800,
    'delivery': 25000,
    'connection': 500000,
  },
};

bool usesTileFinish(RoomType type) =>
    type == RoomType.kitchen || type == RoomType.bathroom;

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
  'finishTileArea': 'm2',
  'fence': 'm',
  'gate': 'pcs',
  'outbuilding': 'm2',
  'paving': 'm2',
  'well': 'pcs',
  'septic': 'pcs',
  'ringBeam': 'm3',
  'lintel': 'm',
  'gutter': 'm',
  'scaffold': 'm2',
  'delivery': 'pcs',
  'connection': 'pcs',
};

/// Lines that are bought as a service: no labour is added to them.
const serviceLines = {
  'excavation',
  'well',
  'septic',
  'scaffold',
  'delivery',
  'connection'
};

/// Example price of a cubic metre of wall laid from each unit other than
/// aerated blocks, which the masonry lines above price.
const masonryPrices = <Currency, Map<MasonryUnit, int>>{
  Currency.cny: {MasonryUnit.brick: 380, MasonryUnit.cinder: 240},
  Currency.kzt: {MasonryUnit.brick: 44000, MasonryUnit.cinder: 25000},
};

/// Example labour rates per unit of each line, for pricing labour by the
/// work done. Lines left out are bought with their labour.
const defaultLabour = <Currency, Map<String, int>>{
  Currency.cny: {
    'cushion': 30,
    'concrete': 260,
    'rebar': 800,
    'formwork': 35,
    'xps': 10,
    'dampproof': 10,
    'blind': 50,
    'masonryExt': 180,
    'masonryInt': 180,
    'ringBeam': 330,
    'lintel': 40,
    'wallIns': 35,
    'facade': 45,
    'floorSlab': 330,
    'roofSlab': 330,
    'roofMembrane': 20,
    'roofIns': 15,
    'parapetWp': 20,
    'roofCover': 45,
    'roofFrame': 40,
    'atticIns': 12,
    'gutter': 20,
    'windows': 80,
    'doorEntry': 250,
    'doorsInt': 150,
    'elecPoint': 35,
    'cable': 3,
    'pipe': 15,
    'radiator': 100,
    'boiler': 600,
    'sanitary': 200,
    'groundFloor': 50,
    'finishArea': 160,
    'finishTileArea': 190,
    'fence': 40,
    'gate': 400,
    'outbuilding': 330,
    'paving': 35,
  },
  Currency.kzt: {
    'cushion': 2000,
    'concrete': 20000,
    'rebar': 60000,
    'formwork': 2500,
    'xps': 800,
    'dampproof': 700,
    'blind': 4000,
    'masonryExt': 14000,
    'masonryInt': 14000,
    'ringBeam': 25000,
    'lintel': 3000,
    'wallIns': 2500,
    'facade': 3500,
    'floorSlab': 25000,
    'roofSlab': 25000,
    'roofMembrane': 1500,
    'roofIns': 1200,
    'parapetWp': 1500,
    'roofCover': 3500,
    'roofFrame': 3000,
    'atticIns': 1000,
    'gutter': 1500,
    'windows': 6000,
    'doorEntry': 20000,
    'doorsInt': 12000,
    'elecPoint': 2500,
    'cable': 250,
    'pipe': 1200,
    'radiator': 8000,
    'boiler': 50000,
    'sanitary': 15000,
    'groundFloor': 4000,
    'finishArea': 12000,
    'finishTileArea': 14000,
    'fence': 3000,
    'gate': 30000,
    'outbuilding': 25000,
    'paving': 2500,
  },
};

/// Where a unit price comes from: the user's own quote, the price list of
/// the house's region, or the built-in example.
enum PriceSource { own, region, example }

/// One price of a region's list, with who reported it and when.
class PriceQuote {
  const PriceQuote(this.price, {this.source = '', this.date = ''});
  final int price;

  /// 'stat' for official statistics, 'market' for prices people reported,
  /// 'team' for prices the team entered.
  final String source;

  /// The day the price was seen, YYYY-MM-DD.
  final String date;
}

/// The prices of one region in one currency. A masonry unit other than
/// aerated blocks is priced under `masonry_<unit>`; a labour rate under the
/// key of its line.
class PriceBook {
  const PriceBook(
      {required this.region,
      required this.currency,
      this.prices = const {},
      this.labour = const {}});
  final String region;
  final Currency currency;
  final Map<String, PriceQuote> prices;
  final Map<String, PriceQuote> labour;
}

class CostLine {
  const CostLine(
      {required this.key,
      required this.stage,
      required this.quantity,
      required this.unit,
      required this.price,
      this.estimated = false,
      this.name,
      this.custom = false,
      this.source = PriceSource.example,
      this.quote,
      this.labourRate = 0,
      this.ownLabour = false,
      this.service = false});

  /// Price key, or the item id for the user's own lines.
  final String key;
  final String stage;
  final String unit;
  final double quantity;
  final int price;

  /// The quantity is a rule of thumb, not measured from the model.
  final bool estimated;

  /// The user's own line and its name.
  final bool custom;
  final String? name;

  /// Where [price] comes from, and the region's quote when it is one.
  final PriceSource source;
  final PriceQuote? quote;

  /// Labour per unit when labour is priced by the work, and whether the
  /// user set that rate.
  final int labourRate;
  final bool ownLabour;

  /// Bought as a service or a fee: no labour is added.
  final bool service;
  double get total => quantity * price;

  /// How far the line may be off, as a share of its amount: a quote is
  /// close, a regional price less so, an example least; a quantity that is
  /// only a rule of thumb adds to it.
  double get uncertainty =>
      switch (source) {
        PriceSource.own => 0.05,
        PriceSource.region => 0.12,
        PriceSource.example => 0.25
      } +
      (estimated ? 0.2 : 0);
}

class CostEstimate {
  const CostEstimate(
      {required this.currency,
      required this.lines,
      required this.labourPct,
      required this.contingencyPct,
      required this.buildingArea,
      this.labourByWork = false,
      this.selfBuild = const {},
      this.region});
  final Currency currency;
  final List<CostLine> lines;
  final int labourPct;
  final int contingencyPct;

  /// Floor area over all floors, m².
  final double buildingArea;

  /// Labour by the work done rather than as a share of the materials, the
  /// stages the family builds itself, and the region of the prices used.
  final bool labourByWork;
  final Set<String> selfBuild;
  final String? region;

  double stageMaterials(String stage) =>
      lines.where((l) => l.stage == stage).fold(0.0, (s, l) => s + l.total);

  /// Labour of one line; the user's own lines and services are taken as
  /// quoted, and nothing is charged on a stage the family builds itself.
  double lineLabour(CostLine l) =>
      l.custom || l.service || selfBuild.contains(l.stage)
          ? 0
          : labourByWork
              ? l.quantity * l.labourRate
              : l.total * labourPct / 100;
  double stageLabour(String stage) => lines
      .where((l) => l.stage == stage)
      .fold(0.0, (s, l) => s + lineLabour(l));
  double stageTotal(String stage) => stageMaterials(stage) + stageLabour(stage);
  double get materials => lines.fold(0.0, (s, l) => s + l.total);
  double get labour => lines.fold(0.0, (s, l) => s + lineLabour(l));
  double get contingency => (materials + labour) * contingencyPct / 100;
  double get total => materials + labour + contingency;
  double get perArea => buildingArea <= 0 ? 0 : total / buildingArea;

  /// How far the total may be off either way: each line by how sure its
  /// price and quantity are, labour by how sure its rate is.
  double get spread {
    var s = 0.0;
    for (final l in lines) {
      s += l.total * (l.custom ? 0.05 : l.uncertainty);
      s += lineLabour(l) * (labourByWork && l.ownLabour ? 0.05 : 0.25);
    }
    return s * (1 + contingencyPct / 100);
  }

  double get low => math.max(0, total - spread);
  double get high => total + spread;

  /// Share of the total the spread makes, 0.2 for ±20%.
  double get spreadShare => total <= 0 ? 0 : spread / total;

  /// Lines still priced by the built-in example.
  int get examplePrices =>
      lines.where((l) => !l.custom && l.source == PriceSource.example).length;
}

/// [currency] decides when the design has not chosen one. [book] is the
/// price list of the design's region; it is used when it is in the
/// estimate's currency.
CostEstimate estimateCost(HouseDocument doc, DerivedHouse derived,
    {Currency currency = Currency.cny, PriceBook? book}) {
  final x = doc.extras;
  final spec = x.cost;
  final cur = spec.currency ?? currency;
  final prices = defaultPrices[cur]!;
  final labour = defaultLabour[cur]!;
  final regional = book != null && book.currency == cur ? book : null;
  final lines = <CostLine>[];
  void line(String key, String stage, double quantity,
      {bool estimated = false, MasonryUnit unit = MasonryUnit.aerated}) {
    if (quantity <= 0) return;
    // Existing all-room finish quotes also cover tiles until priced separately.
    final inherited = key == 'finishTileArea' ? 'finishArea' : key;
    final own = spec.prices[key] ?? spec.prices[inherited];
    final bookKey = unit == MasonryUnit.aerated ? key : 'masonry_${unit.name}';
    final quote = regional?.prices[bookKey] ??
        (key == 'finishTileArea' ? regional?.prices[inherited] : null);
    final example =
        unit == MasonryUnit.aerated ? prices[key]! : masonryPrices[cur]![unit]!;
    lines.add(CostLine(
        key: key,
        stage: stage,
        quantity: quantity,
        unit: costUnits[key]!,
        price: own ?? quote?.price ?? example,
        source: own != null
            ? PriceSource.own
            : quote != null
                ? PriceSource.region
                : PriceSource.example,
        quote: own == null ? quote : null,
        labourRate: spec.labourPrices[key] ??
            spec.labourPrices[inherited] ??
            regional?.labour[key]?.price ??
            regional?.labour[inherited]?.price ??
            labour[key] ??
            0,
        ownLabour: spec.labourPrices.containsKey(key) ||
            spec.labourPrices.containsKey(inherited),
        service: serviceLines.contains(key),
        estimated: estimated));
  }

  final fd = foundationTakeoff(doc, derived);
  final wt = wallTakeoff(doc, derived);
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

  // Walls: the structural layers of the outside wall with the gables, then
  // inner walls; the reinforced belts take the place of masonry.
  final st = structureTakeoff(doc, derived);
  final net = math.max(0.0, wt.exteriorGross - wt.exteriorOpenings) / 1e6;
  final masonry = masonryVolumes(doc, wt, st);
  line('masonryExt', 'walls', masonry.exterior, unit: spec.outerUnit);
  line('masonryInt', 'walls', masonry.interior, unit: spec.innerUnit);
  line('ringBeam', 'walls', st.beltVolume / 1e9);
  line('lintel', 'walls', st.lintelLength / 1000);
  if (x.wallLayers.any((l) => l.material == LayerMaterial.ins)) {
    line('wallIns', 'walls', net);
  }
  line('facade', 'walls', net);

  final ground = derived.floors.first.base;
  final top = derived.floors.last.base;
  double cellArea(FloorBase base) => footprintArea(base) / 1e6;
  final groundArea = cellArea(ground);
  final topArea = cellArea(top);
  final slab = doc.defaults.slabThickness / 1000;
  var upperArea = 0.0;
  for (var i = 1; i < derived.floors.length; i++) {
    upperArea += cellArea(derived.floors[i].base);
  }
  line('floorSlab', 'walls', upperArea * slab);

  // Roof.
  final roof = doc.roof;
  final w = doc.footprint.width / 1000;
  final d = doc.footprint.depth / 1000;
  final t = doc.defaults.outerWallThickness / 1000;
  final outerWalls = wallsOf(top, x.foundation)
      .where((wall) => wall.role == WallRole.exterior)
      .fold(0.0, (s, wall) => s + wall.rect.area / 1e6);
  final innerTop = math.max(0.0, topArea - outerWalls);
  if (roof.type == RoofType.flat) {
    line('roofSlab', 'roof', topArea * slab);
    line('roofMembrane', 'roof', innerTop);
    if (x.roofLayers.any((l) => l.material == LayerMaterial.ins)) {
      line('roofIns', 'roof', innerTop);
    }
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
    line('gutter', 'roof', roofTakeoff(doc)!.eaves);
  }

  // Doors and windows.
  var glass = 0.0;
  var entry = 0;
  var inner = 0;
  for (final g in derived.floors) {
    for (final p in g.openings) {
      if (p.opening.kind == OpeningKind.door) {
        p.host?.kind == 'exterior' ? entry++ : inner++;
      } else {
        glass += p.opening.width * p.opening.height / 1e6;
      }
    }
  }
  line('windows', 'openings', glass);
  line('doorEntry', 'openings', entry.toDouble());
  line('doorsInt', 'openings', inner.toDouble());

  // Services: measured from the points when there are any.
  var rooms = 0;
  var wetRooms = 0;
  var windows = 0;
  var clear = 0.0;
  var tileArea = 0.0;
  for (var i = 0; i < doc.floors.length; i++) {
    final g = derived.floors[i];
    for (final r in doc.floors[i].rooms) {
      rooms++;
      if (usesTileFinish(r.type)) {
        wetRooms++;
        tileArea += (g.base.roomsById[r.id]?.clearArea ?? 0) / 1e6;
      }
    }
    for (final s in g.base.roomGeometry) {
      clear += s.clearArea / 1e6;
    }
    windows += g.openings
        .where((p) =>
            p.opening.kind != OpeningKind.door && p.host?.kind == 'exterior')
        .length;
  }
  final u = utilityTakeoff(doc);
  final measured = !u.isEmpty;
  final fixtures =
      x.furniture.where((f) => wetFurniture.contains(f.kind)).length;
  final points =
      measured ? u.electrical.toDouble() : (clear * 0.5).roundToDouble();
  line('elecPoint', 'mep', points, estimated: !measured);
  line('cable', 'mep', measured ? u.lightCable + u.powerCable : points * 8,
      estimated: !measured);
  line(
      'pipe',
      'mep',
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
  line('sanitary', 'mep', fixtures > 0 ? fixtures.toDouble() : wetRooms * 2.0,
      estimated: fixtures == 0);

  // Floors and finishes.
  final outerGround = wallsOf(ground, x.foundation)
      .where((wall) => wall.role == WallRole.exterior)
      .fold(0.0, (s, wall) => s + wall.rect.area / 1e6);
  line('groundFloor', 'finish', math.max(0.0, groundArea - outerGround));
  line('finishArea', 'finish',
      clear > 0 ? clear - tileArea : groundArea - outerGround);

  line('finishTileArea', 'finish', tileArea);

  // The plot.
  final site = x.site;
  if (site != null) {
    final areas = siteAreas(site);
    final gates = site.items.where((i) => i.kind == SiteKind.gate);
    if (site.fence) {
      line(
          'fence',
          'site',
          math.max(
              0.0,
              2 * (site.width + site.depth) / 1000 -
                  gates.fold(
                      0.0, (s, g) => s + math.max(g.width, g.depth) / 1000)));
    }
    line('gate', 'site', gates.length.toDouble());
    line('outbuilding', 'site',
        siteBuildings.fold(0.0, (s, k) => s + (areas[k] ?? 0)));
    line('paving', 'site', areas[SiteKind.yard] ?? 0);
    line('well', 'site',
        site.items.where((i) => i.kind == SiteKind.well).length.toDouble());
    line('septic', 'site',
        site.items.where((i) => i.kind == SiteKind.septic).length.toDouble());
  }

  // What no drawing shows: scaffolding around the walls, lorries for the
  // heavy materials, and connecting the house to the mains.
  final laid = masonry.exterior + masonry.interior;
  if (laid > 0) {
    line('scaffold', 'general', wt.exteriorGross / 1e6);
    line('delivery', 'general', (laid / 15).ceil() + 3.0, estimated: true);
    line('connection', 'general', 1, estimated: true);
  }

  for (final item in spec.items) {
    lines.add(CostLine(
        key: item.id,
        stage: 'other',
        quantity: item.quantity / 100,
        unit: item.unit,
        price: item.price,
        name: item.name,
        source: PriceSource.own,
        custom: true));
  }

  var area = 0.0;
  for (final g in derived.floors) {
    area += cellArea(g.base);
  }
  return CostEstimate(
      currency: cur,
      lines: List.unmodifiable(lines),
      labourPct: spec.labourPct,
      contingencyPct: spec.contingencyPct,
      buildingArea: area,
      labourByWork: spec.labourByWork,
      selfBuild: spec.selfBuild.toSet(),
      region: spec.region);
}
