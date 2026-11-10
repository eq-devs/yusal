import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/app/messages_ru.dart';
import 'package:yusal/app/settings.dart';
import 'package:yusal/core/analysis/build_schedule.dart';
import 'package:yusal/core/commands/kz_template.dart';
import 'package:yusal/features/house_editor.dart';
import 'package:yusal/render2d/furniture_names.dart';
import 'package:yusal/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;

/// Letters that exist in Kazakh but not in Russian, and Chinese characters:
/// neither belongs on a Russian screen.
final _kazakh = RegExp('[ӘәҒғҚқҢңӨөҰұҮүҺһІі]');
final _chinese = RegExp(r'[一-鿿]');

/// The language switch names each language in itself.
const _allowed = {
  'Қазақша',
  '中文',
  'Тіл / 语言',
  'Тіл / Язык / 语言',
  'Тіл · Язык · 语言'
};

/// Every piece of text the widgets on screen show or announce.
Set<String> shownTexts(WidgetTester t) {
  final out = <String>{};
  for (final w in t.allWidgets) {
    if (w is Text) {
      out.add(w.data ?? w.textSpan?.toPlainText() ?? '');
    } else if (w is RichText) {
      out.add(w.text.toPlainText());
    } else if (w is Tooltip) {
      out.add(w.message ?? '');
    } else if (w is EditableText) {
      out.add(w.controller.text);
    }
  }
  return out..remove('');
}

List<String> foreign(Set<String> texts) => [
      for (final s in texts)
        if (!_allowed.contains(s) &&
            (_kazakh.hasMatch(s) || _chinese.hasMatch(s)))
          s
    ];

void main() {
  tearDown(() => AppSettings.instance.lang = AppLang.zh);

  test('no two-language string is left at a call in the app', () {
    // Strings written at a call carry all three languages (tr3); tr() is
    // only for table rows, which are looked up in the Russian table.
    final literalCall = RegExp(r"(?<![A-Za-z0-9_.])tr\(\s*'");
    final offenders = [
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (literalCall.hasMatch(f.readAsStringSync())) f.path
    ];
    expect(offenders, isEmpty);
  });

  test('every table row has a Russian text', () {
    // A row whose Kazakh is already a Russian word ("Диван") needs none.
    bool gap(String kk) => !hasRuText(kk) && _kazakh.hasMatch(kk);
    final missing = <String>[
      for (final n in furnitureNames.values)
        if (gap(n.$2)) n.$2,
      for (final list in stageChecks.values)
        for (final c in list)
          if (gap(c.$2)) c.$2,
    ];
    expect(missing, isEmpty);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)])
    testWidgets(
        'in Russian every page of the design tool is Russian at ${size.width}',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      AppSettings.instance.lang = AppLang.ru;
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var id = 0;
      // The example house as a Russian speaker gets it.
      final doc = createKazakhTemplate(
          '2026-11-01T00:00:00Z', () => 'ru_${id++}',
          name: 'Казахский сельский дом', names: kazakhTemplateNames());
      final store = ProjectStore(fileSystem: MemoryFiles());
      final pid = await store.createProject(doc);
      await t.pumpWidget(MaterialApp(
          builder: (context, child) => AppScope(child: child!),
          home: HouseEditor(entry: ProjectEntry(pid, doc), store: store)));
      await t.pumpAndSettle();

      final found = <String, List<String>>{};
      void scan(String where) {
        final bad = foreign(shownTexts(t));
        if (bad.isNotEmpty) found[where] = bad;
      }

      scan('plan');
      for (final key in [
        'ext',
        'walk',
        'site',
        'det',
        'heat',
        'qty',
        'cost',
        'build',
        'iss',
        'plan'
      ]) {
        await t.ensureVisible(find.byKey(ValueKey('tab-$key')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey('tab-$key')));
        await t.pumpAndSettle();
        scan(key);
        // Scroll each page once: most are longer than the screen.
        final lists = find.byType(Scrollable);
        if (key != 'plan' && key != 'ext' && key != 'walk') {
          await t.drag(lists.last, const Offset(0, -700), warnIfMissed: false);
          await t.pumpAndSettle();
          scan('$key (scrolled)');
        }
        expect(t.takeException(), isNull, reason: key);
      }

      // The header menu.
      await t.tap(find.byTooltip('Другие действия'));
      await t.pumpAndSettle();
      scan('menu');
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();

      expect(found, isEmpty,
          reason: found.entries
              .map((e) => '${e.key}: ${e.value.take(12).join(' | ')}')
              .join('\n'));
    });
}
