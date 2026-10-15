import 'package:flutter/material.dart';
import 'settings.dart';

/// Drafting-table palette: a cool grey desk, white sheets, dark wall cuts
/// and one amber accent. Every screen and painter reads colours from here.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.bg,
    required this.panel,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.wall,
    required this.room,
    required this.roomHi,
    required this.furn,
    required this.furnLine,
    required this.rug,
    required this.rebar,
    required this.dim,
    required this.crit,
    required this.warn,
    required this.ok,
    required this.chk,
    required this.dark,
  });
  final Color bg,
      panel,
      ink,
      muted,
      line,
      accent,
      accentInk,
      wall,
      room,
      roomHi,
      furn,
      furnLine,
      rug,
      rebar,
      dim,
      crit,
      warn,
      ok,
      chk;
  final bool dark;

  static const light = Tokens(
      bg: Color(0xffE9ECEC),
      panel: Color(0xffFFFFFF),
      ink: Color(0xff1C2326),
      muted: Color(0xff5B666B),
      line: Color(0xffC8D0D2),
      accent: Color(0xffC2771A),
      accentInk: Color(0xffFFFFFF),
      wall: Color(0xff2A3136),
      room: Color(0xffF7F8F7),
      roomHi: Color(0xffFCEBD3),
      furn: Color(0xffDDE3E3),
      furnLine: Color(0xff8D989C),
      rug: Color(0xffA8392E),
      rebar: Color(0xffB0502C),
      dim: Color(0xff4D585D),
      crit: Color(0xffC23B32),
      warn: Color(0xffB7791F),
      ok: Color(0xff2F7D5B),
      chk: Color(0xff3A6E9E),
      dark: false);

  static const night = Tokens(
      bg: Color(0xff13181A),
      panel: Color(0xff1C2326),
      ink: Color(0xffE4E9EA),
      muted: Color(0xff97A3A8),
      line: Color(0xff34404A),
      accent: Color(0xffE5952F),
      accentInk: Color(0xff1A1206),
      wall: Color(0xffD7DDDF),
      room: Color(0xff20282B),
      roomHi: Color(0xff4A3418),
      furn: Color(0xff2E383C),
      furnLine: Color(0xff7E8B90),
      rug: Color(0xffE07A62),
      rebar: Color(0xffE58A5E),
      dim: Color(0xffAEB9BD),
      crit: Color(0xffE8645A),
      warn: Color(0xffE0A94A),
      ok: Color(0xff5FBF92),
      chk: Color(0xff7DB3E6),
      dark: true);

  static Tokens of(BuildContext context) =>
      Theme.of(context).extension<Tokens>() ?? light;

  /// [a] blended over [b]: CSS color-mix(in srgb, a p%, b).
  static Color mix(Color a, double p, Color b) => Color.lerp(b, a, p)!;

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(ThemeExtension<Tokens>? other, double t) =>
      other is Tokens && t >= 0.5 ? other : this;
}

const fontBody = 'NotoSans';
const fontMono = 'PlexMono';
const bodyFallback = [
  'PingFang SC',
  'Noto Sans SC',
  'Microsoft YaHei',
  'Hiragino Sans GB',
  'sans-serif'
];

/// Numbers, sizes and codes: monospace with tabular digits.
TextStyle mono(
        {double size = 13,
        FontWeight weight = FontWeight.w400,
        Color? color}) =>
    TextStyle(
        fontFamily: fontMono,
        fontFamilyFallback: bodyFallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()]);

ThemeData buildTheme(Tokens t) {
  final scheme = ColorScheme(
      brightness: t.dark ? Brightness.dark : Brightness.light,
      primary: t.accent,
      onPrimary: t.accentInk,
      secondary: t.chk,
      onSecondary: t.panel,
      secondaryContainer: Tokens.mix(t.accent, 0.16, t.panel),
      onSecondaryContainer: t.ink,
      primaryContainer: Tokens.mix(t.accent, 0.2, t.panel),
      onPrimaryContainer: t.ink,
      error: t.crit,
      onError: t.panel,
      surface: t.panel,
      onSurface: t.ink,
      onSurfaceVariant: t.muted,
      outline: t.line,
      outlineVariant: t.line,
      surfaceContainerHighest: t.bg,
      inverseSurface: t.ink,
      onInverseSurface: t.panel,
      inversePrimary: t.accent);
  final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontBody,
      fontFamilyFallback: bodyFallback,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.panel,
      dividerColor: t.line,
      extensions: [t]);
  final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8), side: BorderSide(color: t.line));
  return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink),
      appBarTheme: AppBarTheme(
          backgroundColor: t.bg,
          foregroundColor: t.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent),
      cardTheme: CardThemeData(
          color: t.panel,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: t.line))),
      dialogTheme: DialogThemeData(
          backgroundColor: t.panel,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: t.panel,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true),
      popupMenuTheme: PopupMenuThemeData(
          color: t.panel, surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: t.ink,
          contentTextStyle: TextStyle(color: t.panel, fontFamily: fontBody),
          actionTextColor: t.accent),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.accentInk,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: t.ink,
              backgroundColor: t.panel,
              side: BorderSide(color: t.line),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              shape: shape)),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: t.accent)),
      inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: t.panel,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.accent, width: 2))),
      chipTheme: ChipThemeData(
          backgroundColor: t.panel,
          selectedColor: Tokens.mix(t.accent, 0.14, t.panel),
          side: BorderSide(color: t.line),
          shape: const StadiumBorder(),
          labelStyle: TextStyle(color: t.ink, fontSize: 13)),
      sliderTheme: SliderThemeData(
          activeTrackColor: t.accent,
          thumbColor: t.accent,
          inactiveTrackColor: t.line),
      checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? t.accent : Colors.transparent),
          checkColor: WidgetStatePropertyAll(t.accentInk)),
      tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
              color: t.ink, borderRadius: BorderRadius.circular(6)),
          textStyle: TextStyle(color: t.panel, fontSize: 12)));
}

/// The effective palette for the current choice and platform brightness.
Tokens tokensFor(ThemeChoice choice, Brightness platform) =>
    switch (choice) {
      ThemeChoice.day => Tokens.light,
      ThemeChoice.night => Tokens.night,
      ThemeChoice.auto =>
        platform == Brightness.dark ? Tokens.night : Tokens.light
    };
