import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/settings.dart';
import 'theme.dart';
import '../../motion/motion.dart';

/// Picture bytes for [MemoryImage] / [Image.memory], without copying when
/// they already are a [Uint8List]. Those compare images by the identity of
/// their bytes, so a copy made on every build decodes the picture again on
/// every rebuild; the same list is decoded once and then comes from cache.
Uint8List imageBytes(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// Shared building blocks of the platform pages.

/// Width-limited page with ANT's frosted header and an optional sticky
/// action bar. The content scrolls under both: the header blurs it, the
/// action bar fades it out, so neither reads as a hard-edged slab.
class PageScaffold extends StatelessWidget {
  const PageScaffold(
      {super.key,
      required this.title,
      required this.body,
      this.actions = const [],
      this.bottom,
      this.scroll = true,
      this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 32)});
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;
  final bool scroll;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: bottom != null,
      appBar: FrostedAppBar(title: Text(title), actions: actions),
      // The scaffold now reports the bars as padding; the content clears
      // them and still scrolls underneath.
      body: Builder(builder: (context) {
        final bars = MediaQuery.paddingOf(context);
        final inset = padding.copyWith(
            top: padding.top + bars.top, bottom: padding.bottom + bars.bottom);
        return MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: scroll
                        ? SingleChildScrollView(padding: inset, child: body)
                        : Padding(padding: inset, child: body))));
      }),
      bottomNavigationBar: bottom == null ? null : ActionBar(child: bottom!));
}

/// An app bar whose page scrolls under it: the page colour at 88 % over a
/// blur, as in ANT. Put the page in a Scaffold with
/// `extendBodyBehindAppBar: true` and pad the content by
/// `MediaQuery.paddingOf(context).top`.
class FrostedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FrostedAppBar(
      {super.key, this.title, this.actions = const [], this.bottom});
  final Widget? title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return AppBar(
        title: title,
        actions: [...actions, const SizedBox(width: YSpace.xs)],
        bottom: bottom,
        backgroundColor: Colors.transparent,
        // The app bar gives flexibleSpace loose constraints: without the
        // expand the frost lays out at height 0 and the bar is see-through.
        flexibleSpace: SizedBox.expand(
            child: ClipRect(
                child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: ColoredBox(color: t.bg.withValues(alpha: 0.88))))));
  }
}

/// Sticky bottom bar for a page's main action. The page fades out under it
/// instead of meeting a hairline, as ANT's action strip does.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [t.bg.withValues(alpha: 0), t.bg, t.bg],
                stops: const [0, 0.4, 1])),
        child: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                // heightFactor keeps the bar as tall as its content; a plain
                // Center would take the whole screen as a bottom bar.
                child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: child)))));
  }
}

class YCard extends StatelessWidget {
  const YCard(
      {super.key,
      required this.child,
      this.onTap,
      this.padding = const EdgeInsets.all(16),
      this.shadow = false,
      this.color});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool shadow;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    // A card rises in with its page's first rows (ANT's entrance), and
    // shrinks a touch under the finger when it opens something.
    return Stagger(
        child: Pressable(
            enabled: onTap != null,
            child: Container(
                decoration: BoxDecoration(
                    color: color ?? t.card,
                    borderRadius: BorderRadius.circular(yRadius),
                    border: Border.all(color: t.line),
                    boxShadow: shadow ? t.softShadow : null),
                child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                        borderRadius: BorderRadius.circular(yRadius),
                        splashFactory: NoSplash.splashFactory,
                        onTap: onTap,
                        child: Padding(padding: padding, child: child))))));
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.top = 24});
  final String text;
  final Widget? trailing;
  final double top;
  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.only(top: top, bottom: 10),
      child: Row(children: [
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: YFont.section,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.25))),
        if (trailing != null) trailing!,
      ]));
}

/// Small rounded label, e.g. a status.
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color, this.filled = false});
  final String text;
  final Color? color;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final c = color ?? t.ink;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: filled ? c : c.withValues(alpha: t.dark ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(YRadius.pill)),
        child: Text(text,
            style: TextStyle(
                fontSize: YFont.caption,
                fontWeight: FontWeight.w600,
                color: filled ? onFill(c) : c)));
  }
}

/// Pill-shaped choice: a filter toggle, or with [menu] a pill that opens
/// a list (sort, region). The pill is 36 px tall inside a 44 px target.
class FilterPill extends StatelessWidget {
  const FilterPill(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap,
      this.icon,
      this.menu = false});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Shows a chevron: tapping opens choices instead of toggling.
  final bool menu;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final fg = selected ? t.bg : t.ink;
    return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap == null
                ? null
                : () {
                    // A choice: confirmed with a tick, as in ANT.
                    if (!menu) HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: yTouch),
                child: Center(
                    widthFactor: 1,
                    child: DecoratedBox(
                        decoration: ShapeDecoration(
                            color: selected ? t.ink : t.card,
                            shape: StadiumBorder(
                                side: BorderSide(
                                    color: selected ? t.ink : t.line))),
                        child: Padding(
                            padding:
                                EdgeInsets.fromLTRB(14, 8, menu ? 8 : 14, 8),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              if (icon != null) ...[
                                Icon(icon, size: 16, color: fg),
                                const SizedBox(width: 6),
                              ],
                              Text(label,
                                  style: TextStyle(
                                      fontSize: YFont.small,
                                      fontWeight: FontWeight.w600,
                                      color: fg)),
                              if (menu)
                                Icon(Icons.expand_more, size: 18, color: fg),
                            ])))))));
  }
}

/// Round avatar with the first letter of a name.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, this.team = false});
  final String name;
  final double size;
  final bool team;
  static const _colors = [
    Color(0xffA3673B),
    Color(0xff6F8F5A),
    Color(0xffB8641B),
    Color(0xff7A5C8E),
    Color(0xff4C6E8A),
    Color(0xff8C6A4A),
  ];
  @override
  Widget build(BuildContext context) {
    final c = _colors[name.hashCode.abs() % _colors.length];
    return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(team ? size * 0.28 : size)),
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700)));
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.icon});
  final String label, value;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: t.ink),
            const SizedBox(width: 12),
          ],
          SizedBox(
              width: 116,
              child: Text(label,
                  style: TextStyle(color: t.muted, fontSize: YFont.label))),
          Expanded(
              // Values are often amounts, dates and sizes: equal-width
              // digits keep a column of rows aligned.
              child: Text(value,
                  style: const TextStyle(
                      fontSize: YFont.label,
                      fontWeight: FontWeight.w500,
                      fontFeatures: YText.tabular))),
        ]));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.body,
      this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: t.faint),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: YFont.heading, fontWeight: FontWeight.w700)),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!,
                textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]));
  }
}

/// A notice box: grey for information, coral-tinted for warnings.
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key, this.warn = false, this.icon});
  final String text;
  final bool warn;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: warn ? t.accentSoft : t.surface,
            borderRadius: BorderRadius.circular(YRadius.control)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon ?? (warn ? Icons.error_outline : Icons.info_outline),
              size: 18, color: warn ? t.warn : t.muted),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: YFont.small, color: t.ink, height: 1.4))),
        ]));
  }
}

/// Filled button that disables itself while its action runs, so a double
/// tap never sends twice.
class BusyButton extends StatefulWidget {
  const BusyButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.outlined = false,
      this.expand = true,
      this.icon});
  final String label;
  final Future<void> Function()? onPressed;
  final bool outlined, expand;
  final IconData? icon;
  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool busy = false;
  Future<void> run() async {
    if (busy) return;
    // The main action of a screen: a light tap confirms the press.
    HapticFeedback.lightImpact();
    setState(() => busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    // While busy the label keeps its width so the button does not jump,
    // and the button keeps its colours (a disabled fill would wash the
    // spinner out); taps are swallowed instead.
    final label = Row(mainAxisSize: MainAxisSize.min, children: [
      if (widget.icon != null) ...[
        Icon(widget.icon, size: 18),
        const SizedBox(width: 8)
      ],
      Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
    ]);
    final child = Stack(alignment: Alignment.center, children: [
      Visibility(
          visible: !busy,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: label),
      if (busy) const ButtonSpinner(),
    ]);
    final onPressed = enabled ? run : null;
    final button = widget.outlined
        ? OutlinedButton(onPressed: onPressed, child: child)
        : FilledButton(onPressed: onPressed, child: child);
    return Semantics(
        enabled: enabled && !busy,
        child: IgnorePointer(
            ignoring: busy,
            child: widget.expand
                ? SizedBox(width: double.infinity, child: button)
                : button));
  }
}

/// A small spinner in the enclosing button's text colour, so it reads on
/// every fill and in both themes.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: IconTheme.of(context).color ??
              DefaultTextStyle.of(context).style.color));
}

/// A sheet row that staggers in when its sheet first opens.
Widget _staggered(BuildContext context, int i, Widget row) =>
    StaggerScope.of(context) ? Stagger(index: i + 1, child: row) : row;

/// Bottom-sheet picker for one value.
Future<T?> pickOne<T>(
    BuildContext context, String title, List<(T, String)> options,
    {T? selected}) {
  return showMotionSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PlatformTheme(
          child: SafeArea(
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.7),
                  child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: YFont.heading,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        for (final (i, (value, label)) in options.indexed)
                          _staggered(
                              context,
                              i,
                              ListTile(
                                  title: Text(label),
                                  trailing: value == selected
                                      ? const Icon(Icons.check)
                                      : null,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    Navigator.pop(context, value);
                                  })),
                      ])))));
}

/// Bottom-sheet picker for a filter whose first row is "all" (no value).
/// [pickOne] cannot tell "all" from closing the sheet, since both come
/// back as null; here closing returns null and a choice returns a record,
/// so a swipe-away leaves the filter as it was.
Future<(T?,)?> pickFilter<T extends Object>(BuildContext context, String title,
        String allLabel, List<(T, String)> options,
        {T? selected}) =>
    pickOne<(T?,)>(context, title, [
      ((null,), allLabel),
      for (final (value, label) in options) ((value,), label),
    ], selected: (
      selected,
    ));

/// Bottom-sheet picker for several values.
Future<List<T>?> pickMany<T>(BuildContext context, String title,
    List<(T, String)> options, List<T> selected) {
  final chosen = {...selected};
  return showMotionSheet<List<T>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PlatformTheme(
          child: StatefulBuilder(
              builder: (context, setSheet) => SafeArea(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: YFont.heading,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final (value, label) in options)
                                FilterPill(
                                    label: label,
                                    selected: chosen.contains(value),
                                    onTap: () => setSheet(() {
                                          if (!chosen.remove(value))
                                            chosen.add(value);
                                        })),
                            ]),
                            const SizedBox(height: 16),
                            SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                    onPressed: () => Navigator.pop(context, [
                                          for (final (v, _) in options)
                                            if (chosen.contains(v)) v
                                        ]),
                                    child: Text(tr3('完成', 'Дайын', 'Готово')))),
                          ]))))));
}

/// A sheet's body as ANT lays it out: a heading, an optional line, then
/// the content, above the keyboard and the home indicator.
class SheetBody extends StatelessWidget {
  const SheetBody(
      {super.key, required this.title, this.body, required this.children});
  final String title;
  final String? body;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: YFont.section,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              height: 1.25)),
                      if (body != null) ...[
                        const SizedBox(height: 6),
                        Text(body!,
                            style: TextStyle(
                                fontSize: YFont.label,
                                height: 1.45,
                                color: t.muted)),
                      ],
                      const SizedBox(height: 18),
                      ...children,
                    ]))));
  }
}

/// A sheet's two answers side by side: the quiet one, then the main one in
/// ink (or in the alarm colour when it destroys something).
class SheetAnswers extends StatelessWidget {
  const SheetAnswers(
      {super.key,
      required this.cancel,
      required this.ok,
      required this.onOk,
      this.danger = false});
  final String cancel, ok;
  final VoidCallback? onOk;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final fill = danger ? t.crit : t.ink;
    return Row(children: [
      Expanded(
          child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, yButton),
                  backgroundColor: t.surface,
                  side: BorderSide.none),
              onPressed: () => Navigator.pop(context),
              child: Text(cancel))),
      const SizedBox(width: 10),
      Expanded(
          child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: fill, foregroundColor: onFill(fill)),
              onPressed: onOk == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      onOk!();
                    },
              child: Text(ok))),
    ]);
  }
}

/// Asks yes or no in a bottom sheet (ANT asks in sheets, not dialogs: the
/// answer sits under the thumb). Swiping it away is a no.
Future<bool> confirmDialog(BuildContext context, String title,
    {String? body, String? ok, bool danger = false}) async {
  final result = await showMotionSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PlatformTheme(
              child: SheetBody(title: title, body: body, children: [
            SheetAnswers(
                cancel: tr3('取消', 'Болдырмау', 'Отмена'),
                ok: ok ?? tr3('确定', 'Иә', 'Да'),
                danger: danger,
                onOk: () => Navigator.pop(context, true)),
          ])));
  return result == true;
}

/// Asks for a line of text in a bottom sheet, above the keyboard. Null when
/// dismissed.
Future<String?> askText(BuildContext context, String title,
    {String? hint, String initial = '', bool required = true, int lines = 3}) {
  final controller = TextEditingController(text: initial);
  return showMotionSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PlatformTheme(
              child: SheetBody(title: title, children: [
            TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: lines,
                decoration: InputDecoration(hintText: hint)),
            const SizedBox(height: 14),
            SheetAnswers(
                cancel: tr3('取消', 'Болдырмау', 'Отмена'),
                ok: tr3('确定', 'Иә', 'Да'),
                onOk: () {
                  if (required && controller.text.trim().isEmpty) return;
                  Navigator.pop(context, controller.text.trim());
                }),
          ])));
}

/// Number field helper: parses "1 200,5" style input.
double? parseNum(String text) =>
    double.tryParse(text.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.'));

int? parseInt(String text) => parseNum(text)?.round();

/// Stars for a 1–5 score.
class Stars extends StatelessWidget {
  const Stars(this.value, {super.key, this.size = 14});
  final double value;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, size: size + 2, color: t.ink),
      const SizedBox(width: 2),
      Text(value.toStringAsFixed(1),
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// A soft gradient "cover" with an icon, standing in for listing photos.
class Cover extends StatelessWidget {
  const Cover(
      {super.key,
      required this.icon,
      required this.seed,
      this.height = 150,
      this.child,
      this.image});
  final IconData icon;
  final String seed;
  final double height;
  final Widget? child;
  final ImageProvider? image;
  static const _pairs = [
    (Color(0xffF3E3D3), Color(0xffD9B897)),
    (Color(0xffE7E9DC), Color(0xffC3CBAE)),
    (Color(0xffF6E6D6), Color(0xffE4B98F)),
    (Color(0xffEDE4EC), Color(0xffCDB9CF)),
    (Color(0xffE2E8EC), Color(0xffB7C7D3)),
  ];
  static const _nightPairs = [
    (Color(0xff3A2C20), Color(0xff2A2019)),
    (Color(0xff2C3226), Color(0xff22271D)),
    (Color(0xff3B2E22), Color(0xff2C2118)),
    (Color(0xff332B33), Color(0xff272128)),
    (Color(0xff283036), Color(0xff1F262B)),
  ];
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    // A drawing is a sheet of paper: it keeps the light backing at night.
    final pairs =
        t.dark && image == null && child == null ? _nightPairs : _pairs;
    final (a, b) = pairs[seed.hashCode.abs() % pairs.length];
    return ClipRRect(
        borderRadius: BorderRadius.circular(yRadius),
        child: Container(
            height: height,
            // A drawing sits on its own sheet of paper; the tinted
            // gradient is only the placeholder for a house without one.
            decoration: image != null
                ? BoxDecoration(
                    color: YTokens.paper,
                    image: DecorationImage(image: image!, fit: BoxFit.contain))
                : BoxDecoration(
                    gradient: LinearGradient(
                        colors: [a, b],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)),
            child: Stack(children: [
              if (image == null)
                Center(
                    child: Icon(icon,
                        size: height * 0.32,
                        color: (t.dark && child == null
                                ? Colors.white
                                : Colors.black)
                            .withValues(alpha: 0.25))),
              if (child != null) Positioned.fill(child: child!),
            ])));
  }
}
