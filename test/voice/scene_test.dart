import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/core/geometry/derived_house.dart';
import 'package:yusal/features/voice/model/scene.dart';

void main() {
  var n = 0;
  final doc = createKazakhTemplate('2026-10-14T00:00:00Z', () => 'kz${n++}');
  final floor = doc.floors.first;
  // As the editor names them: in document order.
  final aliases = {
    floor.id: 'f1',
    for (final (i, r) in floor.rooms.indexed) r.id: 'r${i + 1}',
    for (final (i, o) in floor.openings.indexed) o.id: 'o${i + 1}',
    for (final (i, u) in doc.extras.furniture.indexed) u.id: 'u${i + 1}',
  };
  String scene({String? selectedId}) => designScene(
      doc: doc,
      derived: deriveHouse(doc),
      floorIndex: 0,
      aliases: aliases,
      selectedId: selectedId);

  test('a design reads as a line per room with where it is and what is in it',
      () {
    final lines = scene().split('\n');
    expect(lines[0], 'house 10000x13000 mm, 1 floor, roof flat');
    expect(lines[1], startsWith('floor f1 "'));
    expect(lines.where((l) => l.startsWith(' r')), hasLength(8));
    // The kitchen: on the east wall, a door to the hall, one window.
    final kitchen = lines.singleWhere((l) => l.contains(' kitchen '));
    expect(kitchen, contains('x5900 y2300 4100x5400 22.1m2'));
    expect(kitchen, contains('| outer east |'));
    expect(kitchen, contains('| doors o14>r3 w800 |'));
    expect(kitchen, contains('| windows o4 east w1800 |'));
    expect(kitchen, contains('counter u27 u28, stove u29'));
    // The front door is told apart, and which rooms touch.
    expect(lines.join(), contains('o9 south w1000 main'));
    final beside = lines.singleWhere((l) => l.startsWith('beside: '));
    expect(beside, contains('r3-r4 east'));
    expect(beside, contains('r6-r7 north'));
  });

  test('ids stay in the app and the whole house is short', () {
    final text = scene();
    expect(text, isNot(contains('kz')));
    // A third of a page for eight rooms and forty pieces of furniture.
    expect(text.length, lessThan(2500));
  });

  test('what is selected is named', () {
    expect(scene(), isNot(contains('selected:')));
    expect(scene(selectedId: floor.rooms[3].id).split('\n'),
        contains('selected: r4'));
  });
}
