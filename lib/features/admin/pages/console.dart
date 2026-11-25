part of '../page.dart';

// The back office's operating pages: feedback, broadcasts, banned words,
// trends and exports. They talk to the real backend only.

HttpAdminRepository? _http(BuildContext context) =>
    switch (context.read(adminRepositoryProvider)) {
      final HttpAdminRepository api => api,
      _ => null,
    };

/// Messages people sent from the app's feedback form.
class FeedbackInboxPage extends StatefulWidget {
  const FeedbackInboxPage({super.key});
  @override
  State<FeedbackInboxPage> createState() => _FeedbackInboxPageState();
}

class _FeedbackInboxPageState extends State<FeedbackInboxPage> {
  bool _open = true;
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final api = _http(context);
    final t = YTokens.of(context);
    return Scaffold(
        appBar: AppBar(title: Text(tr3('用户反馈', 'Пікірлер', 'Обратная связь', 'Feedback', ky: 'Пикир-сунуштар', uz: 'Fikr-mulohazalar'))),
        body: api == null
            ? const SizedBox.shrink()
            : Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(
                        YSpace.gutter, YSpace.sm, YSpace.gutter, 0),
                    child: Wrap(spacing: 8, children: [
                      ChoiceChip(
                          label: Text(tr3('未处理', 'Өңделмеген', 'Новые', 'New', ky: 'Жаңы', uz: 'Yangi')),
                          selected: _open,
                          onSelected: (_) => setState(() => _open = true)),
                      ChoiceChip(
                          label: Text(_all),
                          selected: !_open,
                          onSelected: (_) => setState(() => _open = false)),
                    ])),
                Expanded(
                    child: _PagedList<FeedbackItem>(
                        key: ValueKey('$_open-$_version'),
                        load: (p) => api.feedbackInbox(open: _open, page: p),
                        empty: tr3('没有反馈', 'Пікір жоқ', 'Сообщений нет', 'No messages', ky: 'Билдирүүлөр жок', uz: 'Xabarlar yoʻq'),
                        item: (context, f) => Card(
                            margin: const EdgeInsets.only(bottom: YSpace.sm),
                            child: Padding(
                                padding: const EdgeInsets.all(YSpace.md),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(f.text, style: YText.body),
                                      const SizedBox(height: 6),
                                      Text(
                                          [
                                            _date(f.createdAt),
                                            ...f.context.values,
                                            if (f.accountId == null)
                                              tr3('未登录', 'Кірмеген',
                                                  'Без входа',
                                                  'Not signed in', ky: 'Кирген эмес', uz: 'Kirmagan'),
                                          ].join(' · '),
                                          style: YText.caption
                                              .copyWith(color: t.muted)),
                                      Row(children: [
                                        if (f.accountId != null)
                                          TextButton(
                                              onPressed: () => pushPage<void>(
                                                  context,
                                                  (_) => AccountDetailPage(
                                                      accountId: f.accountId!)),
                                              child: Text(tr3('看账号', 'Аккаунт',
                                                  'Аккаунт',
                                                  'Account', ky: 'Аккаунт', uz: 'Akkaunt'))),
                                        const Spacer(),
                                        if (f.handledAt == null)
                                          TextButton(
                                              onPressed: () async {
                                                await attempt(
                                                    context,
                                                    () =>
                                                        api.markFeedbackHandled(
                                                            f.id));
                                                if (mounted) {
                                                  setState(() => _version++);
                                                }
                                              },
                                              child: Text(tr3(
                                                  '标为已处理',
                                                  'Өңделді',
                                                  'Отметить обработанным',
                                                  'Mark as handled', ky: 'Каралды деп белгилөө', uz: 'Koʻrib chiqildi deb belgilash')))
                                        else
                                          StatusPill(tr3(
                                              '已处理', 'Өңделді', 'Обработано', 'Handled', ky: 'Каралды', uz: 'Koʻrib chiqildi')),
                                      ]),
                                    ])))))
              ]));
  }
}

/// A push to everyone's phone, written in each language.
class BroadcastPage extends StatefulWidget {
  const BroadcastPage({super.key});
  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final _title = TextEditingController(text: 'Yusal');
  final _texts = {
    for (final l in const ['zh', 'kk', 'ru']) l: TextEditingController()
  };
  String? _lang;

  @override
  void dispose() {
    _title.dispose();
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _langName(String l) => switch (l) {
        'zh' => '中文',
        'kk' => 'Қазақша',
        _ => 'Русский',
      };

  Future<void> _send(HttpAdminRepository api) async {
    final texts = {
      for (final e in _texts.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()
    };
    if (_title.text.trim().isEmpty || texts.isEmpty) {
      toast(
          context,
          tr3('请填写标题和至少一种语言的内容', 'Тақырып пен мәтінді жазыңыз',
              'Заполните заголовок и текст',
              'Fill in the title and text', ky: 'Аталышын жана текстин толтуруңуз', uz: 'Sarlavha va matnni toʻldiring'));
      return;
    }
    if (!await confirmDialog(context,
            tr3('发送给所有人？', 'Барлығына жіберу керек пе?', 'Отправить всем?', 'Send to everyone?', ky: 'Баарына жөнөтөсүзбү?', uz: 'Hammaga yuborilsinmi?'),
            body: tr3(
                '推送会立刻发到所有用户的手机，不能撤回。',
                'Хабарландыру бірден барлық телефонға кетеді, қайтарылмайды.',
                'Уведомление сразу уйдёт на все телефоны, отменить нельзя.',
                "The notification goes to every phone at once and can't be undone.", ky: 'Билдирме бардык телефондорго бир убакта барат жана аны кайтаруу мүмкүн эмес.', uz: 'Bildirishnoma barcha telefonlarga bir vaqtda boradi va uni qaytarib boʻlmaydi.'),
            ok: tr3('发送', 'Жіберу', 'Отправить', 'Send', ky: 'Жөнөтүү', uz: 'Yuborish')) ||
        !mounted) {
      return;
    }
    final sent = await attempt(
        context, () => api.broadcast(_title.text.trim(), texts, lang: _lang));
    if (sent != null && mounted) {
      toast(
          context,
          tr3('已发到 $sent 台设备', '$sent құрылғыға жіберілді',
              'Отправлено на $sent устройств',
              'Sent to $sent devices', ky: '$sent түзмөккө жөнөтүлдү', uz: '$sent ta qurilmaga yuborildi'));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = _http(context);
    final t = YTokens.of(context);
    return Scaffold(
        appBar:
            AppBar(title: Text(tr3('群发通知', 'Жаппай хабарландыру', 'Рассылка', 'Broadcast', ky: 'Жалпы билдирүү', uz: 'Ommaviy xabar'))),
        body: api == null
            ? const SizedBox.shrink()
            : ListView(padding: const EdgeInsets.all(YSpace.gutter), children: [
                TextField(
                    controller: _title,
                    maxLength: 60,
                    decoration: InputDecoration(
                        labelText: tr3('标题', 'Тақырып', 'Заголовок', 'Title', ky: 'Аталышы', uz: 'Sarlavha'))),
                for (final e in _texts.entries) ...[
                  const SizedBox(height: YSpace.sm),
                  TextField(
                      controller: e.value,
                      maxLines: 3,
                      maxLength: 300,
                      decoration: InputDecoration(labelText: _langName(e.key))),
                ],
                Text(
                    tr3(
                        '每台手机收到它设置的语言；没写的语言用俄语。',
                        'Әр телефон өз тілінде алады; жазылмаған тілге орысшасы кетеді.',
                        'Каждый телефон получает свой язык; если его нет, уходит русский.',
                        "Each phone gets its own language; if it's missing, Russian is sent.", ky: 'Ар бир телефон өз тилинде алат; ал жок болсо, орусча жөнөтүлөт.', uz: 'Har bir telefon oʻz tilida oladi; u boʻlmasa, ruscha yuboriladi.'),
                    style: YText.caption.copyWith(color: t.muted)),
                const SizedBox(height: YSpace.md),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: Text(tr3('所有人', 'Барлығы', 'Всем', 'Everyone', ky: 'Баарына', uz: 'Hammaga')),
                      selected: _lang == null,
                      onSelected: (_) => setState(() => _lang = null)),
                  for (final l in const ['zh', 'kk', 'ru'])
                    ChoiceChip(
                        label: Text(tr3('只发${_langName(l)}',
                            'Тек ${_langName(l)}', 'Только ${_langName(l)}', 'Only ${_langName(l)}', ky: '${_langName(l)} гана', uz: 'Faqat ${_langName(l)}')),
                        selected: _lang == l,
                        onSelected: (_) => setState(() => _lang = l)),
                ]),
                const SizedBox(height: YSpace.lg),
                BusyButton(
                    label: tr3('发送', 'Жіберу', 'Отправить', 'Send', ky: 'Жөнөтүү', uz: 'Yuborish'),
                    icon: Icons.send_outlined,
                    onPressed: () => _send(api)),
              ]));
  }
}

/// Words that send a demand back, on top of the built-in ones.
class BannedWordsPage extends StatelessWidget {
  const BannedWordsPage({super.key});

  Future<void> _add(
      BuildContext context, HttpAdminRepository api, List<String> words) async {
    final w = await askText(
        context, tr3('添加违禁词', 'Тыйым сөз қосу', 'Добавить слово', 'Add a word', ky: 'Сөз кошуу', uz: 'Soʻz qoʻshish'),
        lines: 1);
    if (w == null || w.trim().isEmpty || !context.mounted) return;
    await attempt(context, () => api.bannedWords([...words, w.trim()]),
        success: tr3('已保存', 'Сақталды', 'Сохранено', 'Saved', ky: 'Сакталды', uz: 'Saqlandi'));
  }

  @override
  Widget build(BuildContext context) {
    final api = _http(context);
    final canOperate = _may(context, AdminPerms.operate);
    final t = YTokens.of(context);
    return Scaffold(
        appBar: AppBar(
            title: Text(tr3('违禁词', 'Тыйым сөздер', 'Запрещённые слова', 'Banned words', ky: 'Тыюу салынган сөздөр', uz: 'Taqiqlangan soʻzlar'))),
        body: api == null
            ? const SizedBox.shrink()
            : _Reloading<({List<String> builtin, List<String> words})>(
                load: api.bannedWords,
                builder: (context, b, reload) => ListView(
                        padding: const EdgeInsets.all(YSpace.gutter),
                        children: [
                          Text(
                              tr3(
                                  '需求里出现这些词会被退回，并说明原因。',
                                  'Тапсырыста осы сөздер болса, себебімен қайтарылады.',
                                  'Заявка с этими словами возвращается с объяснением.',
                                  'Requests with these words are sent back with an explanation.', ky: 'Бул сөздөр бар суроо-талаптар түшүндүрмө менен кайтарылат.', uz: 'Bu soʻzlar bor soʻrovlar izoh bilan qaytariladi.'),
                              style: YText.caption.copyWith(color: t.muted)),
                          SectionTitle(tr3('内置', 'Кірістірілген', 'Встроенные', 'Built-in', ky: 'Камтылган', uz: 'Oʻrnatilgan'),
                              top: 16),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final w in b.builtin) Chip(label: Text(w)),
                          ]),
                          SectionTitle(
                              tr3('后台添加', 'Қосылғандар', 'Добавленные', 'Added', ky: 'Кошулган', uz: 'Qoʻshilgan'),
                              trailing: canOperate
                                  ? TextButton(
                                      onPressed: () async {
                                        await _add(context, api, b.words);
                                        reload();
                                      },
                                      child:
                                          Text(tr3('添加', 'Қосу', 'Добавить', 'Add', ky: 'Кошуу', uz: 'Qoʻshish')))
                                  : null),
                          if (b.words.isEmpty)
                            Text(tr3('还没有', 'Әзірге жоқ', 'Пока нет', 'None yet', ky: 'Азырынча жок', uz: 'Hozircha yoʻq'),
                                style: YText.caption.copyWith(color: t.muted)),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final w in b.words)
                              InputChip(
                                  label: Text(w),
                                  onDeleted: canOperate
                                      ? () async {
                                          await attempt(
                                              context,
                                              () => api.bannedWords(
                                                  [...b.words]..remove(w)));
                                          reload();
                                        }
                                      : null),
                          ]),
                        ])));
  }
}

/// The price list of each region that the cost estimate uses: the team's
/// entries, and beside them the median of what users reported.
class PricesPage extends StatefulWidget {
  const PricesPage({super.key});
  @override
  State<PricesPage> createState() => _PricesPageState();
}

class _PricesPageState extends State<PricesPage> {
  String _region = priceRegions.first;
  bool _labour = false;

  String _name(String key) => switch (key) {
        'masonry_brick' => masonryUnitName(MasonryUnit.brick),
        'masonry_cinder' => masonryUnitName(MasonryUnit.cinder),
        _ => costLineName(key),
      };

  Future<void> _edit(BuildContext context, HttpAdminRepository api, String key,
      PriceEntry? entry) async {
    final text = await askText(context, '${_name(key)} · ${priceRegionName(_region)}',
        hint: tr3('坚戈；留空则删除这条', 'Теңге; өшіру үшін бос қалдырыңыз',
            'Тенге; оставьте пустым, чтобы удалить',
            'Tenge; leave empty to remove the entry', ky: 'Теңге; өчүрүү үчүн бош калтырыңыз', uz: 'Tenge; oʻchirish uchun boʻsh qoldiring'),
        initial: entry == null ? '' : '${entry.price}',
        required: false,
        lines: 1);
    if (text == null || !context.mounted) return;
    final price = int.tryParse(text.replaceAll(RegExp(r'[\s,]'), ''));
    if (text.trim().isNotEmpty && (price == null || price <= 0)) return;
    if (price == null && entry == null) return;
    await attempt(context,
        () => api.setPrice(_region, key, labour: _labour, price: price),
        success: tr3('已保存', 'Сақталды', 'Сохранено', 'Saved', ky: 'Сакталды', uz: 'Saqlandi'));
  }

  @override
  Widget build(BuildContext context) {
    final api = _http(context);
    final canOperate = _may(context, AdminPerms.operate);
    final t = YTokens.of(context);
    final keys = _labour
        ? defaultLabour[Currency.kzt]!.keys.toList()
        : [
            ...defaultPrices[Currency.kzt]!.keys,
            'masonry_brick',
            'masonry_cinder'
          ];
    return Scaffold(
        appBar: AppBar(
            title: Text(tr3('地区价格', 'Аймақ бағалары', 'Цены по регионам', 'Regional prices', ky: 'Аймактык баалар', uz: 'Hududiy narxlar'))),
        body: api == null
            ? const SizedBox.shrink()
            : _Reloading<({List<PriceEntry> entries, List<PriceEntry> reports})>(
                key: ValueKey(_region),
                load: () => api.prices(_region),
                builder: (context, p, reload) {
                  PriceEntry? of(List<PriceEntry> list, String key) {
                    for (final e in list) {
                      if (e.key == key && e.labour == _labour) return e;
                    }
                    return null;
                  }

                  return ListView(
                      padding: const EdgeInsets.all(YSpace.gutter),
                      children: [
                        Text(
                            tr3(
                                '预算页先用用户自己填的价，其次是这里的地区价，再次是同地区至少 3 人报价的中位数，然后是全国价，最后才是示例价。',
                                'Смета алдымен пайдаланушының өз бағасын, сосын осы аймақ бағасын, одан кейін аймақтағы кемінде 3 адам хабарлаған бағаның медианасын, содан соң ел бойынша бағаны, ең соңында мысал бағаны алады.',
                                'Смета берёт сначала цену самого пользователя, затем цену региона отсюда, затем медиану цен от не менее чем 3 пользователей региона, затем цену по стране и только потом примерную.',
                                'The estimate uses the user’s own price first, then the region’s price from here, then the median reported by at least 3 users there, then the country’s price, and the example last.', ky: 'Смета адегенде колдонуучунун өз баасын, андан кийин ушул жердеги аймак баасын, андан соң аймактагы кеминде 3 колдонуучу билдирген баанын медианасын, анан өлкө боюнча бааны, эң акырында болжолдуу бааны алат.', uz: 'Smeta avval foydalanuvchining oʻz narxini, soʻng shu yerdagi hudud narxini, keyin hududdagi kamida 3 foydalanuvchi bildirgan narx medianasini, soʻng mamlakat narxini, eng oxirida taxminiy narxni oladi.'),
                            style: YText.caption.copyWith(color: t.muted)),
                        const SizedBox(height: 12),
                        DropdownButton<String>(
                            key: const Key('admin-prices-region'),
                            isExpanded: true,
                            value: _region,
                            items: [
                              for (final r in priceRegions)
                                DropdownMenuItem(
                                    value: r, child: Text(priceRegionName(r)))
                            ],
                            onChanged: (r) {
                              if (r != null) setState(() => _region = r);
                            }),
                        const SizedBox(height: 8),
                        SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                  value: false,
                                  label: Text(tr3('材料单价', 'Материал бағасы', 'Цены материалов', 'Material prices', ky: 'Материал баалары', uz: 'Material narxlari'))),
                              ButtonSegment(
                                  value: true,
                                  label: Text(tr3('人工单价', 'Жұмыс бағасы', 'Цены работ', 'Labour rates', ky: 'Жумуш баалары', uz: 'Ish narxlari'))),
                            ],
                            selected: {_labour},
                            onSelectionChanged: (v) =>
                                setState(() => _labour = v.first)),
                        const SizedBox(height: 8),
                        for (final key in keys)
                          Builder(builder: (context) {
                            final entry = of(p.entries, key);
                            final market = of(p.reports, key);
                            final unit = unitName(costUnits[
                                    key.startsWith('masonry_')
                                        ? 'masonryExt'
                                        : key] ??
                                '');
                            return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${_name(key)} · ₸/$unit'),
                                subtitle: Text([
                                  if (entry != null)
                                    '${priceSourceName(entry.source)} · ${entry.date}',
                                  if (market != null)
                                    '${tr3('用户报价中位数', 'Пайдаланушылар медианасы', 'Медиана пользователей', 'Users’ median', ky: 'Колдонуучулардын медианасы', uz: 'Foydalanuvchilar medianasi')} ${money(market.price)} (${market.reports})',
                                ].join('\n')),
                                trailing: Text(
                                    entry == null ? '—' : money(entry.price),
                                    style: YText.body.copyWith(
                                        color: entry == null
                                            ? t.muted
                                            : null)),
                                onTap: canOperate
                                    ? () async {
                                        await _edit(context, api, key, entry);
                                        reload();
                                      }
                                    : null);
                          }),
                      ]);
                }));
  }
}

/// New accounts, houses, demands and quotes per day, last 30 days.
class TrendsPage extends StatelessWidget {
  const TrendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = _http(context);
    final t = YTokens.of(context);
    final series = <(String, int Function(TrendDay))>[
      (tr3('新用户', 'Жаңа аккаунт', 'Новые аккаунты', 'New accounts', ky: 'Жаңы аккаунттар', uz: 'Yangi akkauntlar'), (d) => d.users),
      (tr3('新房子', 'Жаңа үй', 'Новые дома', 'New houses', ky: 'Жаңы үйлөр', uz: 'Yangi uylar'), (d) => d.posts),
      (tr3('新需求', 'Жаңа тапсырыс', 'Новые заявки', 'New requests', ky: 'Жаңы суроо-талаптар', uz: 'Yangi soʻrovlar'), (d) => d.demands),
      (tr3('新报价', 'Жаңа ұсыныс', 'Новые отклики', 'New responses', ky: 'Жаңы жооптор', uz: 'Yangi javoblar'), (d) => d.quotes),
    ];
    return Scaffold(
        appBar: AppBar(
            title: Text(tr3('近 30 天', 'Соңғы 30 күн', 'Последние 30 дней', 'Last 30 days', ky: 'Акыркы 30 күн', uz: 'Soʻnggi 30 kun'))),
        body: api == null
            ? const SizedBox.shrink()
            : _Reloading<List<TrendDay>>(
                load: api.trends,
                builder: (context, days, _) => ListView(
                        padding: const EdgeInsets.all(YSpace.gutter),
                        children: [
                          for (final (name, of) in series) ...[
                            SectionTitle(
                                '$name · ${days.fold<int>(0, (s, d) => s + of(d))}',
                                top: 12),
                            SizedBox(
                                height: 72,
                                child: _TrendBars(
                                    values: [for (final d in days) of(d)],
                                    color: t.accent)),
                            Row(children: [
                              Text(days.first.date.substring(5),
                                  style:
                                      YText.caption.copyWith(color: t.muted)),
                              const Spacer(),
                              Text(days.last.date.substring(5),
                                  style:
                                      YText.caption.copyWith(color: t.muted)),
                            ]),
                          ],
                        ])));
  }
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.values, required this.color});
  final List<int> values;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final top = values.fold<int>(1, (m, v) => v > m ? v : m);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final v in values)
        Expanded(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FractionallySizedBox(
                    heightFactor: v == 0 ? 0.02 : v / top,
                    child: Tooltip(
                        message: '$v',
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: v == 0
                                    ? color.withValues(alpha: 0.2)
                                    : color,
                                borderRadius:
                                    BorderRadius.circular(YRadius.row))))))),
    ]);
  }
}

/// Loads once, shows [builder], and loads again on `reload()`.
class _Reloading<T> extends StatefulWidget {
  const _Reloading({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, VoidCallback reload) builder;
  @override
  State<_Reloading<T>> createState() => _ReloadingState<T>();
}

class _ReloadingState<T> extends State<_Reloading<T>> {
  late Future<T> _future = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
      future: _future,
      builder: (context, snap) => snap.hasData
          ? widget.builder(context, snap.data as T,
              () => setState(() => _future = widget.load()))
          : snap.hasError
              ? Center(
                  child: TextButton(
                      onPressed: () => setState(() => _future = widget.load()),
                      child: Text(failureText(snap.error!))))
              : const Center(child: CircularProgressIndicator()));
}

/// Saves a CSV export and opens the share sheet.
Future<void> _export(BuildContext context, String what) async {
  final api = _http(context);
  if (api == null) return;
  final bytes = await attempt(context, () => api.export(what));
  if (bytes == null || !context.mounted) return;
  final day = DateTime.now().toIso8601String().substring(0, 10);
  await SharePlus.instance.share(ShareParams(files: [
    XFile.fromData(Uint8List.fromList(bytes),
        mimeType: 'text/csv', name: 'yusal-$what-$day.csv')
  ], fileNameOverrides: [
    'yusal-$what-$day.csv'
  ]));
}
