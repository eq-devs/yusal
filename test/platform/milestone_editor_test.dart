import 'package:flutter/material.dart';
import '../support/test_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/shared/settings/settings.dart';
import '../support/mock/mock_seed.dart';
import 'package:yusal/features/coop/pages/milestone_editor.dart';
import 'package:yusal/shared/ui/scope.dart';
import 'package:yusal/services/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;
import 'mock_backend_test.dart' show backend, terms;

void main() {
  testWidgets('the owner adds a milestone and saves a plan of 100%', (t) async {
    AppSettings.instance.lang = AppLang.zh;
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final b = backend()..signInAs(SeedIds.owner);
    final coop = await b.invite('app_team_wall', terms());
    await t.pumpWidget(TestScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        child: MaterialApp(
            builder: (_, child) => AppScope(child: child!),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => pushPage<void>(context,
                            (_) => MilestoneEditorPage(cooperation: coop)),
                        child: const Text('open')))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // The wall contract starts with its own point only: walls, 100%.
    expect(find.text('合计 100%'), findsOneWidget);
    await t.tap(find.byKey(const Key('ms-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ms-name-1')), '门窗');
    await t.enterText(find.byKey(const Key('ms-percent-1')), '10');
    await t.pumpAndSettle();
    expect(find.text('合计 110%'), findsOneWidget);
    await t.tap(find.byKey(const Key('milestones-save')));
    await t.pumpAndSettle();
    expect(b.cooperations[coop.id]!.milestones, hasLength(1));
    await t.enterText(find.byKey(const Key('ms-percent-0')), '90');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('milestones-save')));
    await t.pumpAndSettle();
    final saved = b.cooperations[coop.id]!.milestones;
    expect(saved.map((m) => m.key).last, 'c:门窗');
    expect(saved.fold(0, (s, m) => s + m.percent), 100);
  });
}
