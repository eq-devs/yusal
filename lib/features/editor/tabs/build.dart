part of '../page.dart';

/// The building schedule: stages in order with dates, a checklist for each,
/// money spent against the stage's budget from the estimate, and progress.
extension _BuildTab on _HouseEditorState {
  Future<void> editStageStart(BuildStage s, DateTime? planned) async {
    final text = await promptText(context,
        title:
            '${stageName(s)} · ${tr3('开工日期 (年-月-日，留空跟随上一阶段)', 'Басталу күні (жыл-ай-күн, бос қалса алдыңғы кезеңнен кейін)', 'Дата начала (год-месяц-день, если пусто — после предыдущего этапа)', 'Start date (year-month-day; if empty, after the previous stage)', ky: 'Башталган күнү (жыл-ай-күн; бош болсо, мурунку этаптан кийин)', uz: 'Boshlanish sanasi (yil-oy-kun; boʻsh boʻlsa, oldingi bosqichdan keyin)')}',
        initial: s.start ??
            (planned == null ? formatDay(DateTime.now()) : formatDay(planned)),
        cancel: tr3('取消', 'Болдырмау', 'Отмена', 'Cancel', ky: 'Жокко чыгаруу', uz: 'Bekor qilish'),
        ok: tr3('确定', 'Жарайды', 'ОК', 'OK', ky: 'OK', uz: 'OK'));
    if (text == null) return;
    final trimmed = text.trim();
    if (trimmed.isNotEmpty && parseDay(trimmed) == null) {
      notify(tr3(
          '日期格式应为 2027-04-01',
          'Күн пішімі 2027-04-01 сияқты болуы керек',
          'Дата должна быть в формате 2027-04-01',
          'Use the date format 2027-04-01', ky: 'Күндү 2027-04-01 форматында жазыңыз', uz: 'Sanani 2027-04-01 formatida yozing'));
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
        title:
            '${tr3('施工进度', 'Құрылыс кестесі', 'График строительства', 'Build schedule', ky: 'Курулуш графиги', uz: 'Qurilish jadvali')} · ${(done * 100).round()}%',
        subtitle: first == null
            ? tr3(
                '给第一个阶段填开工日期后，会排出每个阶段的日期。',
                'Бірінші кезеңге басталу күнін жазсаңыз, әр кезеңнің күні есептеледі.',
                'Укажите дату начала первого этапа, и даты всех этапов будут рассчитаны.',
                'Set the start date of the first stage and all stage dates are calculated.', ky: 'Биринчи этаптын башталган күнүн коюңуз, бардык этаптардын күндөрү эсептелет.', uz: 'Birinchi bosqich boshlanish sanasini kiriting, barcha bosqich sanalari hisoblanadi.')
            : '${formatDay(first)} → ${last == null ? '?' : formatDay(last)}',
        trailing: IconButton(
            tooltip:
                tr3('恢复默认阶段', 'Әдепкі кезеңдер', 'Вернуть этапы по умолчанию', 'Restore the default stages', ky: 'Демейки этаптарды калыбына келтирүү', uz: 'Standart bosqichlarni tiklash'),
            visualDensity: VisualDensity.compact,
            onPressed: doc.extras.schedule.isEmpty
                ? null
                : () => action('ResetSchedule', {}),
            icon: const Icon(YIcons.refresh, size: 18)),
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
            Kv(
                '$days ${tr3('天', 'күн', 'дн.', 'd', ky: 'к', uz: 'k')}',
                tr3('总工期 (各阶段相加)', 'Жалпы мерзім (кезеңдер қосындысы)',
                    'Общий срок (сумма этапов)',
                    'Total duration (sum of stages)', ky: 'Жалпы мөөнөт (этаптардын суммасы)', uz: 'Umumiy muddat (bosqichlar yigʻindisi)')),
            Kv('${stages.where((s) => s.status == StageStatus.done).length} / ${stages.length}',
                tr3('完成阶段', 'Аяқталған кезең', 'Завершено этапов', 'Stages finished', ky: 'Бүткөн этаптар', uz: 'Tugagan bosqichlar')),
            Kv('$sym ${groupDigits(spent)}', tr3('已花费', 'Жұмсалды', 'Потрачено', 'Spent', ky: 'Жумшалды', uz: 'Sarflandi'),
                color: spent > budget ? t.crit : null),
            Kv(
                '$sym ${groupDigits(budget)}',
                tr3('预算 (见“预算”页)', 'Смета («Смета» беті)',
                    'Смета (см. раздел «Смета»)',
                    'Estimate (see “Estimate”)', ky: 'Смета («Смета» бөлүмүн караңыз)', uz: 'Smeta (“Smeta” boʻlimiga qarang)')),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Btn(
                label: tr3('添加阶段', 'Кезең қосу', 'Добавить этап', 'Add a stage', ky: 'Этап кошуу', uz: 'Bosqich qoʻshish'),
                icon: YIcons.add,
                onPressed: () async {
                  final name = await askText(
                      tr3('阶段名称 (如：打井)', 'Кезең атауы (мысалы: құдық қазу)',
                          'Название этапа (например: копка колодца)',
                          'Stage name (e.g. digging a well)', ky: 'Этаптын аталышы (мис., кудук казуу)', uz: 'Bosqich nomi (masalan, quduq qazish)'),
                      '');
                  if (name == null || name.trim().isEmpty || !mounted) return;
                  final d = await askNumber(
                      tr3('工期 (天)', 'Мерзімі (күн)', 'Длительность (дней)', 'Duration (days)', ky: 'Мөөнөтү (күн)', uz: 'Muddati (kun)'), 7);
                  if (d == null) return;
                  action('AddStage', {'name': name.trim(), 'days': d.round()});
                }),
            Btn(
                label: tr3('预算', 'Смета', 'Смета', 'Estimate', ky: 'Смета', uz: 'Smeta'),
                icon: YIcons.budget,
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(
                onTap: () => update(() => expandedStage = open ? null : s.key),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Text('${index + 1}',
                            style: mono(size: 12, color: t.muted)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(stageName(s),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700))),
                        TagPill(
                            statusName(s.status),
                            switch (s.status) {
                              StageStatus.done => t.ok,
                              StageStatus.doing => t.accent,
                              StageStatus.todo => t.muted,
                            }),
                        Icon(open ? YIcons.chevronUp : YIcons.chevronDown,
                            size: 20, color: t.muted),
                      ]),
                      const SizedBox(height: 6),
                      // Timeline bar, positioned on the whole schedule.
                      Tooltip(
                          message:
                              '${stageName(s)} · ${s.days} ${tr3('天', 'күн', 'дн.', 'd', ky: 'к', uz: 'k')}${p.start == null ? '' : ' · ${formatDay(p.start!)} → ${formatDay(p.end!)}'}',
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
                            '${s.days} ${tr3('天', 'күн', 'дн.', 'd', ky: 'к', uz: 'k')}',
                            if (p.start != null)
                              '${formatDay(p.start!)} → ${formatDay(p.end!)}',
                            if (b != null)
                              '${tr3('预算', 'смета', 'смета', 'estimate', ky: 'смета', uz: 'smeta')} $sym ${groupDigits(b)}',
                            if (s.spent > 0)
                              '${tr3('已花', 'жұмсалды', 'потрачено', 'spent', ky: 'жумшалды', uz: 'sarflandi')} $sym ${groupDigits(s.spent)}',
                            if (checks.isNotEmpty)
                              '✓ ${s.checks.where((c) => c < checks.length).length}/${checks.length}',
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  b != null && s.spent > b ? t.crit : t.muted)),
                    ])),
            if (open) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final st in StageStatus.values)
                  PillToggle(
                      label: statusName(st),
                      checkbox: false,
                      selected: s.status == st,
                      onChanged: (_) => action(
                          'SetStage', {'stageKey': s.key, 'status': st})),
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
                Kv(
                    s.start ?? (p.start == null ? '—' : formatDay(p.start!)),
                    s.start == null
                        ? tr3('开工 (跟随上一阶段)', 'Басталуы (алдыңғыдан кейін)',
                            'Начало (после предыдущего)',
                            'Start (after the previous one)', ky: 'Башталышы (мурункусунан кийин)', uz: 'Boshlanishi (oldingisidan keyin)')
                        : tr3('开工日期', 'Басталу күні', 'Дата начала', 'Start date', ky: 'Башталган күнү', uz: 'Boshlanish sanasi'),
                    onTap: () => editStageStart(s, p.start)),
                Kv('${s.days}',
                    tr3('工期 (天)', 'Мерзімі (күн)', 'Длительность (дней)', 'Duration (days)', ky: 'Мөөнөтү (күн)', uz: 'Muddati (kun)'),
                    onTap: () async {
                  final v = await askNumber(
                      tr3('工期 (天)', 'Мерзімі (күн)', 'Длительность (дней)', 'Duration (days)', ky: 'Мөөнөтү (күн)', uz: 'Muddati (kun)'),
                      s.days);
                  if (v != null) {
                    action('SetStage', {'stageKey': s.key, 'days': v.round()});
                  }
                }),
                Kv('$sym ${groupDigits(s.spent)}',
                    tr3('已花费', 'Жұмсалды', 'Потрачено', 'Spent', ky: 'Жумшалды', uz: 'Sarflandi'), onTap: () async {
                  final v = await askNumber(
                      '${tr3('已花费', 'Жұмсалды', 'Потрачено', 'Spent', ky: 'Жумшалды', uz: 'Sarflandi')} ($sym)', s.spent);
                  if (v != null) {
                    action('SetStage', {'stageKey': s.key, 'spent': v.round()});
                  }
                }),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Btn(
                    label: s.note.isEmpty
                        ? tr3('写备注', 'Жазба қосу', 'Добавить заметку', 'Add a note', ky: 'Эскертме кошуу', uz: 'Izoh qoʻshish')
                        : tr3('改备注', 'Жазбаны өзгерту', 'Изменить заметку', 'Edit the note', ky: 'Эскертмени түзөтүү', uz: 'Izohni tahrirlash'),
                    icon: YIcons.edit,
                    onPressed: () async {
                      final v = await askText(
                          tr3(
                              '备注 (施工队、电话、问题…)',
                              'Жазба (құрылысшы, телефон, мәселе…)',
                              'Заметка (бригада, телефон, проблема…)',
                              'Note (crew, phone, problem…)', ky: 'Эскертме (бригада, телефон, көйгөй…)', uz: 'Izoh (brigada, telefon, muammo…)'),
                          s.note,
                          multiline: true);
                      if (v != null) {
                        action('SetStage', {'stageKey': s.key, 'note': v});
                      }
                    }),
                if (s.custom)
                  Btn(
                      label: tr3('删除阶段', 'Кезеңді жою', 'Удалить этап', 'Delete the stage', ky: 'Этапты өчүрүү', uz: 'Bosqichni oʻchirish'),
                      icon: YIcons.delete,
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
      Note(tr3(
          '每个阶段的预算 = “预算”页对应部分 (含人工) + 预备费。点阶段展开检查清单；隐蔽工程 (钢筋、水管、电线) 封闭前一定拍照留底。',
          'Әр кезеңнің сметасы = «Смета» бетіндегі сәйкес бөлік (жұмыспен) + резерв. Кезеңді басып тексеру тізімін ашыңыз; жасырын жұмыстарды (арматура, құбыр, сым) жаппас бұрын міндетті түрде суретке түсіріңіз.',
          'Смета каждого этапа = соответствующая часть страницы «Смета» (с работой) + резерв. Нажмите на этап, чтобы открыть список проверки; скрытые работы (арматура, трубы, проводка) обязательно сфотографируйте до закрытия.',
          "Each stage's estimate = its share of the “Estimate” page (with labour) + contingency. Tap a stage to open its checklist; always photograph hidden work (rebar, pipes, wiring) before it's covered.", ky: 'Ар бир этаптын сметасы = «Смета» бетиндеги үлүшү (жумуш менен) + күтүлбөгөн чыгымдар. Текшерүү тизмесин ачуу үчүн этапты басыңыз; жашыруун иштерди (арматура, түтүктөр, зымдар) жабылганга чейин сөзсүз сүрөткө тартыңыз.', uz: 'Har bir bosqich smetasi = “Smeta” sahifasidagi ulushi (ish haqi bilan) + kutilmagan xarajatlar. Tekshiruv roʻyxatini ochish uchun bosqichga bosing; yashirin ishlarni (armatura, quvurlar, simlar) yopilishidan oldin albatta suratga oling.')),
    ]);
  }
}
