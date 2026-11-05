import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Side-by-side view of quotes on one demand. No "cheapest" ranking; it
/// warns when scopes, units, pricing or versions differ.
class ComparePage extends StatelessWidget {
  const ComparePage(
      {super.key,
      required this.demand,
      required this.quotes,
      required this.profiles});
  final Demand demand;
  final List<Application> quotes;
  final Map<String, ServiceProfile?> profiles;

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    final issues = compareIssues(quotes);
    String nameOf(Application a) => profiles[a.profileId]?.name ?? '—';
    final rows =
        <(String, String Function(ApplicationVersion v, Application a))>[
      (
        tr3('价格', 'Баға', 'Цена'),
        (v, a) =>
            v.total == null ? tr3('需现场确认', 'Орында', 'Замер') : money(v.total)
      ),
      (tr3('计价方式', 'Баға түрі', 'Тип цены'), (v, a) => pricingName(v.pricing)),
      (
        tr3('人工／材料', 'Жұмыс / материал', 'Работа / материалы'),
        (v, a) => materialName(v.materials)
      ),
      (
        tr3('工期', 'Мерзім', 'Срок'),
        (v, a) => v.durationDays == null
            ? '—'
            : tr3('${v.durationDays} 天', '${v.durationDays} күн',
                '${v.durationDays} дн.')
      ),
      (
        tr3('承接范围', 'Көлемі', 'Объём'),
        (v, a) => v.scopeText.isEmpty ? '—' : v.scopeText
      ),
      (
        tr3('分项单价', 'Бірлік бағасы', 'Расценки'),
        (v, a) => v.lines.isEmpty
            ? '—'
            : v.lines
                .map((l) =>
                    '${l.name} ${numText(l.quantity)} ${unitLabel(l.unit)} × ${money(l.unitPrice)}')
                .join('\n')
      ),
      (
        tr3('包含', 'Кіреді', 'Входит'),
        (v, a) => v.includes.isEmpty ? '—' : v.includes
      ),
      (
        tr3('不包含', 'Кірмейді', 'Не входит'),
        (v, a) => v.excludes.isEmpty ? '—' : v.excludes
      ),
      (
        tr3('有效期', 'Жарамды', 'Действует до'),
        (v, a) => v.validUntil == null ? '—' : fmtDay(v.validUntil)
      ),
      (
        tr3('依据版本', 'Нұсқа', 'Версия'),
        (v, a) => '${v.demandVersionNo}${a.needsReconfirm ? ' ⚠' : ''}'
      ),
    ];
    const colWidth = 200.0;
    return PageScaffold(
        title: tr3('报价对比', 'Ұсыныстарды салыстыру', 'Сравнение предложений'),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(demand.current.title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              tr3(
                  '当前需求为第 ${demand.current.no} 版。平台不做最低价推荐。',
                  'Қазіргі нұсқа: ${demand.current.no}. Ең арзанды ұсынбаймыз.',
                  'Текущая версия ${demand.current.no}. Мы не рекомендуем «самое дешёвое».'),
              style: TextStyle(color: t.muted)),
          const SizedBox(height: 12),
          if (issues.isEmpty)
            Hint(tr3('这些报价的版本、材料范围和单位一致，可以直接比较。',
                'Ұсыныстар салыстыруға жарайды.', 'Предложения сопоставимы.'))
          else
            for (final i in issues)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Hint(compareIssueText(i), warn: true)),
          const SizedBox(height: 16),
          if (quotes.any((a) => a.current.lines.isNotEmpty)) ...[
            Text(
                tr3('按同一张清单逐项对比', 'Бір тізім бойынша салыстыру',
                    'Построчно по одной смете'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                tr3('每行最低价标绿；“未报”表示这位师傅没填这一项。', 'Ең төмені жасыл.',
                    'Минимум по строке выделен зелёным; «нет» — позиция не указана.'),
                style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: 8),
            SingleChildScrollView(
                key: const Key('line-compare'),
                scrollDirection: Axis.horizontal,
                child: _LineTable(quotes: quotes, nameOf: nameOf)),
            const SizedBox(height: 24),
          ],
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                  defaultColumnWidth: const FixedColumnWidth(colWidth),
                  columnWidths: const {0: FixedColumnWidth(110)},
                  border: TableBorder(
                      horizontalInside: BorderSide(color: t.line),
                      bottom: BorderSide(color: t.line),
                      top: BorderSide(color: t.line)),
                  children: [
                    TableRow(children: [
                      const SizedBox(),
                      for (final a in quotes)
                        Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(children: [
                              Avatar(nameOf(a), size: 28),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(nameOf(a),
                                      maxLines: 2,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700))),
                            ])),
                    ]),
                    for (final (label, cell) in rows)
                      TableRow(children: [
                        Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(label,
                                style:
                                    TextStyle(color: t.muted, fontSize: 13))),
                        for (final a in quotes)
                          Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(cell(a.current, a),
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.4))),
                      ]),
                  ])),
        ]));
  }
}

/// One row per bill-of-quantities line, one column per quote; the lowest
/// line total is marked, a missing line says so. Totals at the bottom.
class _LineTable extends StatelessWidget {
  const _LineTable({required this.quotes, required this.nameOf});
  final List<Application> quotes;
  final String Function(Application) nameOf;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final names = <String>[];
    final unitOf = <String, String>{};
    final qtyOf = <String, double>{};
    for (final a in quotes)
      for (final l in a.current.lines)
        if (!names.contains(l.name)) {
          names.add(l.name);
          unitOf[l.name] = l.unit;
          qtyOf[l.name] = l.quantity;
        }
    QuoteLine? lineOf(Application a, String n) =>
        a.current.lines.where((l) => l.name == n).firstOrNull;
    Widget cell(String text, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.all(10),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400)));
    return Table(
        defaultColumnWidth: const FixedColumnWidth(130),
        columnWidths: const {0: FixedColumnWidth(150)},
        border: TableBorder(
            horizontalInside: BorderSide(color: t.line),
            bottom: BorderSide(color: t.line),
            top: BorderSide(color: t.line)),
        children: [
          TableRow(children: [
            cell(tr3('项目', 'Позиция', 'Позиция'), color: t.muted),
            for (final a in quotes) cell(nameOf(a), bold: true),
          ]),
          for (final n in names)
            TableRow(children: [
              cell('$n · ${numText(qtyOf[n]!)} ${unitLabel(unitOf[n]!)}'),
              ...() {
                final totals = [for (final a in quotes) lineOf(a, n)?.total];
                final present = totals.whereType<double>();
                final min = present.isEmpty
                    ? null
                    : present.reduce((x, y) => x < y ? x : y);
                return [
                  for (final v in totals)
                    v == null
                        ? cell(tr3('未报', 'жоқ', 'нет'), color: t.faint)
                        : cell(money(v.round()),
                            color: present.length > 1 && v == min ? t.ok : null,
                            bold: present.length > 1 && v == min),
                ];
              }(),
            ]),
          TableRow(children: [
            cell(tr3('合计', 'Барлығы', 'Итого'), bold: true),
            for (final a in quotes)
              cell(
                  a.current.total == null
                      ? tr3('需现场确认', 'Орында', 'Замер')
                      : money(a.current.total),
                  bold: true),
          ]),
        ]);
  }
}
