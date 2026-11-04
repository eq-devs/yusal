import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../demand/publish_page.dart';
import '../profile/profile_edit_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme.dart';
import 'explore_page.dart';

/// "＋": the four ways in. Draw from scratch, start from someone's plan,
/// find people without a drawing, or join as a pro.
Future<void> showCreateSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _CreateSheet());
  if (choice == null || !context.mounted) return;
  final nav = ShellNav.maybeOf(context);
  switch (choice) {
    case 0:
      nav?.newDesign();
    case 1:
      nav?.go(ShellTab.explore, exploreSegment: ExploreSegment.houses);
    case 2:
      if (await requireLogin(context) && context.mounted)
        await pushPage<void>(context, (_) => const PublishPage());
    case 3:
      if (await requireLogin(context) && context.mounted)
        await pushPage<void>(context, (_) => const ProfileEditPage());
  }
}

class _CreateSheet extends StatelessWidget {
  const _CreateSheet();
  @override
  Widget build(BuildContext context) {
    final options = [
      (
        Icons.architecture,
        tr3('从零画', 'Нөлден сызу', 'С нуля'),
        tr3('模板起步，输长宽就行', 'Үлгіден бастаңыз', 'Шаблон и размеры'),
      ),
      (
        Icons.collections_outlined,
        tr3('从图纸库挑一套', 'Кітапханадан таңдау', 'Из библиотеки'),
        tr3('用别人的房子改', 'Біреудің үйін өзгерту', 'Взять чужой дом за основу'),
      ),
      (
        Icons.construction,
        tr3('直接找人', 'Адам іздеу', 'Найти мастера'),
        tr3('不用图纸，填需求', 'Сызбасыз тапсырыс', 'Без чертежа'),
      ),
      (
        Icons.badge_outlined,
        tr3('入驻接活', 'Жұмыс алу', 'Стать мастером'),
        tr3('工人 / 包工头 / 工程师', 'Шебер / бригада / инженер',
            'Мастер, бригада, инженер'),
      ),
    ];
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      tr3('你想做什么？', 'Не істегіңіз келеді?',
                          'Что вы хотите сделать?'),
                      style: display(size: 22)),
                  const SizedBox(height: 14),
                  LayoutBuilder(builder: (context, c) {
                    final cols = c.maxWidth >= 560 ? 4 : 2;
                    final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      for (var i = 0; i < options.length; i++)
                        SizedBox(
                            width: w,
                            child: _OptionCard(
                                key: Key('create-option-$i'),
                                icon: options[i].$1,
                                title: options[i].$2,
                                body: options[i].$3,
                                onTap: () => Navigator.of(context).pop(i))),
                    ]);
                  }),
                ])));
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.body,
      required this.onTap});
  final IconData icon;
  final String title, body;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    return Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(yRadius),
        child: InkWell(
            borderRadius: BorderRadius.circular(yRadius),
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: t.accent, size: 28),
                      const SizedBox(height: 10),
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(body,
                          style: TextStyle(color: t.muted, fontSize: 13)),
                    ]))));
  }
}
