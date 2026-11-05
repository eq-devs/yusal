import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/ui/coop/milestone_editor.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
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
    await t.pumpWidget(PlatformScope(
        repos: b,
        store: ProjectStore(fileSystem: MemoryFiles()),
        isDemo: true,
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
    expect(find.text('合计 100%'), findsOneWidget);
    await t.tap(find.byKey(const Key('ms-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ms-name-4')), '门窗');
    await t.enterText(find.byKey(const Key('ms-percent-4')), '10');
    await t.pumpAndSettle();
    expect(find.text('合计 110%'), findsOneWidget);
    await t.tap(find.byKey(const Key('milestones-save')));
    await t.pumpAndSettle();
    expect(b.cooperations[coop.id]!.milestones, hasLength(4));
    await t.enterText(find.byKey(const Key('ms-percent-3')), '5');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('milestones-save')));
    await t.pumpAndSettle();
    final saved = b.cooperations[coop.id]!.milestones;
    expect(saved.map((m) => m.key).last, 'c:门窗');
    expect(saved.fold(0, (s, m) => s + m.percent), 100);
  });
}
