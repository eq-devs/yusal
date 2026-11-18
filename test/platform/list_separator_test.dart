import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/platform/data/mock/mock_backend.dart';
import 'package:yusal/platform/ui/cards.dart';
import 'package:yusal/platform/ui/l10n.dart';
import 'package:yusal/platform/ui/scope.dart';
import 'package:yusal/storage/project_store.dart';
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
      await t.pumpWidget(PlatformScope(
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
