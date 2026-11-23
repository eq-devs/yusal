import 'package:flutter/material.dart';
import 'package:yusal/features/chat/repository/chat_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/chat/page.dart';
import 'package:yusal/localization/l10n.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shared/ui/components.dart';
import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/ui/widgets.dart';
import 'package:yusal/features/profile/pages/edit.dart';
import 'package:yusal/features/profile/state/profile.dart';
import 'package:yusal/features/me/pages/trust.dart';

/// Public page of a worker or team. Shows only facts the platform can
/// prove: verified phone, two-sided cooperations, visible reviews.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.profileId});
  final String profileId;

  @override
  Widget build(BuildContext context) {
    watchLang(context);
    return Live<ProfileData>(
        provider: profilePageProvider(profileId),
        loading: const SkeletonPage(avatar: true),
        builder: (context, data) => data.profile == null
            ? PageScaffold(
                title: '',
                body: EmptyState(
                    icon: Icons.person_off_outlined,
                    title:
                        tr3('名片不存在或已隐藏', 'Профиль жоқ', 'Профиль недоступен', 'Profile unavailable')))
            : _ProfileView(data: data));
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.data});
  final ProfileData data;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final p = data.profile!;
    final s = data.stats!;
    final mine = context.session.currentAccount?.id == p.ownerId;
    final stale = context.now.difference(p.availabilityConfirmedAt).inDays > 14;

    Future<void> contact() async {
      if (!await requireLogin(context) || !context.mounted) return;
      final conv = await attempt(
          context,
          () =>
              context.read(chatRepositoryProvider).openConversation(p.ownerId));
      if (conv != null && context.mounted) {
        await pushPage<void>(context, (_) => ChatPage(conversationId: conv.id));
      }
    }

    Widget fact(String value, String label) => Expanded(
            child: Column(children: [
          Text(value,
              style: const TextStyle(
                  fontSize: YFont.section,
                  fontWeight: FontWeight.w800,
                  fontFeatures: YText.tabular)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: YFont.caption)),
        ]));

    return PageScaffold(
        title: '',
        actions: [
          if (mine)
            IconButton(
                tooltip: tr3('编辑', 'Өзгерту', 'Редактировать', 'Edit'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    pushPage<void>(context, (_) => ProfileEditPage(profile: p)))
          else ...[
            IconButton(
                key: const Key('profile-favourite'),
                tooltip: data.favourite
                    ? tr3('取消收藏', 'Таңдаулыдан алу', 'Убрать из избранного', 'Remove from favourites')
                    : tr3('收藏', 'Таңдаулы', 'В избранное', 'Add to favourites'),
                icon: Icon(
                    data.favourite ? Icons.favorite : Icons.favorite_border,
                    color: data.favourite ? t.accent : null),
                onPressed: () async {
                  if (!await requireLogin(context) || !context.mounted) return;
                  await attempt(
                      context,
                      () => context
                          .read(profileRepositoryProvider)
                          .toggleFavourite(p.id));
                }),
            PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'report') {
                    await reportContent(context, ReportTarget.profile, p.id);
                  }
                  if (v == 'block' &&
                      context.mounted &&
                      await requireLogin(context) &&
                      context.mounted) {
                    await attempt(
                        context,
                        () => context
                            .read(chatRepositoryProvider)
                            .block(p.ownerId),
                        success: tr3('已拉黑', 'Бұғатталды', 'Заблокировано', 'Blocked'));
                  }
                },
                itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'report',
                          child: Text(tr3('举报', 'Шағым', 'Пожаловаться', 'Report'))),
                      PopupMenuItem(
                          value: 'block',
                          child: Text(tr3('拉黑', 'Бұғаттау', 'Заблокировать', 'Block'))),
                    ]),
          ],
        ],
        bottom: mine
            ? BusyButton(
                label: tr3('确认我仍在接活', 'Әлі жұмыс аламын',
                    'Подтвердить, что беру заказы',
                    'Confirm that I take orders'),
                onPressed: () => attempt(
                    context,
                    () => context
                        .read(profileRepositoryProvider)
                        .confirmAvailability(p.id),
                    success: tr3('已更新确认时间', 'Жаңартылды', 'Обновлено', 'Updated')))
            : FilledButton.icon(
                onPressed: contact,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(tr3('联系', 'Жазу', 'Написать', 'Message'))),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          YCard(
              shadow: true,
              padding: const EdgeInsets.all(22),
              child: Column(children: [
                Avatar(p.name, size: 84, team: p.kind == ProfileKind.team),
                const SizedBox(height: 12),
                Text.rich(
                    TextSpan(text: p.name, children: [
                      if (p.verified)
                        const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: VerifiedBadge(size: 22))),
                    ]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: YFont.display, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    '${profileKindName(p.kind)} · ${p.trades.map(tradeName).join(listSep)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted)),
                const Divider(height: 28),
                Row(children: [
                  fact(
                      '${s.confirmedCooperations}',
                      // Short words only: a cell is a third of a phone.
                      tr3('双方确认合作', 'Расталған келісім', 'Работ на Yusal', 'Jobs on Yusal')),
                  fact('${s.reviewCount}', tr3('有效评价', 'Пікір', 'Отзывов', 'Reviews')),
                  fact(p.experienceYears == null ? '—' : '${p.experienceYears}',
                      tr3('从业年数（自填）', 'Тәжірибе (өзі)', 'Лет опыта (со слов)', 'Years of experience (self-reported)')),
                ]),
              ])),
          const SizedBox(height: 18),
          InfoRow(tr3('接活状态', 'Күйі', 'Статус', 'Status'),
              '${availabilityName(p)} · ${tr3('确认于 ${fmtDay(p.availabilityConfirmedAt)}', '${fmtDay(p.availabilityConfirmedAt)} расталды', 'обновлено ${fmtDay(p.availabilityConfirmedAt)}', 'updated ${fmtDay(p.availabilityConfirmedAt)}')}${stale ? tr3('（较久未更新）', ' (ескі)', ' (давно)', ' (a while ago)') : ''}',
              icon: Icons.event_available_outlined),
          InfoRow(tr3('服务地区', 'Аймақ', 'Районы', 'Districts'),
              p.regions.map(regionName).join(listSep),
              icon: Icons.place_outlined),
          if (p.teamSize != null)
            InfoRow(tr3('团队人数', 'Бригада', 'Бригада', 'Crew'), '${p.teamSize}',
                icon: Icons.groups_outlined),
          if (p.showPhone && data.owner != null)
            InfoRow(tr3('电话', 'Телефон', 'Телефон', 'Phone'), data.owner!.phone,
                icon: Icons.phone_outlined),
          if (p.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.bio, style: const TextStyle(height: 1.5)),
          ],
          if (s.dimensionAverages.isNotEmpty) ...[
            SectionTitle(tr3('评价维度', 'Бағалар', 'Оценки', 'Ratings')),
            Wrap(spacing: 16, runSpacing: 8, children: [
              for (final e in s.dimensionAverages.entries)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${dimensionName(e.key)} '),
                  Stars(e.value),
                ]),
            ]),
            const SizedBox(height: 4),
            Text(
                tr3('按双方确认结束后公开的评价计算平均分。', 'Расталған пікірлердің орташасы.',
                    'Среднее по опубликованным отзывам.',
                    'Average of published reviews.'),
                style: TextStyle(color: t.muted, fontSize: YFont.caption)),
          ],
          if (p.refPrices.isNotEmpty) ...[
            SectionTitle(tr3('参考价格', 'Бағдарлы баға', 'Ориентировочные цены', 'Indicative prices')),
            for (final r in p.refPrices)
              ListTile(
                  title: Text(
                      '${money(r.amount, unit: r.unit)} ${tr3('起', 'бастап', 'от', 'from')}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(r.scope)),
            Text(
                tr3('最终以具体报价为准。', 'Нақты баға ұсыныста.',
                    'Окончательная цена — в предложении.',
                    'The final price is in the quote.'),
                style: TextStyle(color: t.muted, fontSize: YFont.caption)),
          ],
          if (p.works.isNotEmpty) ...[
            SectionTitle(tr3('作品', 'Жұмыстар', 'Работы', 'Work')),
            for (final w in p.works)
              ListTile(
                  leading: Icon(w.source == WorkSource.platform
                      ? Icons.handshake_outlined
                      : Icons.photo_outlined),
                  title: Text(w.title),
                  subtitle: Text(w.source == WorkSource.platform
                      ? tr3('平台合作记录', 'Платформадағы келісім',
                          'Сотрудничество на платформе',
                          'Cooperations on the platform')
                      : tr3(
                          '自主上传${w.photoCount > 0 ? ' · ${w.photoCount} 张' : ''}',
                          'Өзі жүктеген',
                          'Загружено мастером',
                          'Uploaded by the pro'))),
          ],
          if (data.reviews.isNotEmpty) ...[
            SectionTitle(tr3('评价', 'Пікірлер', 'Отзывы', 'Reviews')),
            for (final r in data.reviews)
              Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fmtDay(r.createdAt),
                            style: TextStyle(
                                color: t.muted, fontSize: YFont.caption)),
                        if (r.text.isNotEmpty) Text(r.text),
                      ])),
          ],
        ]));
  }
}
