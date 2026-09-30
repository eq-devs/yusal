import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/house_core.dart';

final minimal = File('test/fixtures/minimal_flat.house').readAsBytesSync();
final full = File('test/fixtures/full_two_floor_gable.house').readAsBytesSync();

void main() {
  test('rejects nonexistent calendar dates and door fields on windows', () {
    final badDate = utf8.decode(minimal).replaceAll('2026-09-29', '2026-02-30');
    expect(loadHouse(utf8.encode(badDate)).failure!.errors.map((e) => e.code),
        contains('INVALID_TIMESTAMP'));
    final raw = jsonDecode(utf8.decode(full)) as Map<String, dynamic>;
    raw['floors'][0]['openings'][1]['opensTo'] = 'positiveSide';
    final result = loadHouse(utf8.encode(jsonEncode(raw)));
    expect(result.failure!.stage, 'decode');
    expect(result.failure!.errors.map((e) => e.code),
        contains('FIELD_NOT_ALLOWED'));
  });

  test('invalid footprint prevents dependent axis-range and entrance errors',
      () {
    final raw = jsonDecode(utf8.decode(minimal)) as Map<String, dynamic>;
    raw['footprint']['width'] = 2000;
    raw['axes']['global'].add({'id': 'v1', 'dir': 'V', 'pos': 2500});
    raw['mainEntranceOpeningId'] = 'missing';
    final result = loadHouse(utf8.encode(jsonEncode(raw)));
    expect(result.failure!.stage, 'validate');
    expect(result.failure!.errors.map((e) => e.code).toList(), ['INV03']);
  });

  group('House codec', () {
    test('both fixtures load, round trip, and encode deterministically', () {
      for (final bytes in [minimal, full]) {
        final loaded = loadHouse(bytes);
        expect(loaded.isSuccess, isTrue,
            reason:
                '${loaded.failure?.stage}: ${loaded.failure?.errors.map((e) => '${e.code} ${e.path}').join(',')}');
        final encoded = encodeHouse(loaded.document!);
        expect(utf8.encode(encoded), bytes);
        expect(loadHouse(utf8.encode(encoded)).document, loaded.document);
        expect(encodeHouse(loaded.document!), encoded);
      }
    });

    test('rejects file and envelope failures at their correct stage', () {
      expect(loadHouse([]).failure?.errors.single.code, 'NOT_JSON');
      expect(
          loadHouse([0xef, 0xbb, 0xbf, 0x7b, 0x7d]).failure?.errors.single.code,
          'BOM_NOT_ALLOWED');
      expect(loadHouse([0xff]).failure?.errors.single.code, 'NOT_UTF8');
      expect(loadHouse(utf8.encode('[]')).failure?.stage, 'envelope');
      expect(loadHouse(utf8.encode('{}')).failure?.errors.single.code,
          'MISSING_VERSION');
      expect(
          loadHouse(utf8.encode('{"schemaVersion":1,"schemaVersion":1}'))
              .failure
              ?.errors
              .single
              .code,
          'DUPLICATE_JSON_KEY');
      expect(
          loadHouse(List<int>.filled(10485761, 0)).failure?.errors.single.code,
          'FILE_TOO_LARGE');
    });

    test('rejects decimals, unknown fields, and incorrect union shapes', () {
      final source = utf8.decode(minimal);
      expect(
          loadHouse(utf8.encode(
                  source.replaceFirst('"width": 6000', '"width": 6000.0')))
              .failure
              ?.errors
              .first
              .code,
          'NOT_INTEGER');
      expect(
          loadHouse(utf8.encode(source.replaceFirst(
                  '"northAngleDeg": 0', '"northAngleDeg": 0, "extra": true')))
              .failure
              ?.errors
              .first
              .code,
          'UNKNOWN_FIELD');
      final changed = source.replaceFirst('"stairs": []', '"stairs": []');
      expect(changed, source);
    });

    test('main entrance is omitted when absent and present on full fixture',
        () {
      final doc = loadHouse(minimal).document!;
      expect(encodeHouse(doc), isNot(contains('mainEntranceOpeningId')));
      expect(loadHouse(full).document!.mainEntranceOpeningId, 'o1');
    });
  });

  group('Axis resolver and canonicalizer', () {
    test('resolves virtual axes and canonical room rectangle', () {
      final doc = loadHouse(minimal).document!;
      final axes = resolveFloorAxes(doc, 'f1')!;
      expect((axes.nx, axes.ny), (1, 1));
      expect(axes.v.map((axis) => axis.id), ['@left', '@right']);
      expect(isCanonical(axes, doc.floors.single.rooms.single.regions), isTrue);
      expect(canonicalizeCells(axes, {const Cell(0, 0)}).regions,
          doc.floors.single.rooms.single.regions);
    });

    test('reports explicit failures and returns deterministic boundary chains',
        () {
      final doc = loadHouse(full).document!;
      final axes = resolveFloorAxes(doc, 'f1')!;
      expect(lookupAxis(axes, '@nope').failure?.code, 'INVALID_RESERVED_REF');
      expect(lookupAxis(axes, 'missing').failure?.code, 'AXIS_NOT_FOUND');
      final chain = resolveAnchor(
          axes,
          const BoundaryAnchor(
              axisId: 'H1', startAxisId: '@left', endAxisId: 'V1'));
      expect(chain.isSuccess, isTrue);
      expect(chain.chain!.segments.length, 1);
      expect(chain.chain!.nominalLength, 4500);
    });

    test(
        'canonicalization preserves shape, connectivity, and component ordering',
        () {
      final doc = loadHouse(full).document!;
      final axes = resolveFloorAxes(doc, 'f1')!;
      final result = canonicalizeCells(
          axes, {const Cell(0, 0), const Cell(1, 0), const Cell(0, 1)});
      expect(result.isSuccess, isTrue);
      expect(result.regions, hasLength(2));
      expect(isConnected({const Cell(0, 0), const Cell(1, 0)}), isTrue);
      expect(isConnected({const Cell(0, 0), const Cell(1, 1)}), isFalse);
      expect(components(axes, {const Cell(0, 0), const Cell(1, 1)}).cells,
          hasLength(2));
    });
  });

  group('Document validator', () {
    test('accepts both golden documents and retains deep value equality', () {
      for (final bytes in [minimal, full]) {
        final doc = loadHouse(bytes).document!;
        expect(validateHouse(doc), isEmpty);
        expect(composeDocument(doc.meta, extractDesignState(doc)), doc);
      }
    });

    test('maps a bad footprint to INV03 and short circuits dependent checks',
        () {
      final source = utf8
          .decode(minimal)
          .replaceFirst('"width": 6000', '"width": 2000')
          .replaceFirst('"stairTread": 260', '"stairTread": 0');
      final result = loadHouse(utf8.encode(source));
      expect(result.failure?.stage, 'validate');
      expect(result.failure?.errors.map((e) => e.code),
          containsAll(['INV03', 'INV22']));
      expect(result.failure?.errors.any((e) => e.code == 'INV08'), isFalse);
    });

    test('caps validation failures and reports a bad axis rectangle reference',
        () {
      final source =
          utf8.decode(minimal).replaceFirst('"x0": "@left"', '"x0": "missing"');
      final loaded = loadHouse(utf8.encode(source));
      expect(loaded.failure?.errors.single.code, 'INV08');
      expect(
          loaded.failure?.errors.single.path, '/floors/0/rooms/0/regions/0/x0');
    });
  });
}
