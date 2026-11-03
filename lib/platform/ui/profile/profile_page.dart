import 'package:flutter/material.dart';
import '../../../app/settings.dart';
import '../../domain/models.dart';
import '../chat/chat_page.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile_edit_page.dart';

class _ProfileData {
  _ProfileData(this.profile, this.stats, this.owner, this.reviews);
  final ServiceProfile? profile;
  final ProfileStats? stats;
  final Account? owner;
  final List<Review> reviews;
}

/// Public page of a worker or team. Shows only facts the platform can
/// prove: verified phone, two-sided cooperations, visible reviews.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.profileId});
  final String profileId;

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    return Live<_ProfileData>(
        load: (r) async {
          final p = await r.profile(profileId);
          if (p == null) return _ProfileData(null, null, null, const []);
          return _ProfileData(p, await r.stats(p.id),
              await r.account(p.ownerId), await r.reviewsAbout(p.ownerId));
        },
        loading:
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        builder: (context, data) => data.profile == null
            ? PageScaffold(
                title: '',
                body: EmptyState(
                    icon: Icons.person_off_outlined,
                    title:
                        tr3('名片不存在或已隐藏', 'Профиль жоқ', 'Профиль недоступен')))
            : _ProfileView(data: data));
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({required this.data});
  final _ProfileData data;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final p = data.profile!;
    final s = data.stats!;
    final mine = context.repos.currentAccount?.id == p.ownerId;
    final stale = context.now.difference(p.availabilityConfirmedAt).inDays > 14;

    Future<void> contact() async {
      if (!await requireLogin(context) || !context.mounted) return;
      final conv = await attempt(
          context, () => context.repos.openConversation(p.ownerId));
      if (conv != null && context.mounted)
        await pushPage<void>(context, (_) => ChatPage(conversationId: conv.id));
    }

    Widget fact(String value, String label) => Expanded(
            child: Column(children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.muted, fontSize: 12)),
        ]));

    return PageScaffold(
        title: '',
        actions: [
          if (mine)
            IconButton(
                tooltip: tr3('编辑', 'Өзгерту', 'Редактировать'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    pushPage<void>(context, (_) => ProfileEditPage(profile: p)))
          else
            PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'report') {
                    final reason = await askText(
                        context, tr3('举报名片', 'Шағым', 'Пожаловаться'));
                    if (reason != null && context.mounted)
                      await attempt(
                          context,
                          () => context.repos
                              .report(ReportTarget.profile, p.id, reason),
                          success: tr3('已提交', 'Жіберілді', 'Отправлено'));
                  }
                  if (v == 'block' &&
                      context.mounted &&
                      await requireLogin(context) &&
                      context.mounted)
                    await attempt(context, () => context.repos.block(p.ownerId),
                        success: tr3('已拉黑', 'Бұғатталды', 'Заблокировано'));
                },
                itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'report',
                          child: Text(tr3('举报', 'Шағым', 'Пожаловаться'))),
                      PopupMenuItem(
                          value: 'block',
                          child: Text(tr3('拉黑', 'Бұғаттау', 'Заблокировать'))),
                    ]),
        ],
        bottom: mine
            ? BusyButton(
                label: tr3('确认我仍在接活', 'Әлі жұмыс аламын',
                    'Подтвердить, что беру заказы'),
                onPressed: () => attempt(
                    context, () => context.repos.confirmAvailability(p.id),
                    success: tr3('已更新确认时间', 'Жаңартылды', 'Обновлено')))
            : FilledButton.icon(
                onPressed: contact,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(tr3('联系', 'Жазу', 'Написать'))),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          YCard(
              shadow: true,
              padding: const EdgeInsets.all(22),
              child: Column(children: [
                Avatar(p.name, size: 84, team: p.kind == ProfileKind.team),
                const SizedBox(height: 12),
                Text(p.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    '${profileKindName(p.kind)} · ${p.trades.map(tradeName).join('、')}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted)),
                const Divider(height: 28),
                Row(children: [
                  fact(
                      '${s.confirmedCooperations}',
                      tr3('双方确认合作', 'Расталған келісім',
                          'Подтверждённых работ')),
                  fact('${s.reviewCount}', tr3('有效评价', 'Пікір', 'Отзывов')),
                  fact(p.experienceYears == null ? '—' : '${p.experienceYears}',
                      tr3('从业年数（自填）', 'Тәжірибе (өзі)', 'Лет опыта (со слов)')),
                ]),
              ])),
          const SizedBox(height: 18),
          if (s.phoneVerified)
            InfoRow(
                tr3('认证事实', 'Расталған', 'Проверено'),
                tr3('手机号已验证（不等于实名）', 'Телефон расталған',
                    'Телефон подтверждён (не паспорт)'),
                icon: Icons.verified_outlined),
          InfoRow(tr3('接活状态', 'Күйі', 'Статус'),
              '${availabilityName(p)} · ${tr3('确认于 ${fmtDay(p.availabilityConfirmedAt)}', '${fmtDay(p.availabilityConfirmedAt)} расталды', 'обновлено ${fmtDay(p.availabilityConfirmedAt)}')}${stale ? tr3('（较久未更新）', ' (ескі)', ' (давно)') : ''}',
              icon: Icons.event_available_outlined),
          InfoRow(tr3('服务地区', 'Аймақ', 'Районы'),
              p.regions.map(regionName).join('、'),
              icon: Icons.place_outlined),
          if (p.teamSize != null)
            InfoRow(tr3('团队人数', 'Бригада', 'Бригада'), '${p.teamSize}',
                icon: Icons.groups_outlined),
          if (p.showPhone && data.owner != null)
            InfoRow(tr3('电话', 'Телефон', 'Телефон'), data.owner!.phone,
                icon: Icons.phone_outlined),
          if (p.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.bio, style: const TextStyle(height: 1.5)),
          ],
          if (s.dimensionAverages.isNotEmpty) ...[
            SectionTitle(tr3('评价维度', 'Бағалар', 'Оценки')),
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
                    'Среднее по опубликованным отзывам.'),
                style: TextStyle(color: t.muted, fontSize: 12)),
          ],
          if (p.refPrices.isNotEmpty) ...[
            SectionTitle(tr3('参考价格', 'Бағдарлы баға', 'Ориентировочные цены')),
            for (final r in p.refPrices)
              ListTile(
                  title: Text(
                      '${money(r.amount, unit: r.unit)} ${tr3('起', 'бастап', 'от')}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(r.scope)),
            Text(
                tr3('最终以具体报价为准。', 'Нақты баға ұсыныста.',
                    'Окончательная цена — в предложении.'),
                style: TextStyle(color: t.muted, fontSize: 12)),
          ],
          if (p.works.isNotEmpty) ...[
            SectionTitle(tr3('作品', 'Жұмыстар', 'Работы')),
            for (final w in p.works)
              ListTile(
                  leading: Icon(w.source == WorkSource.platform
                      ? Icons.handshake_outlined
                      : Icons.photo_outlined),
                  title: Text(w.title),
                  subtitle: Text(w.source == WorkSource.platform
                      ? tr3('平台合作记录', 'Платформадағы келісім',
                          'Сотрудничество на платформе')
                      : tr3(
                          '自主上传${w.photoCount > 0 ? ' · ${w.photoCount} 张' : ''}',
                          'Өзі жүктеген',
                          'Загружено мастером'))),
          ],
          if (data.reviews.isNotEmpty) ...[
            SectionTitle(tr3('评价', 'Пікірлер', 'Отзывы')),
            for (final r in data.reviews)
              Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fmtDay(r.createdAt),
                            style: TextStyle(color: t.muted, fontSize: 12)),
                        if (r.text.isNotEmpty) Text(r.text),
                      ])),
          ],
        ]));
  }
}
