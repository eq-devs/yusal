import 'package:flutter/material.dart';
import '../../app/settings.dart';
import '../../app/tokens.dart';
import '../../motion/motion.dart';

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

  /// The drafting sheet behind every plan drawing, light in both themes.
  static const paper = Color(0xfff6f7f3);

  /// Backing of a control that sits on a picture.
  Color get onImage => card.withValues(alpha: 0.92);

  List<BoxShadow> get softShadow => [
        BoxShadow(color: shadow, blurRadius: 16, offset: const Offset(0, 6)),
      ];
}

const yRadius = YRadius.card;

/// Spacing on a 4 px grid. Pages use [gutter] at their sides.
abstract final class YSpace {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 20.0;
  static const xxl = 24.0, xxxl = 32.0, huge = 40.0;
  static const gutter = xl;
}

/// Corner radii: dense rows and inputs, controls, cards, sheets, pills.
abstract final class YRadius {
  static const row = 8.0, control = 12.0, card = 14.0, sheet = 20.0;

  /// A chat bubble.
  static const bubble = 18.0;
  static const pill = 999.0;
}

/// Smallest side of anything tappable.
const yTouch = 44.0;

/// Width from which the shell uses a side rail and pages may use columns.
const yWide = 840.0;

/// Type sizes. Pages name a step; they do not write a number.
abstract final class YFont {
  /// Bar labels under the tab icons.
  static const tab = 11.0;
  static const caption = 12.0, small = 13.0, label = 14.0;

  /// Text on buttons.
  static const button = 15.0;
  static const body = 16.0, heading = 18.0, section = 20.0, title = 22.0;

  /// Smallest size of the serif display face (page titles go up to 28).
  static const display = 24.0;
}

/// The type scale. Sizes only come from here; colour comes from the theme
/// unless a page asks for muted text.
abstract final class YText {
  static const title =
      TextStyle(fontSize: YFont.title, fontWeight: FontWeight.w700, height: 1.2);
  static const heading =
      TextStyle(fontSize: YFont.heading, fontWeight: FontWeight.w700, height: 1.25);
  static const body = TextStyle(fontSize: YFont.body, height: 1.45);
  static const bodyStrong =
      TextStyle(fontSize: YFont.body, fontWeight: FontWeight.w600, height: 1.3);
  static const label = TextStyle(fontSize: YFont.label, height: 1.35);
  static const labelStrong =
      TextStyle(fontSize: YFont.label, fontWeight: FontWeight.w600, height: 1.3);
  static const caption = TextStyle(fontSize: YFont.caption, height: 1.35);

  /// Money, sizes and counts: digits of equal width, so columns line up.
  static const tabular = [FontFeature.tabularFigures()];
}

/// Text and icon colour that stays readable on [fill], whatever the theme:
/// the pills and badges are filled with ink or accent, which are dark by day
/// and light at night.
Color onFill(Color fill) {
  const dark = Color(0xff1A120B);
  // Whichever of the two contrasts more: a brightness threshold alone
  // gives white on mid tones such as the night accent, at under 3 : 1.
  final l = fill.computeLuminance();
  final withWhite = 1.05 / (l + 0.05);
  final withDark = (l + 0.05) / (dark.computeLuminance() + 0.05);
  return withWhite >= withDark ? Colors.white : dark;
}

/// Big titles and house names: the serif display face, with the UI sans
/// and system CJK fonts as fallback for Chinese.
TextStyle display(
        {double size = 24,
        FontWeight weight = FontWeight.w600,
        Color? color,
        double height = 1.15}) =>
    TextStyle(
        fontFamily: fontDisplay,
        fontFamilyFallback: const [fontBody, ...bodyFallback],
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: -0.2);

/// The wordmark.
TextStyle wordmark(Color color) =>
    display(size: 26, weight: FontWeight.w700, color: color);

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
      // No ripple: a press is one even tint over the whole control (see
      // PressTint). The highlight stays clear so it is not drawn twice.
      splashFactory: PressTint.splashFactory,
      splashColor: t.ink.withValues(alpha: t.dark ? 0.10 : 0.06),
      highlightColor: Colors.transparent,
      // The design tool's palette stays available to shared widgets.
      extensions: [t, t.dark ? Tokens.night : Tokens.light],
      // iOS-style horizontal slide everywhere, with swipe-back.
      pageTransitionsTheme: motionPageTransitions);
  final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(YRadius.control));
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
              fontSize: YFont.heading,
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
          // A dialog is a column of text, not a banner: without a cap a
          // long sentence stretches it across a desktop window.
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 460),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: YText.heading.copyWith(
              color: t.ink,
              fontFamily: fontBody,
              fontFamilyFallback: bodyFallback),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(YRadius.sheet))),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: t.bg,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          dragHandleColor: t.faint,
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(YRadius.sheet)))),
      popupMenuTheme: PopupMenuThemeData(
          color: t.card,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          shadowColor: t.shadow,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(YRadius.control),
              side: BorderSide(color: t.line))),
      tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
              color: t.ink, borderRadius: BorderRadius.circular(YRadius.row)),
          textStyle: TextStyle(color: t.bg, fontSize: YFont.caption)),
      navigationBarTheme: NavigationBarThemeData(
          backgroundColor: t.bg,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          elevation: 0,
          height: 64,
          labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: YFont.tab,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? t.accent : t.muted)),
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected) ? t.accent : t.muted))),
      navigationRailTheme: NavigationRailThemeData(
          backgroundColor: t.bg,
          indicatorColor: t.accentSoft,
          selectedIconTheme: IconThemeData(size: 24, color: t.accent),
          unselectedIconTheme: IconThemeData(size: 24, color: t.muted),
          selectedLabelTextStyle: TextStyle(
              fontFamily: fontBody,
              fontSize: YFont.caption,
              fontWeight: FontWeight.w700,
              color: t.accent),
          unselectedLabelTextStyle: TextStyle(
              fontFamily: fontBody,
              fontSize: YFont.caption,
              fontWeight: FontWeight.w500,
              color: t.muted)),
      snackBarTheme: SnackBarThemeData(
          backgroundColor: t.ink,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(YRadius.control)),
          contentTextStyle: TextStyle(color: t.bg, fontFamily: fontBody),
          actionTextColor: t.dark ? YTokens.light.accent : YTokens.night.accent),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.accentInk,
              disabledBackgroundColor: t.line,
              disabledForegroundColor: t.muted,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: const TextStyle(
                  fontFamily: fontBody,
                  fontSize: YFont.button,
                  fontWeight: FontWeight.w700),
              shape: pill)),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: t.ink,
              minimumSize: const Size(48, yTouch),
              side: BorderSide(color: t.faint),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              textStyle: const TextStyle(
                  fontFamily: fontBody,
                  fontSize: YFont.label,
                  fontWeight: FontWeight.w600),
              shape: pill)),
      // Plain buttons take the accent and no underline: on a phone an
      // underline reads as a web link, not as something to press.
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: t.accent,
              minimumSize: const Size(yTouch, yTouch),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                  fontFamily: fontBody,
                  fontSize: YFont.label,
                  fontWeight: FontWeight.w600),
              shape: pill)),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
              foregroundColor: t.ink,
              minimumSize: const Size(yTouch, yTouch))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: t.card,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          labelStyle: TextStyle(color: t.muted),
          hintStyle: TextStyle(color: t.muted),
          helperStyle: TextStyle(color: t.muted),
          floatingLabelStyle: TextStyle(color: t.ink),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.control),
              borderSide: BorderSide(color: t.faint)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.control),
              borderSide: BorderSide(color: t.faint)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.control),
              borderSide: BorderSide(color: t.accent, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.control),
              borderSide: BorderSide(color: t.crit)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.control),
              borderSide: BorderSide(color: t.crit, width: 2))),
      chipTheme: ChipThemeData(
          backgroundColor: t.bg,
          selectedColor: t.ink,
          checkmarkColor: t.bg,
          secondarySelectedColor: t.ink,
          side: BorderSide(color: t.line),
          shape: const StadiumBorder(),
          labelStyle: TextStyle(color: t.ink, fontSize: YFont.small),
          secondaryLabelStyle: TextStyle(color: t.bg, fontSize: YFont.small)),
      switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? t.accentInk : t.card),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? t.accent : t.faint),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent)),
      checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? t.ink : Colors.transparent),
          checkColor: WidgetStatePropertyAll(t.bg)),
      radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? t.accent : t.muted)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
      dividerTheme: DividerThemeData(color: t.line, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
          iconColor: t.ink,
          textColor: t.ink,
          contentPadding: EdgeInsets.zero),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: t.accent,
          foregroundColor: t.accentInk,
          elevation: 3,
          extendedTextStyle:
              const TextStyle(fontFamily: fontBody, fontWeight: FontWeight.w700),
          shape: const StadiumBorder()),
      tabBarTheme: TabBarThemeData(
          labelColor: t.ink,
          unselectedLabelColor: t.muted,
          indicatorColor: t.ink,
          dividerColor: t.line,
          labelStyle: const TextStyle(
              fontFamily: fontBody, fontWeight: FontWeight.w700, fontSize: YFont.label),
          unselectedLabelStyle: const TextStyle(
              fontFamily: fontBody,
              fontWeight: FontWeight.w500,
              fontSize: YFont.label)));
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
