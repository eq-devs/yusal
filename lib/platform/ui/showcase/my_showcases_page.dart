import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../scope.dart';
import '../widgets.dart';
import 'share_showcase_page.dart';
import 'showcase_card.dart';
import 'showcase_detail_page.dart';

/// The designs I published to the home feed.
class MyShowcasesPage extends StatelessWidget {
  const MyShowcasesPage({super.key});
  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final me = context.repos.currentAccount;
    return PageScaffold(
        title: tr3(
            '我发布的设计', 'Жарияланған жобаларым', 'Мои опубликованные проекты'),
        bottom: BusyButton(
            label: tr3('发布一套设计', 'Жоба жариялау', 'Опубликовать проект'),
            icon: Icons.add,
            onPressed: () => shareMyDesign(context)),
        body: me == null
            ? const SizedBox.shrink()
            : Live<(List<Showcase>, Set<String>)>(
                load: (r) async =>
                    (await r.showcasesOf(me.id), await r.likedShowcases()),
                builder: (context, data) {
                  final (list, liked) = data;
                  if (list.isEmpty)
                    return EmptyState(
                        icon: Icons.photo_library_outlined,
                        title: tr3('还没有发布设计', 'Әзірге жоқ', 'Пока ничего'),
                        body: tr3(
                            '发布后大家可以点赞、评价，你还能直接为它招人',
                            'Жариялаған соң бағалайды',
                            'Другие смогут оценить проект'));
                  return Column(children: [
                    for (final s in list)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: ShowcaseCard(
                              showcase: s,
                              ownerName: me.displayName,
                              liked: liked.contains(s.id),
                              onLike: () => attempt(context,
                                  () => context.repos.toggleLike(s.id)),
                              onTap: () => pushPage<void>(
                                  context,
                                  (_) =>
                                      ShowcaseDetailPage(showcaseId: s.id)))),
                  ]);
                }));
  }
}
