import 'package:flutter/material.dart';
import '../../app/settings.dart';
import '../../app/tokens.dart';

/// Platform look, after the visual language of Airbnb (large bold titles,
/// rounded cards with soft shadows, pill filters, one accent) but in the
/// colours of a house being built: warm paper, walnut wood and clay.
/// Only the style is borrowed, no assets or brand.
@immutable
class YTokens extends ThemeExtension<YTokens> {
  const YTokens({
    required this.bg,
    required this.surface,
    required this.card,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.ok,
    required this.warn,
    required this.crit,
    required this.info,
    required this.shadow,
    required this.dark,
  });
  final Color bg,
      surface,
      card,
      ink,
      muted,
      faint,
      line,
      accent,
      accentInk,
      accentSoft,
      ok,
      warn,
      crit,
      info,
      shadow;
  final bool dark;

  static const light = YTokens(
      bg: Color(0xffFFFCF8),
      surface: Color(0xffF6F0E8),
      card: Color(0xffFFFFFF),
      ink: Color(0xff2B2118),
      muted: Color(0xff7A6A5B),
      faint: Color(0xffB9AB9C),
      line: Color(0xffECE3D8),
      accent: Color(0xffA3673B),
      accentInk: Color(0xffFFFFFF),
      accentSoft: Color(0xffF7EBDF),
      ok: Color(0xff4F7A3A),
      warn: Color(0xffB8641B),
      crit: Color(0xffB23A2E),
      info: Color(0xff4C6E8A),
      shadow: Color(0x1F3B2A1A),
      dark: false);

  static const night = YTokens(
      bg: Color(0xff15110E),
      surface: Color(0xff201A15),
      card: Color(0xff1C1612),
      ink: Color(0xffF3EBE2),
      muted: Color(0xffB4A697),
      faint: Color(0xff6F6256),
      line: Color(0xff2F2721),
      accent: Color(0xffD28B5A),
      accentInk: Color(0xff1A120B),
      accentSoft: Color(0xff3A2A1F),
      ok: Color(0xff8CBF6A),
      warn: Color(0xffE8A25C),
      crit: Color(0xffE87C6E),
      info: Color(0xff8FB3CF),
      shadow: Color(0x80000000),
      dark: true);

  static YTokens of(BuildContext context) =>
      Theme.of(context).extension<YTokens>() ?? light;

  @override
  YTokens copyWith() => this;
  @override
  YTokens lerp(ThemeExtension<YTokens>? other, double t) =>
      other is YTokens && t >= 0.5 ? other : this;

  List<BoxShadow> get softShadow => [
        BoxShadow(color: shadow, blurRadius: 16, offset: const Offset(0, 6)),
      ];
}

const yRadius = 14.0;

ThemeData buildPlatformTheme(YTokens t) {
  final scheme = ColorScheme(
      brightness: t.dark ? Brightness.dark : Brightness.light,
      primary: t.accent,
      onPrimary: t.accentInk,
      secondary: t.ink,
      onSecondary: t.bg,
      primaryContainer: t.accentSoft,
      onPrimaryContainer: t.ink,
      secondaryContainer: t.surface,
      onSecondaryContainer: t.ink,
      error: t.crit,
      onError: Colors.white,
      surface: t.bg,
      onSurface: t.ink,
      onSurfaceVariant: t.muted,
      outline: t.line,
      outlineVariant: t.line,
      surfaceContainerHighest: t.surface,
      surfaceContainerHigh: t.surface,
      surfaceContainer: t.surface,
      surfaceContainerLow: t.bg,
      inverseSurface: t.ink,
      onInverseSurface: t.bg,
      inversePrimary: t.accent);
  final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontBody,
      fontFamilyFallback: bodyFallback,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      dividerColor: t.line,
      splashFactory: InkSparkle.splashFactory,
      // The design tool's palette stays available to shared widgets.
      extensions: [t, t.dark ? Tokens.night : Tokens.light]);
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink),
      appBarTheme: AppBarTheme(
          backgroundColor: t.bg,
          foregroundColor: t.ink,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
              fontFamily: fontBody,
              fontFamilyFallback: bodyFallback,
              color: t.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700)),
      cardTheme: CardThemeData(
          color: t.card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(yRadius),
              side: BorderSide(color: t.line))),
      dialogTheme: DialogThemeData(
          backgroundColor: t.bg,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: t.bg,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)))),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: t.bg,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          elevation: 0,
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 11,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? t.accent : t.muted)),
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected) ? t.accent : t.muted))),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: t.ink,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          contentTextStyle: TextStyle(color: t.bg, fontFamily: fontBody),
          actionTextColor: t.accent),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.accentInk,
              disabledBackgroundColor: t.line,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              textStyle: const TextStyle(
                  fontFamily: fontBody,
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
              shape: pill)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: t.ink, minimumSize: const Size(48, 44), side: BorderSide(color: t.ink), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), textStyle: const TextStyle(fontFamily: fontBody, fontSize: 14, fontWeight: FontWeight.w600), shape: pill)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: t.ink, textStyle: const TextStyle(fontFamily: fontBody, fontWeight: FontWeight.w600, decoration: TextDecoration.underline))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: t.bg, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), labelStyle: TextStyle(color: t.muted), floatingLabelStyle: TextStyle(color: t.ink), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.faint)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.faint)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.ink, width: 2))),
      chipTheme: ChipThemeData(backgroundColor: t.bg, selectedColor: t.ink, checkmarkColor: t.bg, secondarySelectedColor: t.ink, side: BorderSide(color: t.line), shape: const StadiumBorder(), labelStyle: TextStyle(color: t.ink, fontSize: 13), secondaryLabelStyle: TextStyle(color: t.bg, fontSize: 13)),
      switchTheme: SwitchThemeData(thumbColor: const WidgetStatePropertyAll(Colors.white), trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ink : t.faint), trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent)),
      checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ink : Colors.transparent), checkColor: WidgetStatePropertyAll(t.bg)),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ink : t.muted)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
      dividerTheme: DividerThemeData(color: t.line, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(iconColor: t.ink, textColor: t.ink, contentPadding: EdgeInsets.zero),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: t.accent, foregroundColor: t.accentInk, elevation: 3, extendedTextStyle: const TextStyle(fontFamily: fontBody, fontWeight: FontWeight.w700), shape: const StadiumBorder()),
      tabBarTheme: TabBarThemeData(labelColor: t.ink, unselectedLabelColor: t.muted, indicatorColor: t.ink, dividerColor: t.line, labelStyle: const TextStyle(fontFamily: fontBody, fontWeight: FontWeight.w700, fontSize: 14), unselectedLabelStyle: const TextStyle(fontFamily: fontBody, fontWeight: FontWeight.w500, fontSize: 14)));
}

/// Applies the platform theme below it, following the day / night choice.
class PlatformTheme extends StatelessWidget {
  const PlatformTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final choice = AppScope.watch(context).theme;
    final dark = switch (choice) {
      ThemeChoice.day => false,
      ThemeChoice.night => true,
      ThemeChoice.auto =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    return Theme(
        data: buildPlatformTheme(dark ? YTokens.night : YTokens.light),
        child: child);
  }
}
