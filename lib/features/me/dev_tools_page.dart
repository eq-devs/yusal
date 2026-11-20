import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/settings.dart';
import '../../data/mock/mock_seed.dart';
import '../../shared/ui/l10n.dart';
import '../../shared/ui/scope.dart';
import '../../shared/ui/theme.dart';
import '../../shared/ui/widgets.dart';

/// Developer tools of the mock backend: switch demo accounts, move time
/// forward, simulate going offline and choose how review works.
class DevToolsPage extends StatelessWidget {
  const DevToolsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final mock = context.mock!;
    final t = YTokens.of(context);
    return PageScaffold(
        title: tr3('开发者工具 · Dev', 'Әзірлеуші құралдары · Dev',
            'Инструменты разработчика · Dev'),
        body: OnChange(
            builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Hint(tr3(
                          '所有平台数据都来自内存中的模拟后端，重启后恢复为种子数据。验证码固定 1234。',
                          'Платформаның барлық дерегі жадтағы жасанды серверден алынады; қайта іске қосқанда бастапқы деректер қайтады. Растау коды әрдайым 1234.',
                          'Все данные платформы берутся из имитации сервера в памяти; после перезапуска возвращаются исходные данные. Код подтверждения всегда 1234.')),
                      SectionTitle(tr3('当前时间（模拟）', 'Қазіргі уақыт (жасанды)', 'Текущее время (имитация)')),
                      Text(
                          '${fmtDay(mock.now)} ${fmtTime(mock.now)}  ${tr3('(+${mock.clock.offset.inDays} 天)', '(+${mock.clock.offset.inDays} күн)', '(+${mock.clock.offset.inDays} дн.)')}',
                          style: const TextStyle(
                              fontSize: YFont.body, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final (d, label) in [
                          (1, tr3('+1 天', '+1 күн', '+1 дн.')),
                          (3, tr3('+3 天（回访）', '+3 күн (нәтиже сұрау)', '+3 дн. (опрос о результате)')),
                          (
                            8,
                            tr3('+8 天（单方结束）', '+8 күн (біржақты аяқтау)', '+8 дн. (одностороннее завершение)')
                          ),
                          (
                            31,
                            tr3('+31 天（到期）', '+31 күн (мерзім бітуі)', '+31 дн. (истечение срока)')
                          )
                        ])
                          OutlinedButton(
                              onPressed: () {
                                mock.advanceTime(Duration(days: d));
                                toast(
                                    context,
                                    tr3('时间已快进 $d 天', 'Уақыт алға жылжыды, күн: $d',
                                        'Время сдвинуто вперёд, дней: $d'));
                              },
                              child: Text(label)),
                      ]),
                      SectionTitle(tr3('网络与审核', 'Желі және тексеру', 'Сеть и проверка')),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr3(
                              '模拟断网（聊天发送、备份和反馈会失败）',
                              'Желі жоқ режимі (хабар жіберу, сақтық көшірме және кері байланыс орындалмайды)',
                              'Имитация отсутствия сети (отправка сообщений, резервные копии и обратная связь не работают)')),
                          value: mock.simulateOffline,
                          onChanged: (v) {
                            mock.simulateOffline = v;
                            mock.notify();
                          }),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr3(
                              '自动审核（关闭后需在审核后台手动处理）',
                              'Автоматты тексеру (өшірілсе, тапсырыстар әкімшілікте қолмен тексеріледі)',
                              'Автопроверка (если выключить, заявки проверяются вручную в админке)')),
                          value: mock.autoReviewDelay != null,
                          onChanged: (v) {
                            mock.autoReviewDelay =
                                v ? const Duration(milliseconds: 900) : null;
                            mock.notify();
                          }),
                      SectionTitle(tr3('切换测试账号', 'Сынақ аккаунтын ауыстыру', 'Сменить тестовый аккаунт')),
                      for (final (id, label) in [
                        (
                          SeedIds.owner,
                          tr3('业主 Айгерім（有两个需求）', 'Үй иесі Айгерім (екі тапсырысы бар)', 'Владелица Айгерім (две заявки)')
                        ),
                        (
                          SeedIds.owner2,
                          tr3('业主 Динара（有已结束合作）', 'Үй иесі Динара (аяқталған келісімі бар)', 'Владелица Динара (есть завершённая сделка)')
                        ),
                        (
                          SeedIds.mason,
                          tr3('瓦工 Болат（个人名片）', 'Қалаушы Болат (жеке профиль)', 'Каменщик Болат (личный профиль)')
                        ),
                        (
                          SeedIds.team,
                          tr3('施工队 Нұрлан（团队名片，分包发布者）', 'Бригада Нұрлан (бригада профилі, қосалқы мердігерлік жариялайды)', 'Бригада Нұрлан (профиль бригады, публикует субподряд)')
                        ),
                        (SeedIds.electrician, tr3('电工 Ерлан', 'Электрик Ерлан', 'Электрик Ерлан')),
                        (
                          SeedIds.roofTeam,
                          tr3('屋面队 Самат', 'Шатыр бригадасы Самат', 'Кровельная бригада Самат')
                        ),
                        (
                          SeedIds.admin,
                          tr3('审核员（审核后台）', 'Модератор (әкімшілік)', 'Модератор (админка)')
                        ),
                        (
                          null,
                          tr3('退出登录（游客浏览）', 'Шығу (қонақ ретінде қарау)', 'Выйти (просмотр без входа)')
                        ),
                      ])
                        ListTile(
                            leading: Icon(
                                mock.currentId == id
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color:
                                    mock.currentId == id ? t.accent : t.muted),
                            title: Text(label),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              mock.signInAs(id);
                            }),
                    ])));
  }
}
