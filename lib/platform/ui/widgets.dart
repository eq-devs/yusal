import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/settings.dart';
import 'theme.dart';
import '../../motion/motion.dart';

/// Shared building blocks of the platform pages.

/// Width-limited page with an app bar and an optional sticky action bar.
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
  Widget build(BuildContext context) {
    final content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: scroll
                ? SingleChildScrollView(padding: padding, child: body)
                : Padding(padding: padding, child: body)));
    return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(top: false, child: content),
        bottomNavigationBar: bottom == null ? null : ActionBar(child: bottom!));
  }
}

/// Sticky bottom bar with a hairline on top, like a booking bar.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return DecoratedBox(
        decoration: BoxDecoration(
            color: t.bg, border: Border(top: BorderSide(color: t.line))),
        child: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
    return Pressable(
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
                    child: Padding(padding: padding, child: child)))));
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
                    fontSize: 20, fontWeight: FontWeight.w700, height: 1.2))),
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
            color: filled ? c : c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : c)));
  }
}

/// Pill-shaped filter toggle.
class FilterPill extends StatelessWidget {
  const FilterPill(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap,
      this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Semantics(
        button: true,
        selected: selected,
        child: Material(
            color: selected ? t.ink : t.bg,
            shape: StadiumBorder(
                side: BorderSide(color: selected ? t.ink : t.line)),
            child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[
                        Icon(icon, size: 16, color: selected ? t.bg : t.ink),
                        const SizedBox(width: 6),
                      ],
                      Text(label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? t.bg : t.ink)),
                    ])))));
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
              child:
                  Text(label, style: TextStyle(color: t.muted, fontSize: 14))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500))),
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
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon ?? (warn ? Icons.error_outline : Icons.info_outline),
              size: 18, color: warn ? t.warn : t.muted),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13,
                      color: warn ? t.warn : t.ink,
                      height: 1.4))),
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
    setState(() => busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed == null || busy ? null : run;
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 18),
              const SizedBox(width: 8)
            ],
            Flexible(
                child: Text(widget.label, overflow: TextOverflow.ellipsis)),
          ]);
    final button = widget.outlined
        ? OutlinedButton(onPressed: onPressed, child: child)
        : FilledButton(onPressed: onPressed, child: child);
    return widget.expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
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
                                fontSize: 18, fontWeight: FontWeight.w700)),
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
                                    fontSize: 18, fontWeight: FontWeight.w700)),
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

Future<bool> confirmDialog(BuildContext context, String title,
    {String? body, String? ok, bool danger = false}) async {
  final result = await showDialog<bool>(
      context: context,
      builder: (context) => PlatformTheme(
              child: AlertDialog(
                  title: Text(title),
                  content: body == null ? null : Text(body),
                  actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(ok ?? tr3('确定', 'Иә', 'Да'))),
              ])));
  return result == true;
}

Future<String?> askText(BuildContext context, String title,
    {String? hint, String initial = '', bool required = true, int lines = 3}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
      context: context,
      builder: (context) => PlatformTheme(
              child: AlertDialog(
                  title: Text(title),
                  content: TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: 1,
                      maxLines: lines,
                      decoration: InputDecoration(hintText: hint)),
                  actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                FilledButton(
                    onPressed: () {
                      if (required && controller.text.trim().isEmpty) return;
                      Navigator.pop(context, controller.text.trim());
                    },
                    child: Text(tr3('确定', 'Иә', 'Да'))),
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
  @override
  Widget build(BuildContext context) {
    final (a, b) = _pairs[seed.hashCode.abs() % _pairs.length];
    return ClipRRect(
        borderRadius: BorderRadius.circular(yRadius),
        child: Container(
            height: height,
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [a, b],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                image: image == null
                    ? null
                    : DecorationImage(image: image!, fit: BoxFit.contain)),
            child: Stack(children: [
              if (image == null)
                Center(
                    child: Icon(icon,
                        size: height * 0.32,
                        color: Colors.black.withValues(alpha: 0.25))),
              if (child != null) Positioned.fill(child: child!),
            ])));
  }
}
