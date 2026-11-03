import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../profile/profile_edit_page.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Join as": worker, foreman / team or engineer. Each opens the service
/// profile form with sensible first choices.
class JoinPage extends StatelessWidget {
  const JoinPage({super.key});

  Future<void> start(
      BuildContext context, ProfileKind kind, List<String> trades) async {
    if (!await requireLogin(context) || !context.mounted) return;
    await Navigator.of(context).pushReplacement(
        platformRoute((_) => ProfileEditPage(kind: kind, trades: trades)));
  }

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    AppScope.watch(context);
    Widget role(IconData icon, String title, String body, VoidCallback onTap) =>
        Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Material(
                color: t.card,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(yRadius),
                    side: BorderSide(color: t.line)),
                child: InkWell(
                    borderRadius: BorderRadius.circular(yRadius),
                    onTap: onTap,
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(children: [
                          Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                  color: t.accentSoft,
                                  borderRadius: BorderRadius.circular(14)),
                              child: Icon(icon, color: t.accent, size: 28)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(title,
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(body,
                                    style:
                                        TextStyle(color: t.muted, height: 1.4)),
                              ])),
                          const Icon(Icons.chevron_right),
                        ])))));
    return PageScaffold(
        title: tr3('入驻 Yusal', 'Yusal-ға қосылу', 'Присоединиться'),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr3('你是哪一类？', 'Сіз кімсіз?', 'Кто вы?'),
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              tr3(
                  '建一张接活名片，房主在自己房子的设计里就能找到你。工程量来自图纸，报价对得上。',
                  'Профиль жасаңыз — үй иелері сізді жоба ішінен табады.',
                  'Создайте профиль — владельцы найдут вас прямо в своих проектах.'),
              style: TextStyle(color: t.muted, height: 1.5)),
          const SizedBox(height: 22),
          role(
              Icons.construction,
              tr3('工人 / 师傅', 'Шебер', 'Мастер'),
              tr3('瓦工、电工、水暖、木工……按工种接活', 'Қалаушы, электрик, сантехник…',
                  'Каменщик, электрик, сантехник…'),
              () => start(context, ProfileKind.individual, const [])),
          role(
              Icons.groups_2_outlined,
              tr3('包工头 / 施工队', 'Бригадир / бригада', 'Прораб / бригада'),
              tr3('带队承包整栋或分阶段，按图纸报价', 'Толық не кезеңмен мердігерлік',
                  'Подряд целиком или по этапам'),
              () => start(
                  context, ProfileKind.team, const ['foreman', 'general'])),
          role(
              Icons.engineering_outlined,
              tr3('工程师 / 设计师', 'Инженер / жобалаушы',
                  'Инженер / проектировщик'),
              tr3('结构、水电、房屋设计，帮房主把设计做对', 'Құрылым, инженерлік желілер, жоба',
                  'Конструкции, инженерия, проектирование'),
              () => start(context, ProfileKind.individual, const ['engineer'])),
          const SizedBox(height: 8),
          Hint(tr3('手机号默认隐藏，只有你主动分享才会显示。', 'Телефон әдепкі бойынша жасырын.',
              'Телефон по умолчанию скрыт.')),
        ]));
  }
}
