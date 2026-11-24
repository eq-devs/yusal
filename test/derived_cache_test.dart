import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';

void main() {
  var n = 0;
  final a = createKazakhTemplate('2026-10-14T00:00:00Z', () => 'a${n++}');
  final b = createKazakhTemplate('2026-10-14T00:00:00Z', () => 'b${n++}');

  test('the same document is derived once', () {
    expect(identical(deriveHouse(a), deriveHouse(a)), isTrue);
    final id = a.floors.first.id;
    expect(identical(deriveFloorBase(a, id), deriveFloorBase(a, id)), isTrue);
    expect(identical(deriveHouse(a).floors.first.base, deriveFloorBase(a, id)),
        isTrue);
  });

  test('another document gets its own result', () {
    expect(identical(deriveHouse(a), deriveHouse(b)), isFalse);
    expect(deriveHouse(b).floors.first.base.wallSegments.length,
        deriveHouse(a).floors.first.base.wallSegments.length);
  });

  test('the cache is bounded and recomputes what it dropped', () {
    final cache = DerivedCache<int, Object>(2);
    var runs = 0;
    Object get(Object doc) => cache.get(a, doc.hashCode, () {
          runs++;
          return Object();
        });
    final x = get(1);
    expect(identical(get(1), x), isTrue);
    get(2);
    get(3); // drops 1
    expect(runs, 3);
    expect(identical(get(1), x), isFalse);
    expect(runs, 4);
  });
}
