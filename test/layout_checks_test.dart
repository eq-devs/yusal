import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/checks/check_engine.dart';
import 'package:yusal/core/commands/house_spec.dart';
import 'package:yusal/core/commands/house_templates.dart';
import 'package:yusal/core/geometry/derived_house.dart';

Map<String, dynamic> spec(
        {required String bathDoorTo, bool kitchenWindow = true}) =>
    {
      'name': 'checks',
      'width_mm': 9000,
      'depth_mm': 6000,
      'floors': [
        {
          'rooms': [
            {
              'id': 'hall',
              'name': 'Hall',
              'type': 'custom',
              'x_mm': 0,
              'y_mm': 0,
              'w_mm': 3000,
              'd_mm': 6000
            },
            {
              'id': 'kit',
              'name': 'Kitchen',
              'type': 'kitchen',
              'x_mm': 3000,
              'y_mm': 0,
              'w_mm': 3000,
              'd_mm': 6000
            },
            {
              'id': 'bath',
              'name': 'Bath',
              'type': 'bathroom',
              'x_mm': 6000,
              'y_mm': 0,
              'w_mm': 3000,
              'd_mm': 3000
            },
            {
              'id': 'cor',
              'name': 'Corridor',
              'type': 'custom',
              'x_mm': 6000,
              'y_mm': 3000,
              'w_mm': 3000,
              'd_mm': 3000
            },
          ],
          'doors': [
            {'room': 'hall', 'side': 'south', 'main': true},
            {'room': 'hall', 'to': 'kit'},
            {'room': 'kit', 'to': 'cor'},
            {'room': 'bath', 'to': bathDoorTo},
          ],
          'windows': [
            if (kitchenWindow) {'room': 'kit', 'side': 'south'},
          ],
        }
      ],
    };

List<String> rules(Map<String, dynamic> s) {
  var n = 0;
  final r = buildHouseFromSpec(s, '2026-11-15T00:00:00Z', () => 'id${n++}');
  expect(r.errors, isEmpty);
  final doc = r.document!;
  return runChecks(doc, deriveHouse(doc)).map((c) => c.ruleId).toList();
}

void main() {
  test('a bathroom door into the kitchen is pointed out', () {
    expect(rules(spec(bathDoorTo: 'kit')), contains('R11'));
    expect(rules(spec(bathDoorTo: 'cor')), isNot(contains('R11')));
  });

  test('a kitchen without a window is pointed out', () {
    expect(
        rules(spec(bathDoorTo: 'cor', kitchenWindow: false)), contains('R12'));
    expect(rules(spec(bathDoorTo: 'cor')), isNot(contains('R12')));
  });

  test('the built-in templates pass both', () {
    for (final kind in houseTemplates.keys) {
      var n = 0;
      final doc =
          createTemplate(kind, '2026-11-15T00:00:00Z', () => 'id${n++}');
      final found = runChecks(doc, deriveHouse(doc)).map((c) => c.ruleId);
      expect(found, isNot(contains('R11')), reason: kind);
      expect(found, isNot(contains('R12')), reason: kind);
    }
  });
}
