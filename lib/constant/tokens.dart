import 'package:flutter/material.dart';
import 'package:yusal/constant/theme.dart';

/// Drafting palette from the Yusal logo book: white sheets, ink wall cuts
/// and one orange accent. The page, panel and hairline colours are those
/// of the platform pages ([YTokens]), so the design tool and the rest of
/// the app are one surface; the rest is for the drawing itself.
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
  final Color bg;
  final Color panel;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color accentInk;
  final Color wall;
  final Color room;
  final Color roomHi;
  final Color furn;
  final Color furnLine;
  final Color rug;
  final Color rebar;
  final Color dim;
  final Color crit;
  final Color warn;
  final Color ok;
  final Color chk;
  final bool dark;

  static const light = Tokens(
      bg: Color(0xffFBF9F5),
      panel: Color(0xffFFFFFF),
      ink: Color(0xff1E1C19),
      muted: Color(0xff6F665D),
      line: Color(0xffE4DDD2),
      accent: Color(0xffD86A2B),
      accentInk: Color(0xff1E1C19),
      wall: Color(0xff2A2622),
      room: Color(0xffF7F8F7),
      roomHi: Color(0xffFBE3D2),
      furn: Color(0xffE4DDD2),
      furnLine: Color(0xff978D82),
      rug: Color(0xffA8392E),
      rebar: Color(0xffB0502C),
      dim: Color(0xff4D585D),
      crit: Color(0xffC23B32),
      warn: Color(0xffB7791F),
      ok: Color(0xff2F7D5B),
      chk: Color(0xff3A6E9E),
      dark: false);

  static const night = Tokens(
      bg: Color(0xff1E1C19),
      panel: Color(0xff24211D),
      ink: Color(0xffF7F3EE),
      muted: Color(0xffC2B8AB),
      line: Color(0xff34302A),
      accent: Color(0xffD86A2B),
      accentInk: Color(0xff1E1C19),
      wall: Color(0xffE4DDD2),
      room: Color(0xff24211D),
      roomHi: Color(0xff4A2C1A),
      furn: Color(0xff34302A),
      furnLine: Color(0xff8A8076),
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

/// UI text: Inter, the Yusal logo book's typeface, with full Kazakh and
/// Russian Cyrillic.
const fontBody = 'Inter';

/// Page titles, house names and the wordmark: Inter Display, the tighter
/// cut of Inter for large sizes.
const fontDisplay = 'InterDisplay';

/// Numbers, sizes and codes.
const fontMono = 'JetBrainsMono';
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

/// The app's theme. The design tool and the platform pages share one look
/// (see [buildPlatformTheme]); the drafting palette above is kept for the
/// drawing itself.
ThemeData buildTheme(Tokens t) =>
    buildPlatformTheme(t.dark ? YTokens.night : YTokens.light);
