import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'tokens.dart';

/// Small building blocks shared by every screen, after the drafting-table
/// page: segmented switches, a tab strip, sheets (cards), value grids, pills.

class Seg<T> extends StatelessWidget {
  const Seg(
      {super.key,
      required this.value,
      required this.items,
      required this.onChanged,
      this.label});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
        label: label,
        container: true,
        child: DecoratedBox(
            decoration: BoxDecoration(
                color: t.panel,
                border: Border.all(color: t.line),
                borderRadius: BorderRadius.circular(8)),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final (v, text) in items)
                    Semantics(
                        button: true,
                        selected: v == value,
                        child: Material(
                            color: v == value ? t.accent : Colors.transparent,
                            child: InkWell(
                                onTap: () => onChanged(v),
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 7),
                                    child: Text(text,
                                        style: TextStyle(
                                            fontSize: 13,
                                            height: 1.2,
                                            color: v == value
                                                ? t.accentInk
                                                : t.ink,
                                            fontWeight: v == value
                                                ? FontWeight.w600
                                                : FontWeight.w400))))))
                ]))));
  }
}

/// Sticky strip of page tabs; the current one sits on a sheet with an
/// amber underline.
class TabStrip extends StatelessWidget {
  const TabStrip(
      {super.key,
      required this.tabs,
      required this.current,
      required this.onSelect});
  final List<(String, String)> tabs;
  final String current;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
        decoration: BoxDecoration(
            color: t.bg, border: Border(bottom: BorderSide(color: t.line))),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (key, label) in tabs)
                Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Semantics(
                        selected: key == current,
                        button: true,
                        child: Material(
                            color: key == current ? t.panel : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                                key: ValueKey('tab-$key'),
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => onSelect(key),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: key == current
                                        ? BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border(
                                                bottom: BorderSide(
                                                    color: t.accent,
                                                    width: 2)))
                                        : null,
                                    child: Text(label,
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: key == current
                                                ? t.ink
                                                : t.muted,
                                            fontWeight: key == current
                                                ? FontWeight.w600
                                                : FontWeight.w400)))))))
            ])));
  }
}

/// White working sheet with a hairline border.
class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(10)),
        child: child);
  }
}

/// A titled card: heading, optional muted subtitle, then content.
class InfoCard extends StatelessWidget {
  const InfoCard(
      {super.key,
      this.title,
      this.titleWidget,
      this.subtitle,
      this.trailing,
      required this.children});
  final String? title, subtitle;
  final Widget? titleWidget, trailing;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Sheet(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null || titleWidget != null)
            Row(children: [
              Expanded(
                  child: titleWidget ??
                      Text(title!,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700))),
              if (trailing != null) trailing!
            ]),
          if (subtitle != null)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!,
                    style: TextStyle(fontSize: 12, color: t.muted))),
          ...children
        ]));
  }
}

/// One value in a [KvGrid]: big monospace figure over a muted label.
class Kv {
  const Kv(this.value, this.label, {this.onTap, this.color});
  final String value, label;
  final VoidCallback? onTap;
  final Color? color;
}

class KvGrid extends StatelessWidget {
  const KvGrid(this.items, {super.key, this.minWidth = 130});
  final List<Kv> items;
  final double minWidth;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(builder: (context, c) {
          final columns = math.max(1, ((c.maxWidth + 14) / (minWidth + 14)).floor());
          final width = (c.maxWidth - 14 * (columns - 1)) / columns;
          return Wrap(spacing: 14, runSpacing: 8, children: [
            for (final item in items)
              SizedBox(
                  width: width,
                  child: InkWell(
                      onTap: item.onTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                  child: Text(item.value,
                                      style: mono(
                                          size: 15,
                                          weight: FontWeight.w600,
                                          color: item.color ?? t.ink))),
                              if (item.onTap != null)
                                Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(Icons.edit_outlined,
                                        size: 13, color: t.muted))
                            ]),
                            Text(item.label,
                                style: TextStyle(fontSize: 12, color: t.muted))
                          ])))
          ]);
        }));
  }
}

/// Round pill used for layer toggles and modes.
class PillToggle extends StatelessWidget {
  const PillToggle(
      {super.key,
      required this.label,
      required this.selected,
      required this.onChanged,
      this.checkbox = true,
      this.icon,
      this.tooltip});
  final String label;
  final bool selected, checkbox;
  final IconData? icon;
  final String? tooltip;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final pill = Semantics(
        button: true,
        toggled: selected,
        label: tooltip ?? label,
        child: Material(
            color: selected && !checkbox
                ? Tokens.mix(t.accent, 0.12, t.panel)
                : t.panel,
            shape: StadiumBorder(
                side: BorderSide(
                    color: selected && !checkbox ? t.accent : t.line,
                    width: selected && !checkbox ? 1.5 : 1)),
            child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onChanged(!selected),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (checkbox)
                        Icon(
                            selected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 16,
                            color: selected ? t.accent : t.muted),
                      if (icon != null)
                        Icon(icon, size: 16, color: selected ? t.accent : t.ink),
                      const SizedBox(width: 6),
                      Text(label, style: TextStyle(fontSize: 13, color: t.ink))
                    ])))));
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Bordered compact button.
class Btn extends StatelessWidget {
  const Btn(
      {super.key,
      required this.label,
      this.onPressed,
      this.icon,
      this.tooltip,
      this.danger = false,
      this.primary = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? tooltip;
  final bool danger, primary;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = onPressed == null
        ? t.muted.withValues(alpha: 0.5)
        : danger
            ? t.crit
            : primary
                ? t.accentInk
                : t.ink;
    final button = Material(
        color: primary ? t.accent : t.panel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: primary ? t.accent : t.line)),
        child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: label.isEmpty && icon != null
                ? Center(child: Icon(icon, size: 17, color: color))
                : Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[
                        Icon(icon, size: 16, color: color),
                        if (label.isNotEmpty) const SizedBox(width: 6)
                      ],
                      if (label.isNotEmpty)
                        Flexible(
                            child: Text(label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: color)))
                    ]))));
    return tooltip == null
        ? Semantics(button: true, label: label, child: button)
        : Tooltip(message: tooltip!, child: button);
  }
}

enum Level { crit, warn, chk, ok }

Color levelColor(Tokens t, Level l) => switch (l) {
      Level.crit => t.crit,
      Level.warn => t.warn,
      Level.chk => t.chk,
      Level.ok => t.ok
    };

class TagPill extends StatelessWidget {
  const TagPill(this.text, this.color, {super.key});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
            color: Tokens.mix(color, 0.16, t.panel),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: color)));
  }
}

/// Muted side note with a left rule.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color ?? t.line, width: 3))),
        child: Text(text,
            style: TextStyle(fontSize: 12, height: 1.5, color: t.muted)));
  }
}

/// A plain data table: muted header, hairline rows, monospace numbers.
class TableCellData {
  const TableCellData(this.text,
      {this.numeric = false,
      this.muted = false,
      this.bold = false,
      this.color,
      this.onTap,
      this.highlight = false});
  final String text;
  final bool numeric, muted, bold, highlight;
  final Color? color;
  final VoidCallback? onTap;
}

class PlainTable extends StatelessWidget {
  const PlainTable(
      {super.key, this.header, required this.rows, this.highlightColumn});
  final List<String>? header;
  final List<List<TableCellData>> rows;
  final int? highlightColumn;
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    var wrap = 220.0;
    Widget cell(TableCellData d, int column, {bool head = false}) {
      final style = head
          ? TextStyle(
              fontSize: 12,
              color: t.muted,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4)
          : d.numeric
              ? mono(
                  size: 13,
                  weight: d.bold ? FontWeight.w600 : FontWeight.w400,
                  color: d.color ?? (d.muted ? t.muted : t.ink))
              : TextStyle(
                  fontSize: 13,
                  fontWeight: d.bold ? FontWeight.w700 : FontWeight.w400,
                  color: d.color ?? (d.muted ? t.muted : t.ink));
      // Words wrap so tables fit phones; figures stay on one line.
      Widget text = d.numeric || head
          ? Text(d.text,
              style: style, textAlign: d.numeric ? TextAlign.right : null)
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wrap),
              child: Text(d.text, style: style));
      if (d.onTap != null)
        text = Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                d.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(child: text),
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined, size: 12, color: t.muted)
            ]);
      final highlight = d.highlight || column == highlightColumn;
      return Material(
          color: highlight
              ? Tokens.mix(t.accent, 0.12, t.panel)
              : Colors.transparent,
          child: InkWell(
              onTap: d.onTap,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: Align(
                      alignment: d.numeric
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      widthFactor: 1,
                      child: text))));
    }

    final columns = math.max(header?.length ?? 0,
        rows.fold<int>(0, (m, r) => math.max(m, r.length)));
    final border = BorderSide(color: t.line);
    return LayoutBuilder(builder: (context, c) {
      // Text columns wrap at under half the width so two fit a phone.
      if (c.maxWidth.isFinite) wrap = (c.maxWidth * 0.42).clamp(110.0, 220.0);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
        constraints: BoxConstraints(
            minWidth: c.maxWidth.isFinite ? c.maxWidth : 0),
        child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder(horizontalInside: border, bottom: border),
            children: [
              if (header != null)
                TableRow(children: [
                  for (var i = 0; i < columns; i++)
                    cell(TableCellData(i < header!.length ? header![i] : ''), i,
                        head: true)
                ]),
              for (final row in rows)
                TableRow(children: [
                  for (var i = 0; i < columns; i++)
                    cell(i < row.length ? row[i] : const TableCellData(''), i)
                ])
            ])));
    });
  }
}

/// Text input dialog returning the edited text, or null when cancelled.
Future<String?> promptText(BuildContext context,
    {required String title,
    required String initial,
    required String cancel,
    required String ok,
    bool number = false,
    bool multiline = false,
    String? suffix}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                  width: 420,
                  child: TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: multiline ? 3 : 1,
                      maxLines: multiline ? 8 : 1,
                      keyboardType: number
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : multiline
                              ? TextInputType.multiline
                              : TextInputType.text,
                      decoration: InputDecoration(suffixText: suffix),
                      onSubmitted: multiline
                          ? null
                          : (v) => Navigator.pop(context, v))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(cancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: Text(ok))
              ]));
}
