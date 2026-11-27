import 'dart:typed_data';

import 'package:yusal/features/me/repository/trust_repository.dart';
import 'package:yusal/features/me/state/trust.dart';
import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/admin_models.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/photos.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

// User-facing trust and safety: reporting, appeals, worker verification,
// new-demand alerts and push settings.

/// The reasons a user picks from when reporting; sent as `code:<name>`.
const _reportReasons = ['fake', 'abuse', 'spam', 'contact', 'illegal'];

/// Asks why and reports [targetId]; preset reasons need no typing.
Future<void> reportContent(
    BuildContext context, ReportTarget target, String targetId) async {
  if (!await requireLogin(context) || !context.mounted) return;
  final code = await pickOne<String>(
      context, tr3('举报原因', 'Шағым себебі', 'Причина жалобы', 'Reason for the report', ky: 'Арыздын себеби', uz: 'Shikoyat sababi'), [
    for (final c in _reportReasons) (c, reasonCodeText(c)),
    ('other', tr3('其他，自己填写', 'Басқа', 'Другое', 'Other', ky: 'Башка', uz: 'Boshqa')),
  ]);
  if (code == null || !context.mounted) return;
  var reason = 'code:$code';
  if (code == 'other') {
    final text = await askText(
        context, tr3('举报原因', 'Шағым себебі', 'Причина жалобы', 'Reason for the report', ky: 'Арыздын себеби', uz: 'Shikoyat sababi'),
        hint: tr3('说明发生了什么', 'Не болғанын жазыңыз', 'Опишите, что произошло', 'Describe what happened', ky: 'Эмне болгонун сүрөттөңүз', uz: 'Nima boʻlganini tasvirlang'));
    if (text == null || !context.mounted) return;
    reason = text;
  }
  await attempt(
      context,
      () => context
          .read(moderationRepositoryProvider)
          .report(target, targetId, reason),
      success: tr3('已提交，审核人员会处理并告诉你结果', 'Жіберілді, нәтижесін хабарлаймыз',
          'Жалоба отправлена, мы сообщим о результате',
          "Report sent; we'll let you know the outcome", ky: 'Арыз жөнөтүлдү; жыйынтыгын билдиребиз', uz: 'Shikoyat yuborildi; natijasini maʼlum qilamiz'));
}

/// Asks the owner why a decision was wrong and files the appeal.
Future<void> appealDecision(
    BuildContext context, String target, String targetId) async {
  final text = await askText(context, tr3('申诉', 'Шағымдану', 'Обжаловать', 'Appeal', ky: 'Даттануу', uz: 'Apellyatsiya'),
      hint: tr3('说明为什么这个处理有误，审核人员会重新查看', 'Неге қате екенін жазыңыз',
          'Объясните, почему решение ошибочно',
          'Explain why the decision is wrong', ky: 'Чечим эмне үчүн туура эмес экенин түшүндүрүңүз', uz: 'Qaror nima uchun notoʻgʻri ekanini tushuntiring'),
      lines: 5);
  if (text == null || !context.mounted) return;
  await attempt(
      context,
      () => context
          .read(moderationRepositoryProvider)
          .fileAppeal(target, targetId, text),
      success:
          tr3('申诉已提交，处理后会通知你', 'Шағым жіберілді', 'Обжалование отправлено', 'Appeal sent', ky: 'Даттануу жөнөтүлдү', uz: 'Apellyatsiya yuborildi'));
}

String _appealStatusText(AppealStatus s) => switch (s) {
      AppealStatus.open => tr3('处理中', 'Қаралуда', 'На рассмотрении', 'Under review', ky: 'Каралууда', uz: 'Koʻrib chiqilmoqda'),
      AppealStatus.accepted =>
        tr3('已恢复', 'Қалпына келтірілді', 'Восстановлено', 'Restored', ky: 'Калыбына келтирилди', uz: 'Tiklandi'),
      AppealStatus.rejected =>
        tr3('维持原处理', 'Шешім өзгеріссіз', 'Решение оставлено', 'Decision upheld', ky: 'Чечим күчүндө калды', uz: 'Qaror kuchda qoldi'),
    };

/// The appeals I have filed and their answers.
class MyAppealsPage extends StatelessWidget {
  const MyAppealsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(tr3('我的申诉', 'Шағымдарым', 'Мои обжалования', 'My appeals', ky: 'Менин даттанууларым', uz: 'Mening apellyatsiyalarim'))),
      body: Live<List<Appeal>>(
          provider: myAppealsProvider,
          builder: (context, list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.gavel_outlined,
                  title: tr3('没有申诉记录', 'Шағым жоқ', 'Обжалований нет', 'No appeals', ky: 'Даттануулар жок', uz: 'Apellyatsiyalar yoʻq'))
              : ListView(
                  padding: const EdgeInsets.all(YSpace.gutter),
                  children: [
                      for (final a in list)
                        Padding(
                            padding: const EdgeInsets.only(bottom: YSpace.md),
                            child: YCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(
                                            a.targetTitle.isEmpty
                                                ? tr3('我的账号', 'Аккаунтым',
                                                    'Мой аккаунт',
                                                    'My account', ky: 'Менин аккаунтум', uz: 'Mening akkauntim')
                                                : a.targetTitle,
                                            style: YText.bodyStrong)),
                                    StatusPill(_appealStatusText(a.status)),
                                  ]),
                                  const SizedBox(height: YSpace.xs),
                                  Text(a.text, style: YText.body),
                                  if (a.resolution.isNotEmpty) ...[
                                    const SizedBox(height: YSpace.sm),
                                    Hint(reasonText(a.resolution)),
                                  ],
                                ]))),
                    ])));
}

/// Which pushes I get; the inbox keeps everything either way.
class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});

  static const _quiet = [
    ('', ''),
    ('22:00', '08:00'),
    ('23:00', '07:00'),
    ('21:00', '09:00'),
  ];

  String _quietLabel(String start, String end) => start.isEmpty
      ? tr3('只用平台默认（22:00–08:00）', 'Әдепкі (22:00–08:00)',
          'По умолчанию (22:00–08:00)',
          'Default (22:00–08:00)', ky: 'Демейки (22:00–08:00)', uz: 'Standart (22:00–08:00)')
      : '$start–$end';

  Future<void> _save(BuildContext context, NotificationSettings s) => attempt(
      context,
      () => context.read(trustRepositoryProvider).saveNotificationSettings(s));

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Scaffold(
        appBar: AppBar(title: Text(tr3('通知设置', 'Хабарламалар', 'Уведомления', 'Notifications', ky: 'Билдирмелер', uz: 'Bildirishnomalar'))),
        body: Live<NotificationSettings>(
            provider: notificationSettingsProvider,
            builder: (context, s) {
              bool on(String c) => !s.muted.contains(c);
              NotificationSettings toggled(String c, bool v) =>
                  NotificationSettings(muted: [
                    for (final m in s.muted)
                      if (m != c) m,
                    if (!v) c
                  ], quietStart: s.quietStart, quietEnd: s.quietEnd);
              return ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: YSpace.gutter),
                  children: [
                    SettingsGroup(
                        title:
                            tr3('推送到手机', 'Телефонға жіберу', 'Пуш-уведомления', 'Push notifications', ky: 'Push-билдирмелер', uz: 'Push-bildirishnomalar'),
                        children: [
                          SettingsRow(
                              icon: YIcons.coop,
                              title: tr3('合作与报名', 'Келісім мен өтінімдер',
                                  'Сделки и отклики',
                                  'Deals and responses', ky: 'Келишимдер жана жооптор', uz: 'Bitimlar va javoblar'),
                              subtitle: tr3(
                                  '关系到你的约定，总会推送',
                                  'Әрқашан жіберіледі',
                                  'Касаются ваших договорённостей, всегда',
                                  'About your agreements, always', ky: 'Макулдашууларыңыз жөнүндө, ар дайым', uz: 'Kelishuvlaringiz haqida, har doim'),
                              trailing:
                                  const Switch(value: true, onChanged: null)),
                          SettingsRow(
                              icon: YIcons.chat,
                              title: tr3(
                                  '点赞与点评', 'Ұнату мен пікір', 'Лайки и отзывы', 'Likes and reviews', ky: 'Жактыруулар жана пикирлер', uz: 'Yoqtirishlar va sharhlar'),
                              trailing: Switch(
                                  value: on(PushCategory.community),
                                  onChanged: (v) => _save(context,
                                      toggled(PushCategory.community, v)))),
                          SettingsRow(
                              icon: Icons.notifications_active_outlined,
                              title: tr3(
                                  '新需求提醒', 'Жаңа тапсырыстар', 'Новые заявки', 'New requests', ky: 'Жаңы суроо-талаптар', uz: 'Yangi soʻrovlar'),
                              trailing: Switch(
                                  value: on(PushCategory.alerts),
                                  onChanged: (v) => _save(context,
                                      toggled(PushCategory.alerts, v)))),
                        ]),
                    SettingsGroup(children: [
                      SettingsRow(
                          icon: Icons.bedtime_outlined,
                          title: tr3('免打扰时段', 'Мазаламау', 'Не беспокоить', 'Do not disturb', ky: 'Тынчымды албаңыз', uz: 'Bezovta qilmang'),
                          value: _quietLabel(s.quietStart, s.quietEnd),
                          onTap: () async {
                            final v = await pickOne<(String, String)>(context,
                                tr3('免打扰时段', 'Мазаламау', 'Не беспокоить', 'Do not disturb', ky: 'Тынчымды албаңыз', uz: 'Bezovta qilmang'), [
                              for (final q in _quiet)
                                (q, _quietLabel(q.$1, q.$2))
                            ], selected: (
                              s.quietStart,
                              s.quietEnd
                            ));
                            if (v != null && context.mounted) {
                              await _save(
                                  context,
                                  NotificationSettings(
                                      muted: s.muted,
                                      quietStart: v.$1,
                                      quietEnd: v.$2));
                            }
                          }),
                    ]),
                    Padding(
                        padding: const EdgeInsets.all(YSpace.sm),
                        child: Text(
                            tr3(
                                '关掉的通知仍会出现在消息里，只是不推送到手机。',
                                'Өшірілгендер хабарламалар тізімінде қалады.',
                                'Отключённые уведомления остаются во входящих.',
                                'Turned-off notifications stay in your inbox.', ky: 'Өчүрүлгөн билдирмелер кирүүчү кутуңузда калат.', uz: 'Oʻchirilgan bildirishnomalar kiruvchi qutingizda qoladi.'),
                            style: YText.caption.copyWith(color: t.muted))),
                  ]);
            }));
  }
}

/// Which new demands a worker hears about.
class DemandAlertPage extends StatelessWidget {
  const DemandAlertPage({super.key});

  Future<void> _save(BuildContext context, DemandAlert a) => attempt(
      context, () => context.read(trustRepositoryProvider).saveDemandAlert(a));

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    String all(List<String> names) =>
        names.isEmpty ? tr3('不限', 'Барлығы', 'Любые', 'Any', ky: 'Каалаган', uz: 'Istalgan') : names.join(listSep);
    return Scaffold(
        appBar: AppBar(
            title: Text(tr3('新需求提醒', 'Жаңа тапсырыстар', 'Новые заявки', 'New requests', ky: 'Жаңы суроо-талаптар', uz: 'Yangi soʻrovlar'))),
        body: Live<DemandAlert>(
            provider: demandAlertProvider,
            builder: (context, a) {
              DemandAlert copy(
                      {bool? on,
                      List<String>? regions,
                      List<String>? trades,
                      List<DemandType>? types}) =>
                  DemandAlert(
                      on: on ?? a.on,
                      regions: regions ?? a.regions,
                      trades: trades ?? a.trades,
                      types: types ?? a.types);
              return ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: YSpace.gutter),
                  children: [
                    SettingsGroup(children: [
                      SettingsRow(
                          key: const Key('alert-on'),
                          icon: Icons.notifications_active_outlined,
                          title: tr3(
                              '有新需求时提醒我',
                              'Жаңа тапсырыс туралы хабарлау',
                              'Сообщать о новых заявках',
                              'Notify me about new requests', ky: 'Жаңы суроо-талаптар жөнүндө билдирүү', uz: 'Yangi soʻrovlar haqida xabar berish'),
                          trailing: Switch(
                              value: a.on,
                              onChanged: (v) => _save(context, copy(on: v)))),
                    ]),
                    SettingsGroup(
                        title: tr3('条件', 'Шарттар', 'Условия', 'Conditions', ky: 'Шарттар', uz: 'Shartlar'),
                        children: [
                          SettingsRow(
                              icon: YIcons.location,
                              title: tr3('地区', 'Аймақ', 'Регион', 'Region', ky: 'Аймак', uz: 'Hudud'),
                              value: all(
                                  [for (final r in a.regions) regionName(r)]),
                              onTap: () async {
                                final v = await pickMany<String>(
                                    context,
                                    tr3('地区', 'Аймақ', 'Регион', 'Region', ky: 'Аймак', uz: 'Hudud'),
                                    [
                                      for (final c in regionCodes)
                                        (c, regionName(c))
                                    ],
                                    a.regions);
                                if (v != null && context.mounted) {
                                  await _save(context, copy(regions: v));
                                }
                              }),
                          SettingsRow(
                              icon: YIcons.tools,
                              title: tr3('工种', 'Мамандық', 'Специальность', 'Trade', ky: 'Кесип', uz: 'Kasb'),
                              value:
                                  all([for (final c in a.trades) tradeName(c)]),
                              onTap: () async {
                                final v = await pickMany<String>(
                                    context,
                                    tr3('工种', 'Мамандық', 'Специальность', 'Trade', ky: 'Кесип', uz: 'Kasb'),
                                    [
                                      for (final c in tradeCodes)
                                        (c, tradeName(c))
                                    ],
                                    a.trades);
                                if (v != null && context.mounted) {
                                  await _save(context, copy(trades: v));
                                }
                              }),
                          SettingsRow(
                              icon: YIcons.grid,
                              title: tr3('需求类型', 'Түрі', 'Тип', 'Type', ky: 'Түрү', uz: 'Turi'),
                              value: all(
                                  [for (final x in a.types) demandTypeName(x)]),
                              onTap: () async {
                                final v = await pickMany<DemandType>(
                                    context,
                                    tr3('需求类型', 'Түрі', 'Тип', 'Type', ky: 'Түрү', uz: 'Turi'),
                                    [
                                      for (final x in DemandType.values)
                                        (x, demandTypeName(x))
                                    ],
                                    a.types);
                                if (v != null && context.mounted) {
                                  await _save(context, copy(types: v));
                                }
                              }),
                        ]),
                    Padding(
                        padding: const EdgeInsets.all(YSpace.sm),
                        child: Text(
                            tr3(
                                '需求通过审核、开始招募时提醒一次。夜间和每天的数量有限制，避免打扰。',
                                'Тапсырыс ашылғанда бір рет хабарлаймыз.',
                                'Сообщаем один раз, когда заявка открывается. Ночью и сверх дневного лимита не беспокоим.',
                                'We notify you once, when a request opens. No disturbing at night or beyond the daily limit.', ky: 'Суроо-талап ачылганда бир жолу билдиребиз. Түнкүсүн жана күндүк чектен ашык тынчыңызды албайбыз.', uz: 'Soʻrov ochilganda bir marta xabar beramiz. Tunda va kunlik cheklovdan ortiq bezovta qilmaymiz.'),
                            style: YText.caption.copyWith(color: t.muted))),
                  ]);
            }));
  }
}

String _verificationStatusText(VerificationStatus s) => switch (s) {
      VerificationStatus.pending => tr3('审核中', 'Қаралуда', 'На проверке', 'Under review', ky: 'Каралууда', uz: 'Koʻrib chiqilmoqda'),
      VerificationStatus.approved => tr3('已通过', 'Расталды', 'Подтверждено', 'Verified', ky: 'Текшерилген', uz: 'Tekshirilgan'),
      VerificationStatus.rejected => tr3('未通过', 'Өтпеді', 'Отклонено', 'Rejected', ky: 'Четке кагылды', uz: 'Rad etildi'),
    };

/// A worker asks to have a profile verified: phone and site photos.
class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key, required this.profile});
  final ServiceProfile profile;
  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  late final _phone =
      TextEditingController(text: context.session.currentAccount?.phone ?? '');
  final _note = TextEditingController();
  final _photos = <List<int>>[];
  bool _again = false;

  @override
  void dispose() {
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_phone.text.trim().length < 6 || _photos.isEmpty) {
      toast(
          context,
          tr3('请填写手机号并至少上传一张现场照片', 'Телефон мен кемі бір фото қажет',
              'Нужны телефон и хотя бы одно фото',
              'A phone number and at least one photo are needed', ky: 'Телефон номери жана жок дегенде бир сүрөт керек', uz: 'Telefon raqami va kamida bitta rasm kerak'));
      return;
    }
    final v = await attempt(
        context,
        () => context.read(trustRepositoryProvider).requestVerification(
            widget.profile.id,
            _phone.text.trim(),
            [for (final p in _photos) Uint8List.fromList(p)],
            note: _note.text.trim()),
        success: tr3('已提交，审核人员会尽快查看', 'Жіберілді', 'Отправлено', 'Sent', ky: 'Жөнөтүлдү', uz: 'Yuborildi'));
    if (v != null && mounted) setState(() => _again = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Scaffold(
        appBar: AppBar(title: Text(tr3('实名核验', 'Тексеру', 'Проверка', 'Verification', ky: 'Текшерүү', uz: 'Tekshiruv'))),
        body: Live<Verification?>(
            provider: myVerificationProvider(widget.profile.id),
            builder: (context, v) {
              final showForm = !widget.profile.verified &&
                  (v == null ||
                      v.status == VerificationStatus.rejected && _again);
              return ListView(
                  padding: const EdgeInsets.all(YSpace.gutter),
                  children: [
                    Text(
                        tr3(
                            '核验你的手机号和真实施工现场。通过后名片显示“已核验”，代表身份与现场已查看，不代表平台担保施工质量。',
                            'Телефон мен нақты нысандарыңызды тексереміз. Бұл сапаға кепілдік емес.',
                            'Проверяем телефон и реальные объекты. Это не гарантия качества работ.',
                            "We check your phone and real projects. It's not a guarantee of work quality.", ky: 'Телефонуңузду жана чыныгы долбоорлоруңузду текшеребиз. Бул иштин сапатына кепилдик эмес.', uz: 'Telefoningiz va haqiqiy loyihalaringizni tekshiramiz. Bu ish sifati kafolati emas.'),
                        style: YText.body.copyWith(color: t.muted)),
                    const SizedBox(height: YSpace.lg),
                    if (widget.profile.verified)
                      Row(children: [
                        const VerifiedBadge(size: 22),
                        const SizedBox(width: YSpace.sm),
                        Text(
                            tr3('这张名片已核验', 'Профиль расталған',
                                'Профиль проверен',
                                'Profile verified', ky: 'Профиль текшерилди', uz: 'Profil tekshirildi'),
                            style: YText.bodyStrong),
                      ])
                    else if (v != null && !showForm) ...[
                      Row(children: [
                        Text(tr3('最近一次申请', 'Соңғы өтінім', 'Последняя заявка', 'Last request', ky: 'Акыркы өтүнүч', uz: 'Oxirgi soʻrov'),
                            style: YText.bodyStrong),
                        const Spacer(),
                        StatusPill(_verificationStatusText(v.status)),
                      ]),
                      if (v.resolution.isNotEmpty) ...[
                        const SizedBox(height: YSpace.sm),
                        Hint(reasonText(v.resolution),
                            warn: v.status == VerificationStatus.rejected),
                      ],
                      if (v.status == VerificationStatus.rejected) ...[
                        const SizedBox(height: YSpace.md),
                        OutlinedButton(
                            onPressed: () => setState(() => _again = true),
                            child: Text(
                                tr3('重新申请', 'Қайта жіберу', 'Подать снова', 'Apply again', ky: 'Кайра өтүнүч берүү', uz: 'Qayta ariza berish'))),
                      ],
                    ] else ...[
                      TextField(
                          key: const Key('verify-phone'),
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                              labelText: tr3('手机号', 'Телефон', 'Телефон', 'Phone', ky: 'Телефон', uz: 'Telefon'),
                              hintText: '+7 700 000 00 00')),
                      const SizedBox(height: YSpace.md),
                      Text(
                          tr3(
                              '现场照片（干过的活，最多 6 张）',
                              'Нысан фотолары (6-ға дейін)',
                              'Фото объектов (до 6)',
                              'Project photos (up to 6)', ky: 'Долбоор сүрөттөрү (6га чейин)', uz: 'Loyiha rasmlari (6 tagacha)'),
                          style: YText.bodyStrong),
                      const SizedBox(height: YSpace.sm),
                      PhotoStrip(
                          photos: _photos,
                          onRemove: (i) => setState(() => _photos.removeAt(i))),
                      if (_photos.length < 6)
                        TextButton.icon(
                            onPressed: () async {
                              final more = await pickPhotos(context,
                                  max: 6 - _photos.length);
                              if (mounted) setState(() => _photos.addAll(more));
                            },
                            icon: const Icon(YIcons.camera),
                            label: Text(
                                tr3('添加照片', 'Фото қосу', 'Добавить фото', 'Add photos', ky: 'Сүрөт кошуу', uz: 'Rasm qoʻshish'))),
                      const SizedBox(height: YSpace.md),
                      TextField(
                          controller: _note,
                          maxLines: 3,
                          decoration: InputDecoration(
                              labelText: tr3(
                                  '补充说明（可选）',
                                  'Қосымша (міндетті емес)',
                                  'Комментарий (необязательно)',
                                  'Comment (optional)', ky: 'Комментарий (милдеттүү эмес)', uz: 'Izoh (ixtiyoriy)'))),
                      const SizedBox(height: YSpace.lg),
                      BusyButton(
                          key: const Key('verify-send'),
                          label: tr3('提交核验', 'Жіберу', 'Отправить', 'Send', ky: 'Жөнөтүү', uz: 'Yuborish'),
                          onPressed: _send),
                    ],
                  ]);
            }));
  }
}

/// Entry rows for "我的": appeals, alerts and push settings.
List<Widget> trustRows(BuildContext context, Account account) => [
      SettingsRow(
          key: const Key('me-notification-settings'),
          icon: YIcons.bell,
          title: tr3('通知设置', 'Хабарламалар', 'Уведомления', 'Notifications', ky: 'Билдирмелер', uz: 'Bildirishnomalar'),
          onTap: () =>
              pushPage<void>(context, (_) => const NotificationSettingsPage())),
      SettingsRow(
          key: const Key('me-appeals'),
          icon: Icons.gavel_outlined,
          title: tr3('我的申诉', 'Шағымдарым', 'Мои обжалования', 'My appeals', ky: 'Менин даттанууларым', uz: 'Mening apellyatsiyalarim'),
          subtitle: account.restricted
              ? tr3('账号受限中，可在这里申诉', 'Аккаунт шектелген', 'Аккаунт ограничен', 'Account restricted', ky: 'Аккаунт чектелген', uz: 'Akkaunt cheklangan')
              : null,
          onTap: () => pushPage<void>(context, (_) => const MyAppealsPage())),
    ];
