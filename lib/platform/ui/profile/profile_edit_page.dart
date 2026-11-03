import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Create or edit an individual or team service profile. Only the name,
/// trades, regions, kind and availability are required.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, this.profile, this.role});
  final ServiceProfile? profile;

  /// Preselected role when joining as a professional.
  final ProRole? role;
  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _PriceRow {
  _PriceRow(this.amount, this.unit, this.scope);
  final TextEditingController amount, scope;
  String unit;
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  ProfileKind kind = ProfileKind.individual;
  late ProRole role = widget.role ?? ProRole.worker;
  final name = TextEditingController(),
      experience = TextEditingController(),
      teamSize = TextEditingController(),
      bio = TextEditingController();
  List<String> trades = [], regions = [];
  Availability availability = Availability.now;
  DateTime? availableFrom;
  final prices = <_PriceRow>[];
  List<Work> works = [];
  bool showPhone = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    if (p == null) return;
    kind = p.kind;
    role = p.role;
    name.text = p.name;
    experience.text = p.experienceYears?.toString() ?? '';
    teamSize.text = p.teamSize?.toString() ?? '';
    bio.text = p.bio;
    trades = [...p.trades];
    regions = [...p.regions];
    availability = p.availability;
    availableFrom = p.availableFrom;
    works = [...p.works];
    showPhone = p.showPhone;
    for (final r in p.refPrices) {
      prices.add(_PriceRow(TextEditingController(text: '${r.amount}'), r.unit,
          TextEditingController(text: r.scope)));
    }
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || trades.isEmpty || regions.isEmpty) {
      setState(() => error = tr3(
          '请填写名称、工种和服务地区',
          'Атау, мамандық және аймақ керек',
          'Укажите имя, специальности и районы'));
      return;
    }
    final refPrices = <RefPrice>[];
    for (final r in prices) {
      final a = parseInt(r.amount.text);
      if (a == null || a <= 0 || r.scope.text.trim().isEmpty) {
        setState(() => error = tr3(
            '参考价需要金额、单位和适用范围',
            'Бағаға сома мен қамту керек',
            'У цены должны быть сумма, единица и пояснение'));
        return;
      }
      refPrices
          .add(RefPrice(amount: a, unit: r.unit, scope: r.scope.text.trim()));
    }
    final old = widget.profile;
    final p = ServiceProfile(
        id: old?.id ?? '',
        ownerId: old?.ownerId ?? '',
        kind: kind,
        role: role,
        name: name.text,
        trades: trades,
        regions: regions,
        availability: availability,
        availableFrom:
            availability == Availability.fromDate ? availableFrom : null,
        availabilityConfirmedAt: DateTime.now(),
        experienceYears: parseInt(experience.text),
        teamSize: kind == ProfileKind.team ? parseInt(teamSize.text) : null,
        refPrices: refPrices,
        bio: bio.text.trim(),
        works: works,
        status: old?.status ?? ProfileStatus.active,
        showPhone: showPhone);
    final saved = await attempt(context, () => context.repos.saveProfile(p),
        success: tr3('名片已保存', 'Профиль сақталды', 'Профиль сохранён'));
    if (saved != null && mounted) Navigator.pop(context);
  }

  Widget picker(String label, String value, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
          onTap: onTap,
          child: InputDecorator(
              decoration: InputDecoration(
                  labelText: label, suffixIcon: const Icon(Icons.expand_more)),
              child: Text(value.isEmpty
                  ? tr3('请选择', 'Таңдаңыз', 'Выберите')
                  : value))));

  Widget field(TextEditingController c, String label,
          {bool number = false, int lines = 1}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              minLines: lines,
              maxLines: lines + 3,
              keyboardType: number ? TextInputType.number : null,
              decoration: InputDecoration(labelText: label)));

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return PageScaffold(
        title: widget.profile == null
            ? tr3('创建接活名片', 'Профиль жасау', 'Создать профиль')
            : tr3('编辑名片', 'Профильді өзгерту', 'Редактировать профиль'),
        bottom: BusyButton(
            label: tr3('保存', 'Сақтау', 'Сохранить'), onPressed: save),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Hint(tr3(
              '不需要正式简历。先填必需信息，经验、价格和作品可以以后慢慢完善。',
              'Түйіндеме керек емес, қалғанын кейін толтырасыз.',
              'Резюме не нужно: сначала главное, остальное потом.')),
          const SizedBox(height: 16),
          Text(tr3('我是', 'Мен', 'Я'),
              style: TextStyle(color: YTokens.of(context).muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in ProRole.values)
              FilterPill(
                  label: proRoleName(r),
                  selected: role == r,
                  onTap: () => setState(() {
                        role = r;
                        if (r == ProRole.contractor) kind = ProfileKind.team;
                      })),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            for (final k in ProfileKind.values)
              FilterPill(
                  label: profileKindName(k),
                  selected: kind == k,
                  onTap: () => setState(() => kind = k)),
          ]),
          const SizedBox(height: 14),
          field(
              name,
              kind == ProfileKind.team
                  ? tr3('团队名称', 'Бригада атауы', 'Название бригады')
                  : tr3('姓名', 'Аты-жөні', 'Имя')),
          picker(tr3('工种', 'Мамандық', 'Специальности'),
              trades.map(tradeName).join('、'), () async {
            final v = await pickMany<String>(
                context,
                tr3('工种', 'Мамандық', 'Специальности'),
                [for (final c in tradeCodes) (c, tradeName(c))],
                trades);
            if (v != null) setState(() => trades = v);
          }),
          picker(
              tr3('服务地区', 'Аймақ', 'Районы'), regions.map(regionName).join('、'),
              () async {
            final v = await pickMany<String>(
                context,
                tr3('服务地区', 'Аймақ', 'Районы'),
                [for (final c in regionCodes) (c, regionName(c))],
                regions);
            if (v != null) setState(() => regions = v);
          }),
          Text(tr3('接活状态', 'Күйі', 'Статус'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (a, label) in [
              (Availability.now, tr3('现在可接', 'Қазір бос', 'Свободен')),
              (Availability.fromDate, tr3('指定日期后', 'Күннен бастап', 'С даты')),
              (Availability.notTaking, tr3('暂不接活', 'Алмаймын', 'Не беру')),
            ])
              FilterPill(
                  label: label,
                  selected: availability == a,
                  onTap: () => setState(() => availability = a)),
          ]),
          if (availability == Availability.fromDate)
            ListTile(
                title: Text(fmtDay(availableFrom)),
                trailing: const Icon(Icons.event),
                onTap: () async {
                  final v = await showDatePicker(
                      context: context,
                      firstDate: context.now,
                      lastDate: context.now.add(const Duration(days: 365)),
                      initialDate: availableFrom ??
                          context.now.add(const Duration(days: 7)));
                  if (v != null) setState(() => availableFrom = v);
                }),
          const SizedBox(height: 14),
          field(experience, tr3('从业年数（可选）', 'Тәжірибе (жыл)', 'Опыт, лет'),
              number: true),
          if (kind == ProfileKind.team)
            field(teamSize, tr3('团队人数', 'Адам саны', 'Человек в бригаде'),
                number: true),
          field(bio, tr3('简介（可选）', 'Өзіңіз туралы', 'О себе'), lines: 2),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                  tr3('在名片上公开电话', 'Телефонды көрсету', 'Показывать телефон')),
              subtitle: Text(tr3('默认隐藏；也可以只在聊天中向指定的人展示。', 'Әдепкіде жасырын.',
                  'По умолчанию скрыт; можно показать в чате конкретному человеку.')),
              value: showPhone,
              onChanged: (v) => setState(() => showPhone = v)),
          SectionTitle(tr3('参考价格', 'Бағдарлы баға', 'Ориентировочные цены'),
              trailing: TextButton(
                  onPressed: () => setState(() => prices.add(_PriceRow(
                      TextEditingController(), 'm3', TextEditingController()))),
                  child: Text(tr3('添加', 'Қосу', 'Добавить')))),
          for (final (i, r) in prices.indexed)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: r.amount,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '₸'))),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                        value: r.unit,
                        items: [
                          for (final u in priceUnits)
                            DropdownMenuItem(
                                value: u,
                                child: Text(u == 'total'
                                    ? unitLabel(u)
                                    : '/ ${unitLabel(u)}')),
                        ],
                        onChanged: (v) => setState(() => r.unit = v ?? 'm3')),
                    IconButton(
                        tooltip: tr3('删除', 'Жою', 'Удалить'),
                        onPressed: () => setState(() => prices.removeAt(i)),
                        icon: const Icon(Icons.close)),
                  ]),
                  const SizedBox(height: 6),
                  TextField(
                      controller: r.scope,
                      decoration: InputDecoration(
                          labelText: tr3('适用范围', 'Не кіреді', 'Что входит'),
                          hintText: tr3('例如：仅人工，砌墙', 'Мысалы: тек жұмыс',
                              'Напр.: только работа, кладка'))),
                ])),
          SectionTitle(tr3('作品', 'Жұмыстар', 'Работы'),
              trailing: TextButton(
                  onPressed: () async {
                    final title = await askText(
                        context, tr3('作品标题', 'Атауы', 'Название'),
                        lines: 1);
                    if (title != null)
                      setState(() => works.add(Work(
                          id: 'w${DateTime.now().microsecondsSinceEpoch}',
                          title: title,
                          source: WorkSource.uploaded,
                          photoCount: 1)));
                  },
                  child: Text(tr3('上传', 'Жүктеу', 'Загрузить')))),
          for (final w in works)
            ListTile(
                leading: Icon(w.source == WorkSource.platform
                    ? Icons.handshake_outlined
                    : Icons.photo_outlined),
                title: Text(w.title),
                subtitle: Text(w.source == WorkSource.platform
                    ? tr3('平台合作记录（不可编辑）', 'Платформадан',
                        'С платформы (нельзя изменить)')
                    : tr3('自主上传', 'Өзі жүктеген', 'Загружено')),
                trailing: w.source == WorkSource.uploaded
                    ? IconButton(
                        tooltip: tr3('删除', 'Жою', 'Удалить'),
                        onPressed: () => setState(() => works.remove(w)),
                        icon: const Icon(Icons.delete_outline))
                    : null),
          if (error != null) Hint(error!, warn: true),
        ]));
  }
}
