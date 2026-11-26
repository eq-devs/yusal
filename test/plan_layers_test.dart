// The plan repaints only when what it draws changes; drafts, handles and
// guides are drawn by the overlay over it.
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/commands/room_commands.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';

void main() {
  var n = 0;
  final doc = createHouse(
      name: 'L',
      width: 12000,
      depth: 10000,
      columns: 2,
      rows: 2,
      initialRoom: true,
      timestamp: '2026-11-26T00:00:00Z',
      newId: () => 'l${n++}');
  final base = deriveFloorBase(doc, doc.floors.first.id);
  final room = doc.floors.first.rooms.first.id;

  FloorPlanPainter plan(
          {PlanRect? draft,
          List<Offset> measure = const [],
          String? selectedRoom,
          String label = 'Room',
          bool layered = true}) =>
      FloorPlanPainter(base, {room: label}, const {},
          draft: draft,
          measure: measure,
          selectedRoom: selectedRoom,
          layered: layered);

  test('a draft or a measurement repaints only the overlay', () {
    final before = plan();
    expect(plan(draft: const PlanRect(0, 0, 1000, 1000)).shouldRepaint(before),
        isFalse);
    expect(plan(measure: const [Offset(1, 1)]).shouldRepaint(before), isFalse);
  });

  test('what the plan draws repaints it', () {
    final before = plan();
    expect(plan(selectedRoom: room).shouldRepaint(before), isTrue);
    expect(plan(label: 'Kitchen').shouldRepaint(before), isTrue);
  });

  test('a painter drawing both always repaints', () {
    expect(plan(layered: false).shouldRepaint(plan(layered: false)), isTrue);
  });
}
