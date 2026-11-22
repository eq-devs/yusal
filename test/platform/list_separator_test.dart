import 'package:flutter/material.dart';
import '../support/test_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/shared/settings/settings.dart';
import '../support/mock/mock_backend.dart';
import 'package:yusal/features/profile/widgets/profile_card.dart';
import 'package:yusal/shared/l10n/l10n.dart';
import 'package:yusal/services/storage/project_store.dart';
import '../storage_test.dart' show MemoryFiles;

/// Lists of trades and regions are joined with 、 only in Chinese; a
/// Russian or Kazakh screen showed "Каменщик、Бетонщик".
void main() {
  tearDown(() => AppSettings.instance.lang = AppLang.zh);

  for (final (lang, sep) in [
    (AppLang.ru, ', '),
    (AppLang.kk, ', '),
    (AppLang.zh, '、')
  ]) {
    testWidgets('a worker card lists trades with "$sep" in ${lang.name}',
        (t) async {
      AppSettings.instance.lang = lang;
      final b = MockBackend(latency: Duration.zero);
      final profile = b.profiles.values.firstWhere((p) => p.trades.length > 1);
      await t.pumpWidget(TestScope(
          repos: b,
          store: ProjectStore(fileSystem: MemoryFiles()),
          child: MaterialApp(
              builder: (_, child) => AppScope(child: child!),
              home: Scaffold(
                  body: ProfileCard(profile: profile, onTap: () {})))));
      await t.pumpAndSettle();
      final texts = [
        for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? ''
      ];
      final trades = profile.trades.map(tradeName).join(sep);
      expect(texts, contains(trades));
      if (lang != AppLang.zh) {
        expect(texts.where((s) => s.contains('、')), isEmpty);
      }
    });
  }
}
