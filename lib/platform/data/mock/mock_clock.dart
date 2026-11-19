/// Time source of the mock backend. Developer tools move it forward to
/// check expiry, follow-ups, unilateral ends and review windows.
class MockClock {
  MockClock([DateTime? start]) : _base = start;
  final DateTime? _base;
  Duration offset = Duration.zero;

  DateTime now() => (_base ?? DateTime.now()).add(offset);

  void advance(Duration d) => offset += d;
}
