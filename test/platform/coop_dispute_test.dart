import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/platform/ui/widgets.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/ui/coop/coop_page.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;
import 'mock_backend_test.dart' show backend, terms;

void main() {
  testWidgets('disputing an end asks for the reason without a busy spinner',
      (t) async {
    AppSettings.instance.lang = AppLang.zh;
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final b = backend()..signInAs(SeedIds.owner);
    final coop = await b.invite('app_team_wall', terms());
    b.signInAs(SeedIds.team);
    await b.confirm(coop.id);
    await b.requestEnd(coop.id, '完工了');
    b.signInAs(SeedIds.owner);
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        isDemo: true,
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: CooperationPage(cooperationId: coop.id))));
    await t.pumpAndSettle();
    await t.tap(find.text('提出异议'));
    // Settles: nothing spins while the person types the reason.
    await t.pumpAndSettle();
    expect(find.byType(SheetBody), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await t.enterText(find.byType(TextField), '还差收尾');
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect((await b.cooperation(coop.id))!.endRequest!.dispute, '还差收尾');
  });
}
