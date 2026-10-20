import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/analysis/build_schedule.dart';
import 'package:yusal/core/analysis/cost_estimate.dart';
import 'package:yusal/core/analysis/heat_loss.dart';
import 'package:yusal/core/analysis/site_analysis.dart';
import 'package:yusal/core/analysis/utility_plan.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/core/house_core.dart';

void main() {
  var n = 0;
  String next() => 'pl${n++}';
  const stamp = '2026-10-19T00:00:00Z';
  HouseDocument kz() => createKazakhTemplate(stamp, next);
  HouseDocument box({int width = 10000, int depth = 8000}) => createHouse(
      name: '方案',
      width: width,
      depth: depth,
      columns: 1,
      rows: 1,
      initialRoom: true,
      timestamp: stamp,
      newId: next);
  HouseDocument run(HouseDocument doc, String kind, Map<String, dynamic> args) {
    final result = executeCommand(extractDesignState(doc),
        DesignCommand(kind, args), CommandContext(newId: next, now: () => stamp));
    expect(result, isA<Applied>(),
        reason: result is Rejected ? result.message : kind);
    return composeDocument(doc.meta, (result as Applied).newState);
  }

  String? reject(HouseDocument doc, String kind, Map<String, dynamic> args) {
    final result = executeCommand(extractDesignState(doc),
        DesignCommand(kind, args), CommandContext(newId: next, now: () => stamp));
    return result is Rejected ? result.message : null;
  }

  HouseDocument roundTrip(HouseDocument doc) {
    expect(validateHouse(doc), isEmpty);
    final loaded = loadHouse(utf8.encode(encodeHouse(doc)));
    expect(loaded.isSuccess, true,
        reason: loaded.failure?.errors.map((e) => '${e.path} ${e.message}').join('; '));
    expect(loaded.document, doc);
    return loaded.document!;
  }

  group('hip roof', () {
    test('saves as version 4 and builds four planes up to the ridge', () {
      var doc = run(box(), 'SetRoof', {
        'roof': {'type': 'hip', 'pitchDeg': 30, 'overhang': 500}
      });
      expect(doc.schemaVersion, 4);
      expect(doc.roof.type, RoofType.hip);
      roundTrip(doc);
      final derived = deriveHouse(doc);
      final planes = derived.scene3d.where((e) => e.kind == 'RoofPlane');
      expect(planes, hasLength(4));
      expect(derived.scene3d.where((e) => e.kind == 'GableWall'), isEmpty);
      // Two trapezoids and two triangles over a 10 × 8 m house.
      expect(planes.map((p) => p.vertices.length ~/ 2).toList()..sort(),
          [3, 3, 4, 4]);
      final ridge = 3000 + 4000 * math.tan(math.pi / 6);
      final topZ = planes
          .expand((p) => p.vertices)
          .fold(0.0, (double z, v) => math.max(z, v.z));
      expect(topZ, closeTo(ridge, 0.5));
      final eave = 3000 - 500 * math.tan(math.pi / 6);
      final lowZ = planes
          .expand((p) => p.vertices.take(p.vertices.length ~/ 2))
          .fold(1e9, (double z, v) => math.min(z, v.z));
      expect(lowZ, closeTo(eave, 0.5));
    });

    test('a square house gets a pyramid', () {
      final doc = run(box(width: 9000, depth: 9000), 'SetRoof', {
        'roof': {'type': 'hip', 'pitchDeg': 25, 'overhang': 300}
      });
      final planes = deriveHouse(doc)
          .scene3d
          .where((e) => e.kind == 'RoofPlane')
          .toList();
      expect(planes, hasLength(4));
      expect(planes.every((p) => p.vertices.length == 6), true);
    });

    test('the pitch is validated like a gable roof', () {
      expect(
          reject(box(), 'SetRoof', {
            'roof': {'type': 'hip', 'pitchDeg': 75, 'overhang': 500}
          }),
          isNotNull);
    });

    test('a version 3 reader rejects hip roofs it cannot draw', () {
      final doc = run(box(), 'SetRoof', {
        'roof': {'type': 'hip', 'pitchDeg': 30, 'overhang': 500}
      });
      final raw = jsonDecode(encodeHouse(doc)) as Map<String, dynamic>;
      raw['schemaVersion'] = 3;
      final loaded = loadHouse(utf8.encode(jsonEncode(raw)));
      expect(loaded.isSuccess, false);
    });
  });

  group('cost estimate', () {
    test('every stage of the village house has a price', () {
      final doc = kz(), derived = deriveHouse(doc);
      final e = estimateCost(doc, derived);
      expect(e.currency, Currency.cny);
      for (final stage in ['found', 'walls', 'roof', 'openings', 'mep', 'finish'])
        expect(e.stageMaterials(stage), greaterThan(0), reason: stage);
      expect(e.stageMaterials('site'), 0);
      expect(e.labour, closeTo(e.materials * 0.35, 1));
      expect(e.total, closeTo((e.materials + e.labour) * 1.10, 1));
      // A village house of 130 m²: roughly 1,500–4,000 ¥ per m².
      expect(e.perArea, inInclusiveRange(1500, 4000));
      final kzt = estimateCost(doc, derived, currency: Currency.kzt);
      expect(kzt.total / e.total, inInclusiveRange(50, 100));
    });

    test('prices, markups and own lines are saved and undone', () {
      var doc = kz();
      final before = estimateCost(doc, deriveHouse(doc));
      final concrete =
          before.lines.firstWhere((l) => l.key == 'concrete');
      doc = run(doc, 'SetCost', {'priceKey': 'concrete', 'price': 600});
      doc = run(doc, 'SetCost', {'labourPct': 40, 'contingencyPct': 5});
      doc = run(doc, 'AddCostItem',
          {'name': '设计费', 'unit': '项', 'quantity': 100, 'price': 3000});
      expect(doc.schemaVersion, 4);
      final loaded = roundTrip(doc);
      final after = estimateCost(loaded, deriveHouse(loaded));
      expect(after.lines.firstWhere((l) => l.key == 'concrete').total,
          closeTo(concrete.quantity * 600, 1e-6));
      expect(after.labourPct, 40);
      expect(after.stageMaterials('other'), 3000);
      expect(after.stageLabour('other'), 0);
      // Clearing a price returns to the example.
      doc = run(doc, 'SetCost', {'priceKey': 'concrete', 'price': null});
      expect(doc.extras.cost.prices, isEmpty);
    });

    test('switching currency starts again from that currency\'s prices', () {
      var doc = run(kz(), 'SetCost', {'priceKey': 'rebar', 'price': 5000});
      doc = run(doc, 'SetCost', {'currency': Currency.kzt});
      expect(doc.extras.cost.prices, isEmpty);
      expect(
          estimateCost(doc, deriveHouse(doc))
              .lines
              .firstWhere((l) => l.key == 'rebar')
              .price,
          380000);
    });

    test('negative and out-of-range values are refused', () {
      final doc = kz();
      expect(reject(doc, 'SetCost', {'priceKey': 'concrete', 'price': -1}),
          isNotNull);
      expect(reject(doc, 'SetCost', {'labourPct': 400}), isNotNull);
      expect(reject(doc, 'AddCostItem', {'name': ' '}), isNotNull);
    });

    test('pitched and flat roofs are priced differently', () {
      final doc = kz();
      final flat = run(doc, 'SetRoof', {
        'roof': {'type': 'flat', 'parapetHeight': 900}
      });
      final gable = run(doc, 'SetRoof', {
        'roof': {'type': 'gable', 'ridgeDir': 'V', 'pitchDeg': 30, 'overhang': 500}
      });
      final keysFlat =
          estimateCost(flat, deriveHouse(flat)).lines.map((l) => l.key).toSet();
      final keysGable = estimateCost(gable, deriveHouse(gable))
          .lines
          .map((l) => l.key)
          .toSet();
      expect(keysFlat, containsAll(['roofSlab', 'roofMembrane', 'parapetWp']));
      expect(keysGable, containsAll(['roofCover', 'roofFrame', 'atticIns']));
      expect(keysGable.contains('roofSlab'), false);
    });
  });

  group('heat loss', () {
    test('U-values follow the layers and the user\'s conductivity', () {
      // 15 plaster + 100 wool + 270 aerated block + 15 plaster.
      final r = 15 / 760 + 100 / 40 + 270 / 140 + 15 / 760;
      expect(wallU(defaultWallLayers), closeTo(1 / (0.13 + r + 0.04), 1e-9));
      final better = [
        for (final l in defaultWallLayers)
          l.material == LayerMaterial.ins
              ? Layer(l.name, l.nameKk, l.thickness, l.material, lambda: 35)
              : l
      ];
      expect(wallU(better), lessThan(wallU(defaultWallLayers)));
      expect(groundFloorU(defaultFloorLayers, 130, 46, 0.4),
          inInclusiveRange(0.1, 0.4));
    });

    test('the village house loses a plausible amount of heat', () {
      final doc = kz(), loss = heatLoss(doc, deriveHouse(doc));
      expect(loss.deltaT, 45);
      expect(loss.total, greaterThan(0));
      expect(loss.perArea, inInclusiveRange(25, 120));
      expect(loss.boilerKw, greaterThanOrEqualTo(loss.total * 1.15 / 1000));
      final rooms = loss.spaces.where((s) =>
          doc.floors.first.rooms.any((r) => r.id == s.id));
      expect(rooms, hasLength(doc.floors.first.rooms.length));
      expect(rooms.every((s) => s.floor > 0 && s.roof > 0 && s.air > 0), true);
      final sum = loss.spaces.fold(0.0, (t, s) => t + s.total);
      expect(sum, closeTo(loss.total, 1e-6));
      expect(loss.fuel, greaterThan(0));
    });

    test('colder design weather raises the load in proportion', () {
      var doc = kz();
      final mild = heatLoss(doc, deriveHouse(doc));
      expect(reject(doc, 'SetHeat', {'field': 'outdoor', 'value': -70}),
          isNotNull);
      doc = run(doc, 'SetHeat', {'field': 'outdoor', 'value': -40});
      final cold = heatLoss(doc, deriveHouse(doc));
      expect(cold.total / mild.total, closeTo(60 / 45, 1e-9));
      expect(roundTrip(doc).extras.heat.outdoor, -40);
    });

    test('changing fuel brings that fuel\'s efficiency', () {
      final doc = run(kz(), 'SetHeat', {'fuel': FuelKind.gas});
      expect(doc.extras.heat.efficiency, 92);
      final loss = heatLoss(doc, deriveHouse(doc));
      expect(loss.fuel,
          closeTo(loss.seasonKwh / 0.92 / 9.3, 1e-6));
    });

    test('a thin wall gets advice in the issue list', () {
      final doc = run(kz(), 'SetLayers', {
        'group': 'wall',
        'layers': const [Layer('砖', 'Кірпіш', 370, LayerMaterial.block, lambda: 700)]
      });
      expect(doc.schemaVersion, 4);
      final checks = heatChecks(doc, heatLoss(doc, deriveHouse(doc)));
      expect(checks.map((c) => c.code), contains('H01'));
      expect(roundTrip(doc).extras.wallLayers.single.lambda, 700);
    });
  });

  group('utilities', () {
    test('the first layout lights every room and finds the entrance', () {
      final doc = kz(), derived = deriveHouse(doc);
      final spots = suggestUtilities(doc, derived, 0);
      int count(UtilityKind k) => spots.where((s) => s.kind == k).length;
      expect(count(UtilityKind.light),
          greaterThanOrEqualTo(doc.floors.first.rooms.length));
      expect(count(UtilityKind.panel), 1);
      expect(count(UtilityKind.lightSwitch), greaterThan(4));
      expect(count(UtilityKind.radiator), greaterThan(3));
      expect(count(UtilityKind.water), greaterThan(0));
      // Every point is inside the house.
      for (final s in spots) {
        expect(s.x, inInclusiveRange(0, doc.footprint.width), reason: '$s');
        expect(s.y, inInclusiveRange(0, doc.footprint.depth), reason: '$s');
      }
    });

    test('points are saved, measured, moved and dropped with their floor', () {
      var doc = kz();
      final floorId = doc.floors.first.id;
      final spots = suggestUtilities(doc, deriveHouse(doc), 0);
      doc = run(doc, 'AddUtilities', {
        'floorId': floorId,
        'points': [
          for (final s in spots) {'kind': s.kind, 'x': s.x, 'y': s.y}
        ]
      });
      expect(doc.schemaVersion, 4);
      expect(doc.extras.utilities, hasLength(spots.length));
      // Running it again adds nothing new.
      expect(suggestUtilities(doc, deriveHouse(doc), 0), isEmpty);
      final take = utilityTakeoff(roundTrip(doc));
      expect(take.lightCable, greaterThan(0));
      expect(take.powerCable, greaterThan(take.lightCable * 0.3));
      expect(take.waterPipe, greaterThan(0));
      expect(take.heatingPipe, greaterThan(0));
      final first = doc.extras.utilities.first;
      doc = run(doc, 'UpdateUtility', {'utilityId': first.id, 'x': 1234});
      expect(doc.extras.utilities.first.x, 1234);
      doc = run(doc, 'DeleteUtility', {'utilityId': first.id});
      expect(doc.extras.utilities, hasLength(spots.length - 1));
      // The cost estimate now measures the services.
      final e = estimateCost(doc, deriveHouse(doc));
      expect(e.lines.firstWhere((l) => l.key == 'cable').estimated, false);
      doc = run(doc, 'ClearUtilities', {'floorId': floorId});
      expect(doc.extras.utilities, isEmpty);
      expect(doc.schemaVersion, 3);
    });

    test('points on a deleted floor go with it', () {
      final start = box();
      var doc = run(start, 'AddFloor', {'floorId': start.floors.first.id});
      final upper = doc.floors.last.id;
      doc = run(doc, 'AddUtility',
          {'floorId': upper, 'kind': UtilityKind.light, 'x': 500, 'y': 500});
      doc = run(doc, 'DeleteFloor', {'floorId': upper});
      expect(doc.extras.utilities, isEmpty);
    });
  });

  group('site plan', () {
    test('a default plot fits the house with a front yard', () {
      var doc = run(kz(), 'SetSite', {});
      final site = doc.extras.site!;
      expect(site.houseY, 5000);
      expect(site.houseX * 2 + doc.footprint.width, site.width);
      expect(site.depth - site.houseY - doc.footprint.depth,
          greaterThanOrEqualTo(15000));
      expect(siteChecks(doc).map((c) => c.code), ['S08']);
      doc = run(doc, 'AddSiteItem', {
        'kind': SiteKind.gate,
        'x': 2000,
        'y': 0,
      });
      expect(siteChecks(doc), isEmpty);
      expect(roundTrip(doc).extras.site!.items.single.width, 4000);
    });

    test('sanitary gaps and overlaps are flagged on the plot', () {
      var doc = run(kz(), 'SetSite', {'fence': false});
      final s = doc.extras.site!;
      final behind = s.houseY + doc.footprint.depth;
      doc = run(doc, 'AddSiteItem', {
        'kind': SiteKind.toilet,
        'x': s.houseX,
        'y': behind + 3000,
        'id': 'wc'
      });
      doc = run(doc, 'AddSiteItem', {
        'kind': SiteKind.well,
        'x': s.houseX + 3000,
        'y': behind + 3000,
      });
      doc = run(doc, 'AddSiteItem', {
        'kind': SiteKind.barn,
        'x': s.houseX + 2000,
        'y': s.houseY + 2000,
      });
      final codes = siteChecks(doc).map((c) => c.code).toList();
      expect(codes, containsAll(['S05', 'S06', 'S03']));
      expect(siteChecks(doc).every((c) => c.site), true);
      doc = run(doc, 'UpdateSiteItem',
          {'siteItemId': 'wc', 'y': behind + 13000});
      expect(siteChecks(doc).where((c) => c.title.$1.contains('厕所')), isEmpty);
      doc = run(doc, 'RotateSiteItem', {'siteItemId': 'wc'});
      final wc = doc.extras.site!.items.firstWhere((i) => i.id == 'wc');
      expect((wc.width, wc.depth), (1500, 1200));
      doc = run(doc, 'ClearSite', {});
      expect(doc.extras.site, isNull);
    });

    test('a plot smaller than 3 m is refused', () {
      expect(reject(kz(), 'SetSite', {'width': 1000}), isNotNull);
    });
  });

  group('schedule', () {
    test('built-in stages, checks, dates and budgets', () {
      var doc = kz();
      expect(doc.extras.stages.map((s) => s.key), stageKeys);
      for (final key in stageKeys) {
        expect(stageNames[key], isNotNull);
        expect(stageChecks[key], isNotEmpty);
      }
      doc = run(doc, 'SetStage',
          {'stageKey': 'prep', 'start': '2027-04-01', 'status': StageStatus.done});
      doc = run(doc, 'SetStage', {'stageKey': 'found', 'toggleCheck': 2});
      doc = run(doc, 'SetStage', {'stageKey': 'found', 'toggleCheck': 0});
      doc = run(doc, 'SetStage', {'stageKey': 'found', 'toggleCheck': 2});
      doc = run(doc, 'SetStage',
          {'stageKey': 'found', 'status': StageStatus.doing, 'spent': 42000});
      expect(doc.schemaVersion, 4);
      final loaded = roundTrip(doc);
      final found = loaded.extras.stages[1];
      expect(found.checks, [0]);
      expect(found.spent, 42000);
      final plan = planStages(loaded.extras.stages);
      expect(formatDay(plan[0].start!), '2027-04-01');
      expect(formatDay(plan[1].start!), '2027-04-15');
      expect(formatDay(plan.last.end!), isNotEmpty);
      expect(progress(loaded.extras.stages),
          closeTo((1 + 0.9 / 6) / stageKeys.length, 1e-9));
      final budgets = stageBudgets(estimateCost(loaded, deriveHouse(loaded)));
      expect(budgets['found'], greaterThan(0));
      expect(budgets.containsKey('prep'), false);
    });

    test('own stages can be added and removed; built-in ones stay', () {
      var doc = run(kz(), 'AddStage',
          {'name': '打井', 'days': 3, 'after': 'found', 'id': 'well'});
      expect(doc.extras.stages[2].key, 'own-well');
      expect(reject(doc, 'DeleteStage', {'stageKey': 'roof'}), isNotNull);
      expect(reject(doc, 'SetStage', {'stageKey': 'prep', 'start': '27-4-1'}),
          isNotNull);
      doc = run(doc, 'DeleteStage', {'stageKey': 'own-well'});
      expect(doc.extras.stages.map((s) => s.key), stageKeys);
      doc = run(doc, 'ResetSchedule', {});
      expect(doc.extras.schedule, isEmpty);
    });
  });

  test('files without planning content keep version 3 and their bytes', () {
    final doc = kz();
    expect(doc.schemaVersion, 3);
    expect(encodeHouse(doc).contains('"cost"'), false);
    final again = loadHouse(utf8.encode(encodeHouse(doc))).document!;
    expect(encodeHouse(again), encodeHouse(doc));
  });
}
