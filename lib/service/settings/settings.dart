import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/localization/messages_en.dart';
import 'package:yusal/localization/messages_ky_uz.dart';
import 'package:yusal/localization/messages_ru.dart';

/// Chinese, Kazakh, Russian, English, Kyrgyz and Uzbek, everywhere in the
/// app.
enum AppLang { zh, kk, ru, en, ky, uz }

/// Each language named in itself, in the order the pickers list them.
const languageNames = [
  (AppLang.kk, 'Қазақша'),
  (AppLang.ru, 'Русский'),
  (AppLang.zh, '中文'),
  (AppLang.en, 'English'),
  (AppLang.ky, 'Кыргызча'),
  (AppLang.uz, 'Oʻzbekcha'),
];

enum ThemeChoice { auto, day, night }

/// Interface language and colour theme, kept across launches.
@immutable
class Settings {
  const Settings({this.lang = AppLang.zh, this.theme = ThemeChoice.auto});
  final AppLang lang;
  final ThemeChoice theme;

  @override
  bool operator ==(Object other) =>
      other is Settings && other.lang == lang && other.theme == theme;

  @override
  int get hashCode => Object.hash(lang, theme);
}

/// The language [tr] and [tr3] answer in: plain functions called from
/// everywhere (pages, painters, voice), so it is a plain variable that
/// [settingsProvider] keeps equal to its own. Chinese until [loadSettings].
AppLang appLang = AppLang.zh;

/// The theme choice the app starts with; [loadSettings] reads the saved one.
ThemeChoice appTheme = ThemeChoice.auto;

/// Reads the saved choices, before the first frame.
Future<void> loadSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('house-lang');
    final savedTheme = prefs.getString('house-theme');
    appLang = AppLang.values.where((l) => l.name == savedLang).firstOrNull ??
        switch (PlatformDispatcher.instance.locale.languageCode) {
          'zh' => AppLang.zh,
          'ru' => AppLang.ru,
          'en' => AppLang.en,
          'ky' => AppLang.ky,
          'uz' => AppLang.uz,
          _ => AppLang.kk,
        };
    appTheme =
        ThemeChoice.values.where((t) => t.name == savedTheme).firstOrNull ??
            ThemeChoice.auto;
  } catch (_) {
    /* Storage unavailable: keep the defaults. */
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() => Settings(lang: appLang, theme: appTheme);

  void setLang(AppLang value) {
    if (value == state.lang) return;
    appLang = value;
    state = Settings(lang: value, theme: state.theme);
    _save('house-lang', value.name);
  }

  void setTheme(ThemeChoice value) {
    if (value == state.theme) return;
    appTheme = value;
    state = Settings(lang: state.lang, theme: value);
    _save('house-theme', value.name);
  }

  static void _save(String key, String value) => SharedPreferences.getInstance()
      .then((p) => p.setString(key, value))
      .catchError((_) => false);
}

/// Rebuilds [context] when the language changes: the app's locale follows
/// it, so this is the same signal Flutter's own texts use.
void watchLang(BuildContext context) => Localizations.localeOf(context);

/// Cyrillic interface: Kazakh, Russian or Kyrgyz (Cyrillic units such as
/// м², and words like "млн").
bool get isKk =>
    appLang == AppLang.kk || appLang == AppLang.ru || appLang == AppLang.ky;

bool get isRu => appLang == AppLang.ru;

bool get isEn => appLang == AppLang.en;

bool get isKy => appLang == AppLang.ky;

bool get isUz => appLang == AppLang.uz;

/// Any interface but Chinese: names and numbers are written the Western
/// way (no 万, Latin or Cyrillic units).
bool get isWestern => appLang != AppLang.zh;

/// A Chinese / Kazakh pair from a table (names of furniture, stages,
/// checklists). The Kazakh text is the key: Russian is looked up in
/// [ruText], English in [enText], Kyrgyz in [kyText] and Uzbek in
/// [uzText]; strings written at a call use [tr3] instead.
String tr(String zh, String kk) => switch (appLang) {
      AppLang.zh => zh,
      AppLang.kk => kk,
      AppLang.ru => ruText(kk),
      AppLang.en => enText(kk) ?? ruText(kk),
      AppLang.ky => kyText(kk) ?? ruText(kk),
      AppLang.uz => uzText(kk) ?? ruText(kk),
    };

/// Platform strings, written at the call in Chinese, Kazakh, Russian,
/// English, and optionally Kyrgyz and Uzbek. Where Kyrgyz or Uzbek is
/// missing the Russian is shown, which both audiences read.
String tr3(String zh, String kk, String ru, String? en,
        {String? ky, String? uz}) =>
    switch (appLang) {
      AppLang.zh => zh,
      AppLang.kk => kk,
      AppLang.ru => ru,
      AppLang.en => en ?? ru,
      AppLang.ky => ky ?? ru,
      AppLang.uz => uz ?? ru,
    };

/// Between items of a list: 、 in Chinese, a comma elsewhere.
String get listSep => tr3('、', ', ', ', ', ', ', ky: ', ', uz: ', ');

/// Kazakh, Russian, Kyrgyz and Uzbek write decimals with a comma.
String dec(String number) =>
    isWestern && !isEn ? number.replaceAll('.', ',') : number;

/// Whole number in groups of three split by a space, in every language:
/// 1250000 → "1 250 000". Used for money and other large amounts.
String groupDigits(num value) {
  final digits = value.round().abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Metres from millimetres, two decimals: 3600 → "3.60".
String m2dp(num mm) => dec((mm / 1000).toStringAsFixed(2));

String get unitM => tr3('米', 'м', 'м', 'm', ky: 'м', uz: 'm');
String get unitM2 => tr3('㎡', 'м²', 'м²', 'm²', ky: 'м²', uz: 'm²');
String get unitM3 => tr3('m³', 'м³', 'м³', 'm³', ky: 'м³', uz: 'm³');
String get unitMm => tr3('mm', 'мм', 'мм', 'mm', ky: 'мм', uz: 'mm');
String get unitPcs => tr3('个', 'дана', 'шт.', 'pcs', ky: 'даана', uz: 'dona');

/// Floors named automatically ("一楼", "二楼 副本") are stored in Chinese and
/// shown in the interface language; a name the user typed is kept.
String floorDisplayName(String name) {
  const numerals = '一二三四五六七八九十';
  final m = RegExp(r'^([一二三四五六七八九十])楼( 副本)?$').firstMatch(name);
  if (m == null || !isWestern) return name;
  final n = numerals.indexOf(m[1]!) + 1;
  if (isEn) return 'Floor $n${m[2] == null ? '' : ' (copy)'}';
  if (isRu) return '$n-й этаж${m[2] == null ? '' : ' (копия)'}';
  if (isKy) return '$n-кабат${m[2] == null ? '' : ' (көчүрмө)'}';
  if (isUz) return '$n-qavat${m[2] == null ? '' : ' (nusxa)'}';
  return '$n-қабат${m[2] == null ? '' : ' (көшірме)'}';
}
