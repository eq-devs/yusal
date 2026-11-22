import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/commands/house_spec.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

/// A one-storey 12 × 10 m house as a language model would describe it.
final Map<String, Object?> spec = {
  'name': 'Test',
  'width_mm': 12000,
  'depth_mm': 10000,
  'roof': 'gable',
  'floors': [
    {
      'rooms': [
        {
          'id': 'liv',
          'type': 'living',
          'name': 'Қонақ бөлме',
          'x_mm': 0,
          'y_mm': 0,
          'w_mm': 6000,
          'd_mm': 5000
        },
        {
          'id': 'kit',
          'type': 'kitchen',
          'x_mm': 6000,
          'y_mm': 0,
          'w_mm': 6000,
          'd_mm': 5000
        },
        {
          'id': 'b1',
          'type': 'bedroom',
          'x_mm': 0,
          'y_mm': 5000,
          'w_mm': 4000,
          'd_mm': 5000
        },
        {
          'id': 'cor',
          'type': 'custom',
          'name': 'Дәліз',
          'x_mm': 4000,
          'y_mm': 5000,
          'w_mm': 1500,
          'd_mm': 5000
        },
        {
          'id': 'b2',
          'type': 'bedroom',
          'x_mm': 5500,
          'y_mm': 5000,
          'w_mm': 4000,
          'd_mm': 5000
        },
        {
          'id': 'bath',
          'type': 'bathroom',
          'x_mm': 9500,
          'y_mm': 5000,
          'w_mm': 2500,
          'd_mm': 5000
        },
      ],
      'doors': [
        {'room': 'liv', 'side': 'south', 'main': true},
        {'room': 'liv', 'to': 'kit'},
        {'room': 'cor', 'to': 'b1'},
        {'room': 'cor', 'to': 'b2'},
        {'room': 'b2', 'to': 'bath'},
      ],
      'open': [
        ['liv', 'cor']
      ],
      'windows': [
        {'room': 'liv', 'side': 'west'},
        {'room': 'kit', 'side': 'south', 'count': 2},
        {'room': 'b1', 'side': 'north'},
        {'room': 'b2', 'side': 'north'},
        {'room': 'bath', 'side': 'east', 'width_mm': 600},
      ],
      'furniture': [
        {'room': 'liv', 'kind': 'sofa'},
        {'room': 'liv', 'kind': 'tvStand'},
        {'room': 'b1', 'kind': 'bed'},
        {'room': 'b1', 'kind': 'wardrobe'},
      ],
    }
  ],
};

void main() {
  var n = 0;
  String id() => 'id${n++}';

  test('a spec becomes a design with its rooms, openings and furniture', () {
    final r = buildHouseFromSpec(spec, '2026-11-15T00:00:00Z', id);
    expect(r.errors, isEmpty);
    expect(r.notes, isEmpty);
    final doc = r.document!;
    expect(validateHouse(doc), isEmpty);
    final floor = doc.floors.single;
    expect(floor.rooms, hasLength(6));
    expect(floor.rooms.map((r) => r.name), contains('Қонақ бөлме'));
    expect(
        floor.openings.where((o) => o.kind == OpeningKind.door), hasLength(5));
    expect(floor.openings.where((o) => o.kind == OpeningKind.window),
        hasLength(6));
    expect(doc.mainEntranceOpeningId, isNotNull);
    expect(doc.extras.furniture, hasLength(4));
    // Every room has a way in, and the bedrooms have windows.
    final rules = runChecks(doc, deriveHouse(doc)).map((c) => c.ruleId);
    expect(rules, isNot(contains('R04')));
    expect(rules, isNot(contains('R05')));
    expect(rules, isNot(contains('R08')));
  });

  test('overlapping rooms are refused with the reason', () {
    final bad = {
      'width_mm': 8000,
      'depth_mm': 8000,
      'floors': [
        {
          'rooms': [
            {
              'id': 'a',
              'type': 'living',
              'x_mm': 0,
              'y_mm': 0,
              'w_mm': 5000,
              'd_mm': 8000
            },
            {
              'id': 'b',
              'type': 'bedroom',
              'x_mm': 4000,
              'y_mm': 0,
              'w_mm': 4000,
              'd_mm': 8000
            },
          ]
        }
      ]
    };
    final r = buildHouseFromSpec(bad, '2026-11-15T00:00:00Z', id);
    expect(r.document, isNull);
    expect(r.errors.single, contains('overlap'));
  });

  test('two floors with a stair', () {
    final two = {
      'width_mm': 10000,
      'depth_mm': 8000,
      'floors': [
        {
          'rooms': [
            {
              'id': 'liv',
              'type': 'living',
              'x_mm': 0,
              'y_mm': 0,
              'w_mm': 7000,
              'd_mm': 8000
            },
            {
              'id': 'hall',
              'type': 'custom',
              'x_mm': 7000,
              'y_mm': 0,
              'w_mm': 3000,
              'd_mm': 8000
            },
          ],
          'doors': [
            {'room': 'hall', 'side': 'south'},
            {'room': 'hall', 'to': 'liv'}
          ],
        },
        {
          'rooms': [
            {
              'id': 'b1',
              'type': 'bedroom',
              'x_mm': 0,
              'y_mm': 0,
              'w_mm': 7000,
              'd_mm': 8000
            },
            {
              'id': 'hall',
              'type': 'custom',
              'x_mm': 7000,
              'y_mm': 0,
              'w_mm': 3000,
              'd_mm': 8000
            },
          ],
          'doors': [
            {'room': 'hall', 'to': 'b1'}
          ],
        }
      ],
      'stairs': [
        {
          'floor': 1,
          'x_mm': 7000,
          'y_mm': 4000,
          'w_mm': 3000,
          'd_mm': 4000,
          'type': 'L'
        }
      ],
    };
    final r = buildHouseFromSpec(two, '2026-11-15T00:00:00Z', id);
    expect(r.notes, isEmpty);
    expect(r.errors, isEmpty);
    expect(r.document!.floors, hasLength(2));
    expect(r.document!.floors.first.stairs, hasLength(1));
    expect(validateHouse(r.document!), isEmpty);
  });
}
