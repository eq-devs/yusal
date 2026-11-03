import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chinese, Kazakh and Russian. The design tool is written in Chinese and
/// Kazakh; in Russian it shows its Kazakh text until it is translated.
enum AppLang { zh, kk, ru }

enum ThemeChoice { auto, day, night }

/// Interface language and colour theme, shared by every screen and kept
/// across launches. Screens call [AppScope.watch] so they rebuild on change.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();

  /// Chinese until [load] runs, so tests and previews keep their wording.
  AppLang lang = AppLang.zh;
  ThemeChoice theme = ThemeChoice.auto;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString('house-lang'),
          savedTheme = prefs.getString('house-theme');
      lang = AppLang.values.where((l) => l.name == savedLang).firstOrNull ??
          switch (PlatformDispatcher.instance.locale.languageCode) {
            'zh' => AppLang.zh,
            'ru' => AppLang.ru,
            _ => AppLang.kk,
          };
      theme = ThemeChoice.values.where((t) => t.name == savedTheme).firstOrNull ??
          ThemeChoice.auto;
    } catch (_) {
      /* Storage unavailable: keep the defaults. */
    }
    notifyListeners();
  }

  void setLang(AppLang value) {
    if (value == lang) return;
    lang = value;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString('house-lang', value.name))
        .catchError((_) => false);
  }

  void setTheme(ThemeChoice value) {
    if (value == theme) return;
    theme = value;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString('house-theme', value.name))
        .catchError((_) => false);
  }
}

/// Makes widgets that read the settings rebuild when they change.
class AppScope extends InheritedNotifier<AppSettings> {
  AppScope({super.key, required super.child})
      : super(notifier: AppSettings.instance);

  /// The settings, registering [context] for rebuilds when a scope exists.
  static AppSettings watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier ??
      AppSettings.instance;
}

/// Cyrillic interface: Kazakh, or Russian falling back to Kazakh where only
/// Chinese and Kazakh text exist.
bool get isKk => AppSettings.instance.lang != AppLang.zh;

bool get isRu => AppSettings.instance.lang == AppLang.ru;

/// Every design-tool string is written as a Chinese / Kazakh pair.
String tr(String zh, String kk) => isKk ? kk : zh;

/// Platform strings come in all three languages.
String tr3(String zh, String kk, String ru) =>
    switch (AppSettings.instance.lang) {
      AppLang.zh => zh,
      AppLang.kk => kk,
      AppLang.ru => ru,
    };

/// Kazakh writes decimals with a comma.
String dec(String number) => isKk ? number.replaceAll('.', ',') : number;

/// Metres from millimetres, two decimals: 3600 → "3.60".
String m2dp(num mm) => dec((mm / 1000).toStringAsFixed(2));

String get unitM => tr('米', 'м');
String get unitM2 => tr('㎡', 'м²');
String get unitM3 => tr('m³', 'м³');
String get unitMm => tr('mm', 'мм');
String get unitPcs => tr('个', 'дана');
