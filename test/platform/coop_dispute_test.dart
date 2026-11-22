import 'package:flutter/material.dart';
import '../support/test_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/service/settings/settings.dart';
import '../support/mock/mock_seed.dart';
import 'package:yusal/features/coop/page.dart';
import 'package:yusal/service/storage/project_store.dart';
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
    await t.pumpWidget(TestScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
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
