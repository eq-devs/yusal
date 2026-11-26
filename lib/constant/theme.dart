import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yusal/constant/tokens.dart';
import 'package:yusal/features/shared/motion/motion.dart';

/// Platform look, after the ANT Community app's design system (one accent
/// used sparingly, selection in ink, flat hairline cards, one shadow tier
/// for things that float, pill buttons, frosted bars) in the colours of the
/// Yusal logo book: ink #1E1C19, cream #F7F3EE, stone #C2B8AB and one
/// orange #F96A10, the roof of the puzzle-house mark. Text on orange is
/// ink, which keeps it above 4.5 : 1.
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
    required this.elevated,
    required this.scrim,
    required this.dark,
  });
  final Color bg;
  final Color surface;
  final Color card;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color ok;
  final Color warn;
  final Color crit;
  final Color info;
  final Color shadow;

  /// Sheets, dialogs, menus and toasts: what floats above the page. A drop
  /// shadow is invisible at night, so there it is a lighter surface.
  final Color elevated;

  /// Behind a sheet or dialog.
  final Color scrim;
  final bool dark;

  static const light = YTokens(
      bg: Color(0xffFBF9F5),
      surface: Color(0xffF3EEE7),
      card: Color(0xffFFFFFF),
      ink: Color(0xff1E1C19),
      muted: Color(0xff6F665D),
      faint: Color(0xffB5ACA0),
      line: Color(0xffE4DDD2),
      accent: Color(0xffF96A10),
      accentInk: Color(0xff1E1C19),
      accentSoft: Color(0xffFBE9DD),
      ok: Color(0xff4F7A3A),
      warn: Color(0xffB8641B),
      crit: Color(0xffB23A2E),
      info: Color(0xff4C6E8A),
      shadow: Color(0x141E1C19),
      elevated: Color(0xffFFFFFF),
      scrim: Color(0x5C1E1C19),
      dark: false);

  static const night = YTokens(
      bg: Color(0xff1E1C19),
      surface: Color(0xff28251F),
      card: Color(0xff24211D),
      ink: Color(0xffF7F3EE),
      muted: Color(0xffC2B8AB),
      faint: Color(0xff7A7168),
      line: Color(0xff34302A),
      accent: Color(0xffF96A10),
      accentInk: Color(0xff1E1C19),
      accentSoft: Color(0xff3D2618),
      ok: Color(0xff8CBF6A),
      warn: Color(0xffE8A25C),
      crit: Color(0xffE87C6E),
      info: Color(0xff8FB3CF),
      shadow: Color(0x4D000000),
      elevated: Color(0xff2E2A25),
      scrim: Color(0xB3000000),
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

  /// The one elevation tier: a hairline ring plus two short, faint drops,
  /// so a raised surface reads as lifted without a halo. Flat is the
  /// default; only floating things (menus, the tab bar, a photo's control)
  /// take it. Cards never do.
  List<BoxShadow> get softShadow => [
        BoxShadow(
            color: shadow.withValues(alpha: shadow.a / 2), spreadRadius: 1),
        BoxShadow(color: shadow, blurRadius: 6, offset: const Offset(0, 2)),
        BoxShadow(
            color: shadow.withValues(alpha: shadow.a * 1.6),
            blurRadius: 8,
            offset: const Offset(0, 4)),
      ];
}

const yRadius = YRadius.card;

/// Spacing on a 4 px grid. Pages use [gutter] at their sides and
/// [section] between two unrelated blocks.
abstract final class YSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;
  static const gutter = xl;
  static const section = 28.0;
}

/// Corner radii, ANT's five steps: tags and dense rows, inputs and
/// thumbnails, cards and photos, sheets and dialogs, pills.
abstract final class YRadius {
  static const row = 8.0;
  static const control = 12.0;
  static const card = 20.0;
  static const sheet = 24.0;

  /// A chat bubble.
  static const bubble = 18.0;
  static const pill = 999.0;
}

/// Smallest side of anything tappable.
const yTouch = 44.0;

/// Height of a filled or outlined button: taller than the touch target, so
/// a screen's main action reads as the main action.
const yButton = 48.0;

/// Width from which the shell uses a side rail and pages may use columns.
const yWide = 840.0;

/// Type sizes. Pages name a step; they do not write a number.
abstract final class YFont {
  /// Bar labels under the tab icons.
  static const tab = 11.0;
  static const caption = 12.0;
  static const small = 13.0;
  static const label = 14.0;

  /// Text on buttons.
  static const button = 15.0;
  static const body = 16.0;
  static const heading = 18.0;
  static const section = 20.0;
  static const title = 22.0;

  /// Smallest size of the display face (page titles go up to 28).
  static const display = 24.0;
}

/// The type scale. Sizes only come from here; colour comes from the theme
/// unless a page asks for muted text.
abstract final class YText {
  static const title = TextStyle(
      fontSize: YFont.title, fontWeight: FontWeight.w700, height: 1.2);
  static const heading = TextStyle(
      fontSize: YFont.heading, fontWeight: FontWeight.w700, height: 1.25);
  static const body = TextStyle(fontSize: YFont.body, height: 1.45);
  static const bodyStrong =
      TextStyle(fontSize: YFont.body, fontWeight: FontWeight.w600, height: 1.3);
  static const label = TextStyle(fontSize: YFont.label, height: 1.35);
  static const labelStrong = TextStyle(
      fontSize: YFont.label, fontWeight: FontWeight.w600, height: 1.3);
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

/// Big titles and house names: Inter Display, tracked in by 2 % as in the
/// logo book, with the UI sans and system CJK fonts as fallback for Chinese.
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
        letterSpacing: -0.02 * size);

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
      // No Material ripple: a press is a warm bloom from the finger that
      // settles into one even tint (see PressTint). The highlight stays
      // clear so it is not drawn twice.
      splashFactory: PressTint.splashFactory,
      splashColor: t.accent.withValues(alpha: t.dark ? 0.20 : 0.14),
      highlightColor: Colors.transparent,
      iconTheme: IconThemeData(color: t.ink),
      // The design tool's palette stays available to shared widgets.
      extensions: [t, t.dark ? Tokens.night : Tokens.light],
      // iOS-style horizontal slide everywhere, with swipe-back.
      pageTransitionsTheme: motionPageTransitions);
  const pill = StadiumBorder();
  // A field is a soft fill with no outline, as iOS draws them.
  final hairline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(YRadius.control),
      borderSide: BorderSide.none);
  return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink),
      appBarTheme: AppBarTheme(
          backgroundColor: t.bg,
          foregroundColor: t.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          // Frosted bars are transparent, from which the app bar would
          // guess a dark background and paint white status-bar text on
          // the light page. The icons follow the page's own brightness.
          systemOverlayStyle:
              t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          // Detail pages: a back chevron and a plain left-aligned title;
          // the page's own headline carries the weight.
          titleTextStyle: TextStyle(
              fontFamily: fontBody,
              fontFamilyFallback: bodyFallback,
              color: t.ink,
              fontSize: 17,
              letterSpacing: -0.2,
              fontWeight: FontWeight.w600)),
      actionIconTheme: ActionIconThemeData(
          backButtonIconBuilder: (_) =>
              const Icon(Icons.arrow_back_ios_new_rounded, size: 20)),
      cardTheme: CardThemeData(
          color: t.card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(yRadius),
              side: BorderSide(color: t.line))),
      dialogTheme: DialogThemeData(
          backgroundColor: t.elevated,
          barrierColor: t.scrim,
          elevation: t.dark ? 0 : 3,
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
          backgroundColor: t.elevated,
          modalBarrierColor: t.scrim,
          elevation: t.dark ? 0 : 3,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          dragHandleColor: t.line,
          dragHandleSize: const Size(40, 5),
          shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(YRadius.sheet)))),
      popupMenuTheme: PopupMenuThemeData(
          color: t.elevated,
          surfaceTintColor: Colors.transparent,
          elevation: t.dark ? 0 : 4,
          shadowColor: t.shadow,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(YRadius.card))),
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
              color: s.contains(WidgetState.selected) ? t.ink : t.muted)),
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected) ? t.ink : t.muted))),
      navigationRailTheme: NavigationRailThemeData(
          backgroundColor: t.bg,
          // Selection is ink: the accent is kept for each screen's main
          // action.
          indicatorColor: t.ink.withValues(alpha: 0.07),
          selectedIconTheme: IconThemeData(size: 24, color: t.ink),
          unselectedIconTheme: IconThemeData(size: 24, color: t.muted),
          selectedLabelTextStyle: TextStyle(
              fontFamily: fontBody, fontFamilyFallback: bodyFallback,
              fontSize: YFont.caption,
              fontWeight: FontWeight.w700,
              color: t.ink),
          unselectedLabelTextStyle: TextStyle(
              fontFamily: fontBody, fontFamilyFallback: bodyFallback,
              fontSize: YFont.caption,
              fontWeight: FontWeight.w500,
              color: t.muted)),
      // A toast floats like a sheet: the elevated surface with ink text.
      snackBarTheme:
          SnackBarThemeData(backgroundColor: t.elevated, elevation: t.dark ? 0 : 4, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YRadius.control)), contentTextStyle: TextStyle(color: t.ink, fontFamily: fontBody, fontSize: YFont.label), actionTextColor: t.accent),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: t.accent, foregroundColor: t.accentInk, disabledBackgroundColor: t.line, disabledForegroundColor: t.muted, minimumSize: const Size(64, yButton), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), textStyle: const TextStyle(fontFamily: fontBody, fontFamilyFallback: bodyFallback, fontSize: YFont.button, fontWeight: FontWeight.w700), shape: pill)),
      outlinedButtonTheme: OutlinedButtonThemeData(
          // The quiet second action: a soft pill with no outline.
          style: OutlinedButton.styleFrom(foregroundColor: t.ink, backgroundColor: t.surface, minimumSize: const Size(48, yTouch), side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8), textStyle: const TextStyle(fontFamily: fontBody, fontFamilyFallback: bodyFallback, fontSize: YFont.label, fontWeight: FontWeight.w600), shape: pill)),
      // Plain buttons are ink with no underline: the accent is kept for
      // the screen's one main action, and on a phone an underline reads as
      // a web link, not as something to press.
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: t.ink, minimumSize: const Size(yTouch, yTouch), padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontFamily: fontBody, fontFamilyFallback: bodyFallback, fontSize: YFont.label, fontWeight: FontWeight.w600), shape: pill)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: t.ink, minimumSize: const Size(yTouch, yTouch))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: t.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          labelStyle: TextStyle(color: t.muted),
          hintStyle: TextStyle(color: t.muted),
          helperStyle: TextStyle(color: t.muted),
          floatingLabelStyle: TextStyle(color: t.ink),
          // A soft field; focus is an ink ring with no glow.
          border: hairline,
          enabledBorder: hairline,
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(YRadius.control), borderSide: BorderSide(color: t.ink, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(YRadius.control), borderSide: BorderSide(color: t.crit)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(YRadius.control), borderSide: BorderSide(color: t.crit, width: 1.5))),
      // Chips are a soft fill, never a border; a selected one is ink.
      chipTheme: ChipThemeData(backgroundColor: t.surface, selectedColor: t.ink, checkmarkColor: t.bg, secondarySelectedColor: t.ink, side: BorderSide.none, shape: const StadiumBorder(), labelStyle: TextStyle(fontFamily: fontBody, fontFamilyFallback: bodyFallback, color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? t.bg : t.ink), fontSize: YFont.small, fontWeight: FontWeight.w600), secondaryLabelStyle: TextStyle(fontFamily: fontBody, fontFamilyFallback: bodyFallback, color: t.bg, fontSize: YFont.small, fontWeight: FontWeight.w600)),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ink : t.surface), foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.bg : t.ink), iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.bg : t.ink), side: const WidgetStatePropertyAll(BorderSide.none))),
      switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.bg : t.card),
          // On is ink, like every other selection.
          trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ink : t.line),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent)),
      checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ink : Colors.transparent), checkColor: WidgetStatePropertyAll(t.bg)),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.ink : t.muted)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
      dividerTheme: DividerThemeData(color: t.line, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(iconColor: t.ink, textColor: t.ink, contentPadding: EdgeInsets.zero),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: t.accent, foregroundColor: t.accentInk, elevation: 0, highlightElevation: 0, extendedTextStyle: const TextStyle(fontFamily: fontBody, fontFamilyFallback: bodyFallback, fontWeight: FontWeight.w700), shape: const StadiumBorder()),
      tabBarTheme: TabBarThemeData(labelColor: t.ink, unselectedLabelColor: t.muted, indicatorColor: t.ink, dividerColor: t.line, labelStyle: const TextStyle(fontFamily: fontBody, fontFamilyFallback: bodyFallback, fontWeight: FontWeight.w700, fontSize: YFont.label), unselectedLabelStyle: const TextStyle(fontFamily: fontBody, fontFamilyFallback: bodyFallback, fontWeight: FontWeight.w500, fontSize: YFont.label)));
}

/// Applies the platform theme below it, light or dark as the app is.
class PlatformTheme extends StatelessWidget {
  const PlatformTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    // MaterialApp has already resolved day / night / system.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
        data: buildPlatformTheme(dark ? YTokens.night : YTokens.light),
        child: child);
  }
}
