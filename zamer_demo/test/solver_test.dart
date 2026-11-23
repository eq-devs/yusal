import 'package:flutter_test/flutter_test.dart';
import 'package:zamer/solver.dart';

void main() {
  test('demo L-room closes and the misread wall is found', () {
    final r = RoomSolver(DemoRoom.sketch, DemoRoom.measurements).solve();
    for (final c in r.checks) {
      // ignore: avoid_print
      print(
          '${c.m.a}-${c.m.b} meas ${c.m.metres} fit ${c.fitted.toStringAsFixed(4)} loo ${c.looExpected?.toStringAsFixed(4)} drop ${c.costDrop.toStringAsFixed(1)}');
    }
    // ignore: avoid_print
    print(
        'gap ${r.rawGap} area ${r.area} suspects ${r.suspects.map((s) => '${s.m.a}-${s.m.b}')}');
    expect(r.rawGap, greaterThan(0.02));
    expect(r.suspects.length, 1);
    expect(r.suspects.first.m.a, 4);
    expect(r.suspects.first.looExpected!, closeTo(3.80, 0.01));
    expect(r.area, closeTo(6.2 * 5.1 - 2.4 * 1.7, 0.08));
  });

  test('clean rectangle has no suspects', () {
    final r = RoomSolver(const [
      P(0, 0),
      P(200, 4),
      P(198, 120),
      P(-2, 118)
    ], const [
      Measurement(0, 1, 4.002),
      Measurement(1, 2, 3.001),
      Measurement(2, 3, 3.998),
      Measurement(3, 0, 2.999),
    ]).solve();
    expect(r.suspects, isEmpty);
    expect(r.area, closeTo(12.0, 0.02));
    expect(r.rightAngles.every((e) => e), isTrue);
  });
}
