part of '../house_editor.dart';

/// The building schedule: stages in order with dates, a checklist for each,
/// money spent against the stage's budget from the estimate, and progress.
extension _BuildTab on _HouseEditorState {
  Future<void> editStageStart(BuildStage s, DateTime? planned) async {
    final text = await promptText(context,
        title: '${stageName(s)} · ${tr('开工日期 (年-月-日，留空跟随上一阶段)', 'Басталу күні (жыл-ай-күн, бос қалса алдыңғы кезеңнен кейін)')}',
        initial: s.start ?? (planned == null ? formatDay(DateTime.now()) : formatDay(planned)),
        cancel: tr('取消', 'Болдырмау'),
        ok: tr('确定', 'Жарайды'));
    if (text == null) return;
    final trimmed = text.trim();
    if (trimmed.isNotEmpty && parseDay(trimmed) == null) {
      notify(tr('日期格式应为 2027-04-01', 'Күн пішімі 2027-04-01 сияқты болуы керек'));
      return;
    }
    action('SetStage', {
      'stageKey': s.key,
      'start': trimmed.isEmpty ? '' : formatDay(parseDay(trimmed)!)
    });
  }

  Widget buildTab(bool wide) {
    final t = Tokens.of(context);
    final doc = history.present;
    final stages = doc.extras.stages;
    final plan = planStages(stages);
    final e = estimate;
    final sym = currencySymbol(e.currency);
    final budgets = stageBudgets(e);
    final spent = stages.fold(0, (s, x) => s + x.spent);
    final budget = budgets.values.fold(0.0, (s, v) => s + v) +
        e.stageMaterials('other') * (1 + e.contingencyPct / 100);
    final done = progress(stages);
    final days = stages.fold(0, (s, x) => s + x.days);
    final first = plan.map((p) => p.start).whereType<DateTime>().firstOrNull;
    final last = plan.map((p) => p.end).whereType<DateTime>().lastOrNull;
    // Timeline: dated stages on the calendar, otherwise one after another.
    final spanStart = first ?? DateTime.utc(2000);
    var cursor = 0;
    final offsets = <String, (int, int)>{};
    for (final p in plan) {
      if (p.start != null && first != null) {
        offsets[p.stage.key] =
            (p.start!.difference(spanStart).inDays, p.stage.days);
      } else {
        offsets[p.stage.key] = (cursor, p.stage.days);
      }
      cursor = offsets[p.stage.key]!.$1 + p.stage.days;
    }
    final span = offsets.values.fold(1, (m, o) => math.max(m, o.$1 + o.$2));
    Color statusColor(StageStatus s) => switch (s) {
          StageStatus.done => t.ok,
          StageStatus.doing => t.dark ? const Color(0xffCF8020) : t.accent,
          StageStatus.todo => Tokens.mix(t.muted, 0.45, t.panel),
        };
    final summary = InfoCard(
        title: '${tr('施工进度', 'Құрылыс кестесі')} · ${(done * 100).round()}%',
        subtitle: first == null
            ? tr('给第一个阶段填开工日期后，会排出每个阶段的日期。',
                'Бірінші кезеңге басталу күнін жазсаңыз, әр кезеңнің күні есептеледі.')
            : '${formatDay(first)} → ${last == null ? '?' : formatDay(last)}',
        trailing: IconButton(
            tooltip: tr('恢复默认阶段', 'Әдепкі кезеңдер'),
            visualDensity: VisualDensity.compact,
            onPressed: doc.extras.schedule.isEmpty
                ? null
                : () => action('ResetSchedule', {}),
            icon: const Icon(Icons.restart_alt, size: 18)),
        children: [
          const SizedBox(height: 10),
          // Meter: share of work done on a lighter track of the same hue.
          Semantics(
              label: '${(done * 100).round()}%',
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                      height: 8,
                      child: Stack(children: [
                        Positioned.fill(
                            child: ColoredBox(
                                color: Tokens.mix(t.ok, 0.18, t.panel))),
                        FractionallySizedBox(
                            widthFactor: done.clamp(0.0, 1.0),
                            child: ColoredBox(color: t.ok)),
                      ])))),
          KvGrid([
            Kv('$days ${tr('天', 'күн')}', tr('总工期 (各阶段相加)', 'Жалпы мерзім (кезеңдер қосындысы)')),
            Kv('${stages.where((s) => s.status == StageStatus.done).length} / ${stages.length}',
                tr('完成阶段', 'Аяқталған кезең')),
            Kv('$sym ${money(spent)}', tr('已花费', 'Жұмсалды'),
                color: spent > budget ? t.crit : null),
            Kv('$sym ${money(budget)}', tr('预算 (见“预算”页)', 'Смета («Смета» беті)')),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr('添加阶段', 'Кезең қосу'),
                icon: Icons.add,
                onPressed: () async {
                  final name = await askText(tr('阶段名称 (如：打井)', 'Кезең атауы (мысалы: құдық қазу)'), '');
                  if (name == null || name.trim().isEmpty || !mounted) return;
                  final d = await askNumber(tr('工期 (天)', 'Мерзімі (күн)'), 7);
                  if (d == null) return;
                  action('AddStage', {'name': name.trim(), 'days': d.round()});
                }),
            Btn(
                label: tr('预算', 'Смета'),
                icon: Icons.payments_outlined,
                onPressed: () => showTab('cost')),
          ]),
        ]);
    Widget stageCard(PlannedStage p, int index) {
      final s = p.stage;
      final checks = stageChecks[s.key] ?? const [];
      final b = budgets[s.key];
      final o = offsets[s.key]!;
      final open = expandedStage == s.key;
      return Sheet(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
                onTap: () => update(() => expandedStage = open ? null : s.key),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Text('${index + 1}', style: mono(size: 12, color: t.muted)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(stageName(s),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700))),
                    TagPill(statusName(s.status), switch (s.status) {
                      StageStatus.done => t.ok,
                      StageStatus.doing => t.accent,
                      StageStatus.todo => t.muted,
                    }),
                    Icon(open ? Icons.expand_less : Icons.expand_more,
                        size: 20, color: t.muted),
                  ]),
                  const SizedBox(height: 6),
                  // Timeline bar, positioned on the whole schedule.
                  Tooltip(
                      message:
                          '${stageName(s)} · ${s.days} ${tr('天', 'күн')}${p.start == null ? '' : ' · ${formatDay(p.start!)} → ${formatDay(p.end!)}'}',
                      child: LayoutBuilder(
                          builder: (context, c) => SizedBox(
                              height: 10,
                              child: Stack(children: [
                                Positioned(
                                    left: c.maxWidth * o.$1 / span,
                                    width: math.max(
                                        3.0, c.maxWidth * o.$2 / span),
                                    top: 0,
                                    bottom: 0,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: statusColor(s.status),
                                            borderRadius:
                                                BorderRadius.circular(4)))),
                              ])))),
                  const SizedBox(height: 4),
                  Text(
                      [
                        '${s.days} ${tr('天', 'күн')}',
                        if (p.start != null)
                          '${formatDay(p.start!)} → ${formatDay(p.end!)}',
                        if (b != null) '${tr('预算', 'смета')} $sym ${money(b)}',
                        if (s.spent > 0) '${tr('已花', 'жұмсалды')} $sym ${money(s.spent)}',
                        if (checks.isNotEmpty)
                          '✓ ${s.checks.where((c) => c < checks.length).length}/${checks.length}',
                      ].join(' · '),
                      style: TextStyle(
                          fontSize: 12,
                          color: b != null && s.spent > b ? t.crit : t.muted)),
                ])),
            if (open) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final st in StageStatus.values)
                  PillToggle(
                      label: statusName(st),
                      checkbox: false,
                      selected: s.status == st,
                      onChanged: (_) =>
                          action('SetStage', {'stageKey': s.key, 'status': st})),
              ]),
              for (var i = 0; i < checks.length; i++)
                // Its own Material so the tile's ink shows over the sheet.
                Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: s.checks.contains(i),
                        title: Text(tr(checks[i].$1, checks[i].$2),
                            style: const TextStyle(fontSize: 13)),
                        onChanged: (_) => action('SetStage',
                            {'stageKey': s.key, 'toggleCheck': i}))),
              KvGrid([
                Kv(s.start ?? (p.start == null ? '—' : formatDay(p.start!)),
                    s.start == null ? tr('开工 (跟随上一阶段)', 'Басталуы (алдыңғыдан кейін)') : tr('开工日期', 'Басталу күні'),
                    onTap: () => editStageStart(s, p.start)),
                Kv('${s.days}', tr('工期 (天)', 'Мерзімі (күн)'), onTap: () async {
                  final v = await askNumber(tr('工期 (天)', 'Мерзімі (күн)'), s.days);
                  if (v != null)
                    action('SetStage', {'stageKey': s.key, 'days': v.round()});
                }),
                Kv('$sym ${money(s.spent)}', tr('已花费', 'Жұмсалды'), onTap: () async {
                  final v = await askNumber('${tr('已花费', 'Жұмсалды')} ($sym)', s.spent);
                  if (v != null)
                    action('SetStage', {'stageKey': s.key, 'spent': v.round()});
                }),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Btn(
                    label: s.note.isEmpty ? tr('写备注', 'Жазба қосу') : tr('改备注', 'Жазбаны өзгерту'),
                    icon: Icons.edit_note,
                    onPressed: () async {
                      final v = await askText(tr('备注 (施工队、电话、问题…)', 'Жазба (құрылысшы, телефон, мәселе…)'),
                          s.note,
                          multiline: true);
                      if (v != null)
                        action('SetStage', {'stageKey': s.key, 'note': v});
                    }),
                if (s.custom)
                  Btn(
                      label: tr('删除阶段', 'Кезеңді жою'),
                      icon: Icons.delete_outline,
                      danger: true,
                      onPressed: () =>
                          action('DeleteStage', {'stageKey': s.key})),
              ]),
              if (s.note.isNotEmpty) Note(s.note),
            ],
          ]));
    }

    return page([
      summary,
      for (var i = 0; i < plan.length; i++) stageCard(plan[i], i),
      Note(tr('每个阶段的预算 = “预算”页对应部分 (含人工) + 预备费。点阶段展开检查清单；隐蔽工程 (钢筋、水管、电线) 封闭前一定拍照留底。',
          'Әр кезеңнің сметасы = «Смета» бетіндегі сәйкес бөлік (жұмыспен) + резерв. Кезеңді басып тексеру тізімін ашыңыз; жасырын жұмыстарды (арматура, құбыр, сым) жаппас бұрын міндетті түрде суретке түсіріңіз.')),
    ]);
  }
}
