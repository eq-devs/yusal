import 'package:flutter/widgets.dart';

import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/chat/pages/inbox.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/state/screen.dart';

/// Implemented by the app shell so navigation can switch its tabs.
abstract interface class ShellTabs {
  void goTab(int tab);
}

const _tabs = ['explore', 'houses', 'messages', 'me'];

/// Moving around the app by name.
final navActions = [
  AppAction(
    id: 'nav.tab',
    title: const L3('切换主页面', 'Негізгі бетке өту', 'Перейти на вкладку', 'Go to a tab', ky: 'Өтмөккө өтүү', uz: 'Boʻlimga oʻtish'),
    examples: const L3('打开消息', 'Хабарларды аш', 'Открой чаты', 'Open chats', ky: 'Чаттарды ач', uz: 'Chatlarni och'),
    params: const {'tab': Param.choice(_tabs)},
    risk: Risk.read,
    run: (ctx, args) async {
      final shell = VoiceScreens.mounted.whereType<ShellTabs>().firstOrNull;
      if (shell == null) {
        return const ActionResult.fail(ActionCodes.notAvailable);
      }
      Navigator.of((shell as State).context).popUntil((r) => r.isFirst);
      shell.goTab(_tabs.indexOf(args.choice('tab')));
      return const ActionResult.ok();
    },
  ),
  AppAction(
    id: 'nav.open',
    title: const L3('打开一项内容', 'Нысанды ашу', 'Открыть объект', 'Open an item', ky: 'Нерсени ачуу', uz: 'Elementni ochish'),
    examples: const L3('打开这个需求', 'Осы сұранысты аш', 'Открой эту заявку', 'Open this request', ky: 'Бул суроо-талапты ач', uz: 'Bu soʻrovni och'),
    params: {
      'kind': Param.choice([for (final t in RefType.values) t.name]),
      'ref': const Param.text(),
    },
    risk: Risk.read,
    run: (ctx, args) async {
      final page = ctx.page;
      final kind = args.choice('kind');
      final entity = ctx.find(kind, args.text('ref'));
      if (entity == null) {
        return const ActionResult.fail(ActionCodes.unknownEntity,
            say: {'param': 'ref'});
      }
      if (page == null) {
        return const ActionResult.fail(ActionCodes.notAvailable);
      }
      // Not awaited: the future completes when the opened page closes.
      openRef(page, RefType.values.byName(kind), entity.id);
      return ActionResult.ok(changed: [entity.id]);
    },
  ),
];
