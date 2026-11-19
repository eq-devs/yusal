import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:yusal/platform/update/code_push.dart';

class _FakeUpdater implements ShorebirdUpdater {
  _FakeUpdater({this.available = true, this.status = UpdateStatus.outdated});
  final bool available;
  UpdateStatus status;
  int checks = 0, updates = 0;
  bool failUpdate = false;

  @override
  bool get isAvailable => available;
  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    checks++;
    return status;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    updates++;
    if (failUpdate) {
      throw const UpdateException(
          message: 'x', reason: UpdateFailureReason.downloadFailed);
    }
  }

  @override
  Future<Patch?> readCurrentPatch() async => const Patch(number: 3);
  @override
  Future<Patch?> readNextPatch() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('downloads an outdated patch once per interval', () async {
    final u = _FakeUpdater();
    final push = CodePush(u);
    await push.check();
    await push.check();
    expect(u.checks, 1);
    expect(u.updates, 1);
    expect(await push.currentPatch(), 3);
  });

  test('up to date: no download', () async {
    final u = _FakeUpdater(status: UpdateStatus.upToDate);
    await CodePush(u).check();
    expect(u.updates, 0);
  });

  test('a failed download does not throw', () async {
    final u = _FakeUpdater()..failUpdate = true;
    await CodePush(u).check();
    expect(u.updates, 1);
  });

  test('unavailable updater: start and currentPatch are no-ops', () async {
    final u = _FakeUpdater(available: false);
    CodePush(u).start();
    expect(u.checks, 0);
    expect(await CodePush(u).currentPatch(), isNull);
  });
}
