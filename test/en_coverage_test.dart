import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/localization/messages_en.dart';
import 'package:yusal/localization/messages_ky_uz.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/analysis/build_schedule.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/features/editor/engine/render2d/furniture_names.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'storage_test.dart' show MemoryFiles;
import 'tabs.dart';

/// Cyrillic and Chinese: neither belongs on an English or Uzbek screen.
final _cyrillic = RegExp('[Ѐ-ӿ]');
final _chinese = RegExp('[一-鿿]');

/// Letters Kazakh has and Kyrgyz doesn't: their sight on a Kyrgyz screen
/// means Kazakh text leaked through.
final _kazakhOnly = RegExp('[әғқұһіӘҒҚҰҺІ]');

/// The language switch names each language in itself.
const _allowed = {
  'Қазақша',
  'Русский',
  '中文',
  'Кыргызча',
  'Тіл / 语言 / Language',
  'Тіл / Язык / 语言 / Language',
};

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

List<String> foreign(Set<String> texts, {AppLang lang = AppLang.en}) => [
      for (final s in texts)
        if (!_allowed.contains(s) &&
            (_chinese.hasMatch(s) ||
                (lang == AppLang.ky
                    ? _kazakhOnly.hasMatch(s)
                    : _cyrillic.hasMatch(s))))
          s
    ];

/// The source of each `tr3(` call in [src] that has literal texts but no
/// Kyrgyz or no Uzbek.
List<String> missingKyUz(String src) {
  final out = <String>[];
  for (final m in RegExp(r'(?<![\w.])tr3\(').allMatches(src)) {
    if (src.substring(m.start > 7 ? m.start - 7 : 0, m.start).contains('String')) {
      continue;
    }
    var i = m.end;
    var depth = 0;
    String? quote;
    while (i < src.length) {
      final c = src[i];
      if (quote != null) {
        if (c == r'\') {
          i += 2;
          continue;
        }
        if (c == quote) quote = null;
      } else if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        if (depth == 0) break;
        depth--;
      }
      i++;
    }
    final call = src.substring(m.start, i);
    final literal = RegExp('^tr3\\(\\s*[\'"]').hasMatch(call);
    if (literal && !(call.contains('ky:') && call.contains('uz:'))) {
      out.add(call);
    }
  }
  return out;
}

void main() {
  tearDown(() => appLang = AppLang.zh);

  test('every tr3 call with written texts also has English', () {
    // tr3('中文', 'Қазақша', 'Русский') with no fourth text shows Russian
    // to English readers.
    final threeOnly = RegExp(
        r"tr3\(\s*'[^']*',\s*'[^']*',\s*'[^']*'\s*\)",
        multiLine: true);
    final offenders = [
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        for (final m in threeOnly.allMatches(f.readAsStringSync()))
          '${f.path}: ${m[0]}'
    ];
    expect(offenders, isEmpty);
  });

  test('every tr3 call with written texts also has Kyrgyz and Uzbek', () {
    final offenders = [
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        for (final call in missingKyUz(f.readAsStringSync()))
          '${f.path}: ${call.split('\n').first}'
    ];
    expect(offenders, isEmpty);
  });

  test('every table row has Kyrgyz and Uzbek', () {
    final missing = <String>[
      for (final n in furnitureNames.values)
        if (!hasKyUzText(n.$2)) n.$2,
      for (final list in stageChecks.values)
        for (final c in list)
          if (!hasKyUzText(c.$2)) c.$2,
    ];
    expect(missing, isEmpty);
  });

  test('every table row has an English text', () {
    final missing = <String>[
      for (final n in furnitureNames.values)
        if (!hasEnText(n.$2)) n.$2,
      for (final list in stageChecks.values)
        for (final c in list)
          if (!hasEnText(c.$2)) c.$2,
    ];
    expect(missing, isEmpty);
  });

  for (final (lang, size) in [
    (AppLang.en, const Size(1280, 900)),
    (AppLang.en, const Size(390, 844)),
    (AppLang.ky, const Size(390, 844)),
    (AppLang.uz, const Size(390, 844)),
  ]) {
    testWidgets(
        'in ${lang.name} every page of the design tool is in it at ${size.width}',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      appLang = lang;
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var id = 0;
      final doc = createKazakhTemplate(
          '2026-11-01T00:00:00Z', () => 'en_${id++}',
          name: 'Kazakh village house', names: kazakhTemplateNames());
      final store = ProjectStore(fileSystem: MemoryFiles());
      final pid = await store.createProject(doc);
      await t.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: HouseEditor(entry: ProjectEntry(pid, doc), store: store))));
      await t.pumpAndSettle();

      final found = <String, List<String>>{};
      void scan(String where) {
        final bad = foreign(shownTexts(t), lang: lang);
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
        await t.pumpAndSettle();
        await openTab(t, key);
        await t.pumpAndSettle();
        scan(key);
        final lists = find.byType(Scrollable);
        if (key != 'plan' && key != 'ext' && key != 'walk') {
          await t.drag(lists.last, const Offset(0, -700), warnIfMissed: false);
          await t.pumpAndSettle();
          scan('$key (scrolled)');
        }
        expect(t.takeException(), isNull, reason: key);
      }

      await t.tap(find.byTooltip(switch (lang) {
        AppLang.ky => 'Дагы аракеттер',
        AppLang.uz => 'Boshqa amallar',
        _ => 'More actions',
      }));
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
}
