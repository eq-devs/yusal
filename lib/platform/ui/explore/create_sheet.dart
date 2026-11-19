import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../demand/publish_page.dart';
import '../profile/profile_edit_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme.dart';
import 'explore_page.dart';
import '../../../motion/motion.dart';

/// "＋": the four ways in. Draw from scratch, start from someone's plan,
/// find people without a drawing, or join as a pro.
Future<void> showCreateSheet(BuildContext context) async {
  final choice = await showMotionSheet<int>(
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
    // Owners' three ways in, the easiest first: most people start from a
    // house someone already drew. Joining as a pro is a separate, quieter
    // link so it does not compete with them.
    final options = [
      (
        1,
        Icons.collections_outlined,
        tr3('从图纸库挑一套', 'Кітапханадан таңдау', 'Из библиотеки'),
        tr3('用别人的房子改', 'Біреудің үйін өзгерту', 'Взять чужой дом за основу'),
      ),
      (
        0,
        Icons.architecture,
        tr3('从零画', 'Нөлден сызу', 'С нуля'),
        tr3('输长宽、选屋顶就能开始', 'Өлшем мен шатырды таңдаңыз', 'Размеры и крыша'),
      ),
      (
        2,
        Icons.construction,
        tr3('直接找人', 'Адам іздеу', 'Найти мастера'),
        tr3('不用图纸，填需求', 'Сызбасыз тапсырыс', 'Без чертежа'),
      ),
    ];
    final t = YTokens.of(context);
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                    final cols = c.maxWidth >= 560 ? 3 : 1;
                    final w = (c.maxWidth - 12 * (cols - 1)) / cols;
                    final stagger = StaggerScope.of(context);
                    Widget row(int i, Widget c) =>
                        stagger ? Stagger(index: i + 1, child: c) : c;
                    return Wrap(spacing: 12, runSpacing: 10, children: [
                      for (final (i, o) in options.indexed)
                        row(i, SizedBox(
                            width: w,
                            child: _OptionCard(
                                key: Key('create-option-${o.$1}'),
                                icon: o.$2,
                                title: o.$3,
                                body: o.$4,
                                recommended: i == 0,
                                row: cols == 1,
                                onTap: () => Navigator.of(context).pop(o.$1)))),
                    ]);
                  }),
                  const SizedBox(height: 6),
                  Center(
                      child: TextButton(
                          key: const Key('create-option-3'),
                          onPressed: () => Navigator.of(context).pop(3),
                          child: Text(
                              tr3('我是工人 / 包工头 / 工程师：入驻接活',
                                  'Шеберсіз бе? Жұмыс алу',
                                  'Вы мастер? Получать заказы'),
                              style: TextStyle(color: t.muted)))),
                ])));
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.body,
      required this.onTap,
      this.recommended = false,
      this.row = false});
  final IconData icon;
  final String title, body;
  final VoidCallback onTap;
  final bool recommended;

  /// Icon beside the text (narrow screens, one card per line) instead of
  /// above it.
  final bool row;
  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: YFont.body)),
            if (recommended)
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(YRadius.pill)),
                  child: Text(tr3('推荐', 'Ұсынамыз', 'Совет'),
                      style: TextStyle(
                          color: t.accentInk,
                          fontSize: YFont.caption,
                          fontWeight: FontWeight.w700))),
          ]),
      const SizedBox(height: 2),
      Text(body, style: TextStyle(color: t.muted, fontSize: YFont.small)),
    ]);
    final icon = Icon(this.icon, color: t.accent, size: 28);
    return Pressable(
        child: Material(
        color: recommended ? t.accentSoft : t.surface,
        borderRadius: BorderRadius.circular(yRadius),
        child: InkWell(
            borderRadius: BorderRadius.circular(yRadius),
            splashFactory: NoSplash.splashFactory,
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: row
                    ? Row(children: [
                        icon,
                        const SizedBox(width: 14),
                        Expanded(child: text),
                        Icon(Icons.chevron_right, color: t.faint),
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [icon, const SizedBox(height: 10), text])))));
  }
}
