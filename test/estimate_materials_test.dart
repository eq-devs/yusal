import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/analysis/cost_estimate.dart';
import 'package:yusal/features/editor/engine/core/analysis/house_analysis.dart';
import 'package:yusal/features/editor/engine/core/analysis/materials.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/repository/price_repository.dart';

void main() {
  var n = 0;
  String next() => 'em${n++}';
  const stamp = '2026-10-19T00:00:00Z';
  HouseDocument kz() => createKazakhTemplate(stamp, next);
  HouseDocument run(HouseDocument doc, String kind, Map<String, dynamic> args) {
    final result = executeCommand(
        extractDesignState(doc),
        DesignCommand(kind, args),
        CommandContext(newId: next, now: () => stamp));
    expect(result, isA<Applied>(),
        reason: result is Rejected ? result.message : kind);
    return composeDocument(doc.meta, (result as Applied).newState);
  }

  CostEstimate cost(HouseDocument doc, {PriceBook? book}) =>
      estimateCost(doc, deriveHouse(doc), currency: Currency.kzt, book: book);
  CostLine line(CostEstimate e, String key) =>
      e.lines.firstWhere((l) => l.key == key);

  test('tile finishes inherit the existing finish quote until overridden', () {
    final doc = run(kz(), 'SetCost', {'priceKey': 'finishArea', 'price': 18000});
    expect(line(cost(doc), 'finishTileArea').price, 18000);
    final own = run(doc, 'SetCost', {'priceKey': 'finishTileArea', 'price': 15500});
    expect(line(cost(own), 'finishTileArea').price, 15500);
    expect(line(cost(own), 'finishArea').price, 18000);
  });

  group('lines the estimate used to miss', () {
    test('belts, lintels, gutters, scaffolding, delivery and connections', () {
      final e = cost(kz());
      expect(e.lines.any((l) => l.key == 'gutter'), false,
          reason: 'a flat roof drains inside');
      final gable = run(kz(), 'SetRoof', {
        'roof': {
          'type': 'gable',
          'ridgeDir': 'H',
          'pitchDeg': 30,
          'overhang': 400
        }
      });
      expect(line(cost(gable), 'gutter').quantity, greaterThan(0));
      for (final key in [
        'ringBeam',
        'lintel',
        'scaffold',
        'delivery',
        'connection'
      ]) {
        expect(line(e, key).quantity, greaterThan(0), reason: key);
      }
      // A belt runs on top of every load-bearing wall of each floor.
      final doc = kz();
      final s = structureTakeoff(doc, deriveHouse(doc));
      expect(s.beltExterior, greaterThan(0));
      expect(s.lintels, greaterThan(0));
      expect(s.lintelLength, greaterThan(s.lintels * 2 * lintelBearing));
      // The national average for a self-built house is near 190,000 ₸/m².
      expect(e.perArea, inInclusiveRange(120000, 280000));
    });
  });

  group('labour', () {
    test('by the work done uses a rate per line, own rates win', () {
      var doc = run(kz(), 'SetCost', {'labourByWork': true});
      final e = cost(doc);
      expect(e.labourByWork, true);
      final concrete = line(e, 'concrete');
      expect(
          e.lineLabour(concrete),
          closeTo(concrete.quantity * defaultLabour[Currency.kzt]!['concrete']!,
              1e-6));
      // Hired services have no labour on top.
      expect(e.lineLabour(line(e, 'delivery')), 0);
      // The two ways of pricing labour land in the same region.
      final share = e.labour / e.materials;
      expect(share, inInclusiveRange(0.2, 0.55));

      doc =
          run(doc, 'SetCost', {'labourKey': 'concrete', 'labourPrice': 12345});
      final own = line(cost(doc), 'concrete');
      expect(own.labourRate, 12345);
      expect(own.ownLabour, true);
      doc = run(doc, 'SetCost', {'labourKey': 'concrete', 'labourPrice': null});
      expect(line(cost(doc), 'concrete').ownLabour, false);
    });

    test('a stage the family builds itself has no labour', () {
      final before = cost(kz());
      var doc = run(kz(), 'SetCost', {'selfStage': 'walls', 'self': true});
      final e = cost(doc);
      expect(e.stageLabour('walls'), 0);
      expect(e.stageMaterials('walls'), before.stageMaterials('walls'));
      expect(e.total, lessThan(before.total));
      doc = run(doc, 'SetCost', {'selfStage': 'walls', 'self': false});
      expect(cost(doc).total, closeTo(before.total, 1e-6));
    });
  });

  group('prices by source', () {
    test('own beats the region, the region beats the example', () {
      const book = PriceBook(region: 'astana', currency: Currency.kzt, prices: {
        'concrete': PriceQuote(39200, source: 'stat', date: '2026-09'),
        'rebar': PriceQuote(339000, source: 'stat', date: '2026-06'),
      }, labour: {
        'concrete':
            PriceQuote(22000, source: 'market', date: '2026-10-01')
      });
      var doc = kz();
      final plain = cost(doc);
      final e = cost(doc, book: book);
      expect(line(e, 'concrete').price, 39200);
      expect(line(e, 'concrete').source, PriceSource.region);
      expect(line(e, 'concrete').quote!.date, '2026-09');
      expect(line(e, 'cushion').source, PriceSource.example);
      expect(e.examplePrices, plain.examplePrices - 2);
      // Knowing more narrows the range.
      expect(e.spreadShare, lessThan(plain.spreadShare));
      expect(e.low, lessThan(e.total));
      expect(e.high, greaterThan(e.total));

      doc = run(doc, 'SetCost', {'priceKey': 'concrete', 'price': 41000});
      final own = cost(doc, book: book);
      expect(line(own, 'concrete').price, 41000);
      expect(line(own, 'concrete').source, PriceSource.own);
      expect(own.spreadShare, lessThan(e.spreadShare));

      // A list in another currency is not used.
      final cny = estimateCost(kz(), deriveHouse(kz()), book: book);
      expect(line(cny, 'concrete').source, PriceSource.example);
    });

    test('brick and cinder block are priced apart from aerated block', () {
      final aerated = cost(kz());
      final doc = run(kz(), 'SetCost', {'outerUnit': MasonryUnit.brick});
      final brick = cost(doc);
      expect(line(brick, 'masonryExt').price,
          masonryPrices[Currency.kzt]![MasonryUnit.brick]);
      expect(
          line(brick, 'masonryInt').price, line(aerated, 'masonryInt').price);
      const book = PriceBook(region: 'kz', currency: Currency.kzt, prices: {
        'masonry_brick':
            PriceQuote(50000, source: 'team', date: '2026-11')
      });
      expect(line(cost(doc, book: book), 'masonryExt').price, 50000);
      expect(line(cost(kz(), book: book), 'masonryExt').source,
          PriceSource.example);
    });

    test("a price list is read from the back end's answer", () {
      final book = priceBookFromJson({
        'region': 'almaty',
        'currency': 'kzt',
        'prices': {
          'concrete': {'price': 30400, 'source': 'stat', 'date': '2026-09'},
          'broken': 'x'
        },
        'labour': <String, dynamic>{}
      });
      expect(book.region, 'almaty');
      expect(book.prices.keys, ['concrete']);
      expect(book.prices['concrete']!.price, 30400);
    });
  });

  group('the settings are saved', () {
    test('units, labour, self-build and region survive a round trip', () {
      var doc = kz();
      doc = run(doc, 'SetCost', {'outerUnit': MasonryUnit.cinder});
      doc = run(doc, 'SetCost', {'labourByWork': true});
      doc = run(doc, 'SetCost', {'labourKey': 'rebar', 'labourPrice': 70000});
      doc = run(doc, 'SetCost', {'selfStage': 'finish', 'self': true});
      doc = run(doc, 'SetCost', {'region': 'almaty'});
      doc = run(doc, 'SetFoundation', {'type': FoundationType.pile});
      doc = run(doc, 'SetFoundation', {'field': 'pileStep', 'value': 1800});
      expect(validateHouse(doc), isEmpty);
      final loaded = loadHouse(utf8.encode(encodeHouse(doc)));
      expect(loaded.isSuccess, true);
      expect(loaded.document, doc);
      final c = loaded.document!.extras.cost;
      expect(c.outerUnit, MasonryUnit.cinder);
      expect(c.labourByWork, true);
      expect(c.labourPrices, {'rebar': 70000});
      expect(c.selfBuild, ['finish']);
      expect(c.region, 'almaty');
      expect(loaded.document!.extras.foundation.type, FoundationType.pile);
      expect(loaded.document!.extras.foundation.pileStep, 1800);
      doc = run(doc, 'SetCost', {'region': null});
      expect(doc.extras.cost.region, isNull);
    });

    test('a design that changed none of them is written as before', () {
      final text = encodeHouse(kz());
      for (final word in [
        'outerUnit',
        'labourByWork',
        'selfBuild',
        'pileDia',
        'slabBarStep'
      ]) {
        expect(text.contains(word), false, reason: word);
      }
    });
  });

  group('foundation kinds', () {
    test('a slab covers the house and has no strips', () {
      final doc = run(kz(), 'SetFoundation', {'type': FoundationType.slab});
      final q = foundationTakeoff(doc, deriveHouse(doc));
      expect(q.strips, isEmpty);
      expect(q.slabRects, isNotEmpty);
      final area = q.slabRects.fold(0.0, (s, r) => s + r.area);
      expect(
          q.concrete, closeTo(area * doc.extras.foundation.slabThickness, 1));
      // More concrete than strips under the same house.
      final strip = foundationTakeoff(kz(), deriveHouse(kz()));
      expect(q.concrete, greaterThan(strip.concrete));
      expect(line(cost(doc), 'concrete').quantity, greaterThan(0));
    });

    test('piles stand at the ends of the beams and between them', () {
      final doc = run(kz(), 'SetFoundation', {'type': FoundationType.pile});
      final q = foundationTakeoff(doc, deriveHouse(doc));
      expect(q.strips, isNotEmpty);
      expect(q.piles.length, greaterThan(4));
      expect(q.pileConcrete, greaterThan(0));
      expect(q.pileBarLength, greaterThan(0));
      // Closer piles, more of them.
      final dense =
          run(doc, 'SetFoundation', {'field': 'pileStep', 'value': 1000});
      expect(foundationTakeoff(dense, deriveHouse(dense)).piles.length,
          greaterThan(q.piles.length));
    });
  });

  group('materials list', () {
    test('what to buy comes with waste and whole packs', () {
      final doc = kz();
      final derived = deriveHouse(doc);
      final list = materialList(doc, derived);
      MaterialLine m(String key) => list.firstWhere((l) => l.key == key);
      for (final l in list) {
        expect(l.quantity, greaterThan(0), reason: l.key);
        expect(l.quantity.isFinite, true, reason: l.key);
        if (l.packs != null) expect(l.packs, greaterThan(0), reason: l.key);
      }
      // Concrete is ordered 3% over the measured volume of the foundation.
      final found = foundationTakeoff(doc, derived);
      final concrete =
          list.firstWhere((l) => l.key == 'concrete' && l.stage == 'found');
      expect(concrete.waste, 3);
      expect(concrete.quantity, closeTo(found.concrete / 1e9 * 1.03, 0.01));
      // Rebar is bought in whole 11.7 m bars.
      final bars = list.where((l) => l.key == 'rebar' && l.stage == 'found');
      expect(bars, isNotEmpty);
      for (final b in bars) {
        expect(b.packs! * barLength, greaterThanOrEqualTo(b.quantity - 1e-6));
        expect(b.weight, greaterThan(0));
      }
      // Blocks: 600 × 200 on the face, so 8.33 per m² of wall, plus waste.
      final masonry = masonryVolumes(
          doc, wallTakeoff(doc, derived), structureTakeoff(doc, derived));
      final blocks = m('blockAerated');
      expect(blocks.unit, 'pcs');
      final thickness = doc.defaults.outerWallThickness / 1000;
      expect(blocks.quantity,
          greaterThan(masonry.exterior / (0.6 * 0.2 * thickness)));
      // The stages come in building order.
      final order = [for (final l in list) costStages.indexOf(l.stage)];
      expect(order, [...order]..sort());
    });

    test('brick walls list bricks and mortar, not blocks and glue', () {
      var doc = run(kz(), 'SetCost', {'outerUnit': MasonryUnit.brick});
      doc = run(doc, 'SetCost', {'innerUnit': MasonryUnit.brick});
      final keys =
          materialList(doc, deriveHouse(doc)).map((l) => l.key).toSet();
      expect(keys.contains('brick'), true);
      expect(keys.contains('cement'), true);
      expect(keys.contains('blockAerated'), false);
      expect(keys.contains('glue'), false);
    });

    test('a pitched roof lists timber and sheets, a flat one a membrane', () {
      final flat = materialList(kz(), deriveHouse(kz()));
      expect(flat.any((l) => l.key == 'timber'), false);
      expect(flat.any((l) => l.key == 'roofRoll'), true);
      final doc = run(kz(), 'SetRoof', {
        'roof': {
          'type': 'gable',
          'ridgeDir': 'H',
          'pitchDeg': 30,
          'overhang': 400
        }
      });
      final keys =
          materialList(doc, deriveHouse(doc)).map((l) => l.key).toSet();
      expect(keys.contains('timber'), true);
      expect(keys.contains('roofSheet'), true);
      expect(keys.contains('roofRoll'), false);
    });
  });
}
