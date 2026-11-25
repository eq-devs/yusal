import 'dart:math' as math;
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/analysis/cost_estimate.dart';
import 'package:yusal/features/editor/engine/core/analysis/house_analysis.dart';

/// The shopping list of a house: the quantities of the model turned into
/// what is bought, by a recipe for each part (a cubic metre of block wall
/// is so many blocks, so much glue and so much bar), with an allowance for
/// waste and rounded up to whole bags, bars and rolls. The recipes are
/// common rules of thumb; a builder's own figures come first. Pure Dart.

class MaterialLine {
  const MaterialLine(
      {required this.key,
      required this.stage,
      required this.quantity,
      required this.unit,
      this.waste = 0,
      this.detail = '',
      this.packs,
      this.pack = '',
      this.weight,
      this.estimated = false});

  /// What it is, a key of the material names; a line copied from the
  /// estimate keeps the estimate's key.
  final String key;
  final String stage;

  /// To buy, the waste allowance included, in [unit]: pcs, m, m2, m3, kg
  /// or l.
  final double quantity;
  final String unit;

  /// The allowance already in [quantity], percent.
  final int waste;

  /// Size or grade, the same in every language: Ø12, 600×200×300.
  final String detail;

  /// Whole packs to buy and what a pack is: bag, bar, roll, sheet, coil,
  /// can or piece.
  final int? packs;
  final String pack;

  /// Kilograms, for bar sold by weight.
  final double? weight;

  /// From a rule of thumb rather than measured from the model.
  final bool estimated;
}

/// Bars come 11.7 m long.
const barLength = 11.7;

/// What a cubic metre of wall takes of each unit: its size (mm, the block
/// as thick as the wall when zero), how many with their joints, and the
/// glue (kg) or mortar (m³) between them.
const _unitsPerM3 = {MasonryUnit.brick: 394.0, MasonryUnit.cinder: 63.0};
const _unitSize = {
  MasonryUnit.brick: '250×120×65',
  MasonryUnit.cinder: '390×190×188'
};
const _mortarPerM3 = {MasonryUnit.brick: 0.24, MasonryUnit.cinder: 0.12};
const _unitKey = {
  MasonryUnit.aerated: 'blockAerated',
  MasonryUnit.brick: 'brick',
  MasonryUnit.cinder: 'blockCinder'
};

class _Raw {
  _Raw(this.unit, this.waste, this.packSize, this.pack, this.weightPer,
      this.estimated);
  final String unit;
  final int waste;
  final double? packSize;
  final String pack;
  final double? weightPer;
  bool estimated;
  double net = 0;
}

/// [estimate] is the estimate of the same document when the caller has it.
List<MaterialLine> materialList(HouseDocument doc, DerivedHouse derived,
    {CostEstimate? estimate}) {
  final x = doc.extras;
  final f = x.foundation;
  final spec = x.cost;
  final raw = <(String, String, String), _Raw>{};
  void add(String key, String stage, double net, String unit,
      {int waste = 0,
      String detail = '',
      double? packSize,
      String pack = '',
      double? weightPer,
      bool estimated = false}) {
    if (net <= 0) return;
    final r = raw.putIfAbsent((stage, key, detail),
        () => _Raw(unit, waste, packSize, pack, weightPer, estimated));
    r
      ..net += net
      ..estimated = r.estimated && estimated;
  }

  void bar(String stage, int dia, double mm, {bool estimated = false}) =>
      add('rebar', stage, mm / 1000, 'm',
          waste: 5,
          detail: 'Ø$dia',
          packSize: barLength,
          pack: 'bar',
          weightPer: barKgPerM(dia),
          estimated: estimated);
  void concrete(String stage, double mm3, [String grade = '']) =>
      add('concrete', stage, mm3 / 1e9, 'm3', waste: 3, detail: grade);

  // Foundation.
  final fd = foundationTakeoff(doc, derived);
  concrete('found', fd.concrete, f.concrete);
  bar('found', f.barDia, fd.mainBarLength);
  bar('found', f.partitionBarDia, fd.partitionBarLength);
  bar('found', f.stirrupDia, fd.stirrupLength);
  bar('found', f.partitionStirrupDia, fd.partitionStirrupLength);
  add('gravel', 'found', fd.cushion / 1e9, 'm3', waste: 15);
  add('formBoard', 'found', fd.formwork / 1e6, 'm2');
  add('xps', 'found', fd.xps / 1e6, 'm2',
      waste: 5, packSize: 0.72, pack: 'sheet');
  add('bitumenRoll', 'found', fd.waterproofing / 1e6, 'm2',
      waste: 10, packSize: 10, pack: 'roll');

  // Walls: the outside wall at its structural thickness, inner walls by
  // the thickness drawn.
  final wt = wallTakeoff(doc, derived);
  final st = structureTakeoff(doc, derived);
  final volumes = masonryVolumes(doc, wt, st);
  final outer = structuralThickness(doc);
  void masonry(MasonryUnit unit, double m3, double thickness) {
    if (m3 <= 0) return;
    if (unit == MasonryUnit.aerated) {
      final t = thickness.round();
      add(_unitKey[unit]!, 'walls', m3 / (0.6 * 0.2 * t / 1000), 'pcs',
          waste: 5, detail: '600×200×$t');
      add('glue', 'walls', m3 * 25, 'kg', packSize: 25, pack: 'bag');
      // Two bars in grooves every fourth course.
      bar('walls', 8, m3 * 1e9 / thickness / 1000 * 2.5);
    } else {
      add(_unitKey[unit]!, 'walls', m3 * _unitsPerM3[unit]!, 'pcs',
          waste: 5, detail: _unitSize[unit]!);
      final mortar = m3 * _mortarPerM3[unit]!;
      add('cement', 'walls', mortar * 300, 'kg', packSize: 50, pack: 'bag');
      add('sand', 'walls', mortar * 1.1, 'm3', waste: 10);
    }
  }

  masonry(spec.outerUnit, volumes.exterior, outer);
  final inner = <int, double>{};
  for (var i = 0; i < doc.floors.length; i++) {
    final g = derived.floors[i];
    final h = doc.floors[i].height.toDouble();
    for (final wall in wallsOf(g.base, f)) {
      if (wall.role != WallRole.bearing && wall.role != WallRole.partition) {
        continue;
      }
      final openings = g.openings
          .where((p) => p.status == 'ok' && p.host?.ref == wall.segment.ref)
          .fold(
              0.0, (s, p) => s + p.opening.width * p.opening.height.toDouble());
      final along = wall.segment.end.pos - wall.segment.start.pos.toDouble();
      final t = wall.thickness.round();
      inner[t] = (inner[t] ?? 0) + (along * h - openings) * wall.thickness;
    }
  }
  final innerSum = inner.values.fold(0.0, (s, v) => s + v) / 1e9;
  var innerFace = 0.0;
  for (final e in inner.entries) {
    // The belts come out of each thickness in proportion.
    masonry(spec.innerUnit,
        innerSum <= 0 ? 0 : e.value / 1e9 * volumes.interior / innerSum,
        e.key.toDouble());
    innerFace += e.value / e.key / 1e6;
  }

  // Belts and lintels: four bars and a stirrup every 250 mm.
  concrete('walls', st.beltVolume + st.lintelVolume);
  bar('walls', 12, (st.beltLength * 1.08 + st.lintelLength) * 4);
  final beltWidth = st.beltLength <= 0
      ? outer
      : st.beltVolume / st.beltLength / ringBeamHeight;
  bar(
      'walls',
      6,
      ((st.beltLength + st.lintelLength) / 250).ceil() *
          (2 * (beltWidth - 80 + ringBeamHeight - 80) + 150));

  // Slabs between floors and under a flat roof: concrete, an allowance
  // of bar and the deck to pour on.
  final slab = doc.defaults.slabThickness.toDouble();
  final top = derived.floors.last.base;
  var upper = 0.0;
  for (var i = 1; i < derived.floors.length; i++) {
    upper += footprintArea(derived.floors[i].base);
  }
  void slabOf(String stage, double mm2) {
    if (mm2 <= 0) return;
    concrete(stage, mm2 * slab);
    bar(stage, 12, mm2 * slab / 1e9 * 100 / barKgPerM(12) * 1000,
        estimated: true);
    add('formBoard', stage, mm2 / 1e6, 'm2');
  }

  slabOf('walls', upper);

  // The outside face: insulation when the build-up has it, then render.
  final net = math.max(0.0, wt.exteriorGross - wt.exteriorOpenings) / 1e6;
  final wallIns = x.wallLayers
      .where((l) => l.material == LayerMaterial.ins)
      .fold(0, (s, l) => s + l.thickness);
  if (wallIns > 0) {
    add('insulation', 'walls', net, 'm2', waste: 5, detail: '$wallIns mm');
    add('adhesive', 'walls', net * 6, 'kg', packSize: 25, pack: 'bag');
    add('dowel', 'walls', net * 6, 'pcs');
    add('mesh', 'walls', net, 'm2', waste: 10, packSize: 50, pack: 'roll');
  }
  add('render', 'walls', net * 3.5, 'kg', packSize: 25, pack: 'bag');

  // Roof.
  final topArea = footprintArea(top) / 1e6;
  final outerTop = wallsOf(top, f)
      .where((wall) => wall.role == WallRole.exterior)
      .fold(0.0, (s, wall) => s + wall.rect.area / 1e6);
  final innerTop = math.max(0.0, topArea - outerTop);
  final roofIns = x.roofLayers
      .where((l) => l.material == LayerMaterial.ins)
      .fold(0, (s, l) => s + l.thickness);
  final rt = roofTakeoff(doc);
  if (rt == null) {
    slabOf('roof', topArea * 1e6);
    add('roofRoll', 'roof', innerTop * 2, 'm2',
        waste: 15, packSize: 10, pack: 'roll');
    if (roofIns > 0) {
      add('insulation', 'roof', innerTop, 'm2',
          waste: 5, detail: '$roofIns mm');
    }
  } else {
    add('timber', 'roof', rt.rafterLength * 0.05 * 0.15, 'm3',
        waste: 10, detail: '50×150');
    add('timber', 'roof', rt.battenLength * 0.025 * 0.1, 'm3',
        waste: 10, detail: '25×100');
    add('timber', 'roof', rt.eaves * 0.15 * 0.15, 'm3',
        waste: 5, detail: '150×150');
    add('roofMembrane', 'roof', rt.area, 'm2',
        waste: 10, packSize: 75, pack: 'roll');
    add('roofSheet', 'roof', rt.area, 'm2', waste: 10);
    add('ridgeCap', 'roof', rt.ridge + rt.hips, 'm',
        waste: 5, packSize: 2, pack: 'piece');
    add('gutter', 'roof', rt.eaves, 'm', packSize: 3, pack: 'piece');
    add('downpipe', 'roof', 4 * wt.height / 1000, 'm',
        packSize: 3, pack: 'piece');
    add('screw', 'roof', rt.area * 8, 'pcs', packSize: 250, pack: 'pack');
    add('wool', 'roof', innerTop * (roofIns > 0 ? roofIns : 200) / 1000, 'm3',
        waste: 5);
  }

  // Windows and doors, one line per size.
  var around = 0.0;
  for (final g in derived.floors) {
    for (final p in g.openings) {
      if (p.status != 'ok') continue;
      final o = p.opening;
      add(
          o.kind != OpeningKind.door
              ? 'window'
              : p.host?.kind == 'exterior'
                  ? 'doorEntry'
                  : 'doorInt',
          'openings',
          1,
          'pcs',
          detail: '${o.width}×${o.height}');
      around += 2 * (o.width + o.height) / 1000;
    }
  }
  add('foam', 'openings', (around / 10).ceilToDouble(), 'pcs', estimated: true);

  // Services are counted in the estimate; wire and pipe get a tenth more.
  final e = estimate ?? estimateCost(doc, derived);
  for (final l in e.lines.where((l) => l.stage == 'mep')) {
    final run = l.unit == 'm';
    add(l.key, 'mep', l.quantity, l.unit,
        waste: run ? 10 : 0,
        packSize: l.key == 'cable' ? 100 : null,
        pack: l.key == 'cable' ? 'coil' : '',
        estimated: l.estimated);
  }

  // Inside: plaster and paint on the walls, screed and a floor covering.
  var clear = 0.0;
  var wet = 0.0;
  for (var i = 0; i < doc.floors.length; i++) {
    final g = derived.floors[i].base;
    for (final r in doc.floors[i].rooms) {
      final area = (g.roomsById[r.id]?.clearArea ?? 0) / 1e6;
      clear += area;
      if (usesTileFinish(r.type)) {
        wet += area;
      }
    }
  }
  int layer(List<Layer> layers, LayerMaterial m, int usual) =>
      layers.lastWhere((l) => l.material == m,
          orElse: () => Layer('', '', usual, m)).thickness;
  final faces = net + 2 * innerFace;
  if (clear > 0) {
    add(
        'plaster',
        'finish',
        faces * layer(x.wallLayers, LayerMaterial.plaster, 15) * 0.85,
        'kg',
        packSize: 30,
        pack: 'bag');
    add('putty', 'finish', faces * 1.2, 'kg', packSize: 20, pack: 'bag');
    add('paint', 'finish', (faces + clear) * 0.3, 'l',
        packSize: 10, pack: 'can');
    add(
        'screed',
        'finish',
        clear * layer(x.floorLayers, LayerMaterial.plaster, 50) * 2,
        'kg',
        packSize: 40,
        pack: 'bag');
    add('tile', 'finish', wet, 'm2', waste: 10);
    add('tileGlue', 'finish', wet * 5, 'kg', packSize: 25, pack: 'bag');
    add('laminate', 'finish', clear - wet, 'm2', waste: 7);
  }

  final out = <MaterialLine>[];
  final wire = <String, double>{};
  for (final entry in raw.entries) {
    final (stage, key, detail) = entry.key;
    final r = entry.value;
    final quantity = r.net * (1 + r.waste / 100);
    final packs = r.packSize == null
        ? null
        : (quantity / r.packSize! - 1e-9).ceil();
    // Whole bars are bought, so their weight is that of whole bars.
    final weight = r.weightPer == null
        ? null
        : (r.pack == 'bar' ? packs! * r.packSize! : quantity) * r.weightPer!;
    if (key == 'rebar') wire[stage] = (wire[stage] ?? 0) + weight!;
    out.add(MaterialLine(
        key: key,
        stage: stage,
        quantity: r.unit == 'pcs' ? quantity.ceilToDouble() : quantity,
        unit: r.unit,
        waste: r.waste,
        detail: detail,
        packs: packs,
        pack: r.pack,
        weight: weight,
        estimated: r.estimated));
  }
  // Tying wire: about ten kilograms to a tonne of bar.
  for (final w in wire.entries) {
    out.add(MaterialLine(
        key: 'tieWire',
        stage: w.key,
        quantity: (w.value * 0.01 * 10).ceil() / 10,
        unit: 'kg',
        estimated: true));
  }
  int order(MaterialLine l) => costStages.indexOf(l.stage);
  final index = {for (final (i, l) in out.indexed) l: i};
  out.sort((a, b) => order(a) != order(b)
      ? order(a).compareTo(order(b))
      : index[a]!.compareTo(index[b]!));
  return List.unmodifiable(out);
}
