import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/data/mock/mock_seed.dart';
import 'package:yusal/platform/domain/models.dart';
import 'package:yusal/platform/ui/me/admin_page.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

Future<MockBackend> pumpAdmin(WidgetTester t, String account) async {
  AppSettings.instance.lang = AppLang.zh;
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final b = MockBackend(latency: Duration.zero, autoReviewDelay: null)
    ..signInAs(account);
  await t.pumpWidget(PlatformScope(
      repos: b,
      store: ProjectStore(fileSystem: MemoryFiles()),
      child: MaterialApp(
          builder: (_, child) => AppScope(child: child!),
          home: const AdminPage())));
  await t.pumpAndSettle();
  return b;
}

void main() {
  testWidgets('the back office opens on the to-do list and every tab loads',
      (t) async {
    final b = await pumpAdmin(t, SeedIds.admin);
    expect(find.text('工作台'), findsWidgets);
    expect(find.textContaining('举报'), findsWidgets);
    for (final tab in ['审核', '用户', '更多']) {
      await t.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(tab)));
      await t.pumpAndSettle();
    }
    expect(find.text('推送节制'), findsOneWidget);
    await t.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('用户')));
    await t.pumpAndSettle();
    expect(find.text(b.accounts[SeedIds.mason]!.displayName), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('swiping a pending demand right approves it', (t) async {
    final b = await pumpAdmin(t, SeedIds.admin);
    final d = b.demands.values.firstWhere((d) => d.ownerId == SeedIds.owner);
    b.demands[d.id] = d.copyWith(status: DemandStatus.pendingReview);
    b.notify();
    await t.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('审核')));
    await t.pumpAndSettle();
    await t.drag(find.text(d.current.title), const Offset(900, 0));
    await t.pumpAndSettle();
    expect(b.demands[d.id]!.status, DemandStatus.open);
    expect(b.auditLog.last.action, 'approve');
  });

  testWidgets('an account without a role sees no back office', (t) async {
    await pumpAdmin(t, SeedIds.owner);
    expect(find.text('没有后台权限'), findsOneWidget);
  });
}
