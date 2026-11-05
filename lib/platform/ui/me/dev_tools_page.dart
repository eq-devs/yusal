import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/mock/mock_seed.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Developer tools of the mock backend: switch demo accounts, move time
/// forward, simulate going offline and choose how review works.
class DevToolsPage extends StatelessWidget {
  const DevToolsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final mock = context.mock!;
    final t = YTokens.of(context);
    return PageScaffold(
        title: '开发者工具 · Dev',
        body: OnChange(
            builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Hint('所有平台数据都来自内存中的模拟后端，重启后恢复为种子数据。验证码固定 1234。'),
                      const SectionTitle('当前时间（模拟）'),
                      Text(
                          '${fmtDay(mock.now)} ${fmtTime(mock.now)}  (+${mock.clock.offset.inDays} 天)',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final (d, label) in [
                          (1, '+1 天'),
                          (3, '+3 天（回访）'),
                          (8, '+8 天（单方结束）'),
                          (31, '+31 天（到期）')
                        ])
                          OutlinedButton(
                              onPressed: () {
                                mock.advanceTime(Duration(days: d));
                                toast(context, '时间已快进 $d 天');
                              },
                              child: Text(label)),
                      ]),
                      const SectionTitle('网络与审核'),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('模拟断网（聊天发送和备份会失败）'),
                          value: mock.simulateOffline,
                          onChanged: (v) {
                            mock.simulateOffline = v;
                            mock.notify();
                          }),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('自动审核（关闭后需在审核后台手动处理）'),
                          value: mock.autoReviewDelay != null,
                          onChanged: (v) {
                            mock.autoReviewDelay =
                                v ? const Duration(milliseconds: 900) : null;
                            mock.notify();
                          }),
                      const SectionTitle('切换测试账号'),
                      for (final (id, label) in [
                        (SeedIds.owner, '业主 Айгерім（有两个需求）'),
                        (SeedIds.owner2, '业主 Динара（有已结束合作）'),
                        (SeedIds.mason, '瓦工 Болат（个人名片）'),
                        (SeedIds.team, '施工队 Нұрлан（团队名片，分包发布者）'),
                        (SeedIds.electrician, '电工 Ерлан'),
                        (SeedIds.roofTeam, '屋面队 Самат'),
                        (SeedIds.admin, '审核员（审核后台）'),
                        (null, '退出登录（游客浏览）'),
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
