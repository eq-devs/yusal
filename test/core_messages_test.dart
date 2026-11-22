import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/shared/l10n/messages.dart';
import 'package:yusal/shared/settings/settings.dart';

/// Messages the design core sends back to the editor (rejected edits and
/// layout checks) must read in Kazakh and Russian too, not fall back to the
/// Chinese the core writes them in.
void main() {
  final chinese = RegExp('[一-鿿]');
  const shown = [
    // Layout checks R11, R12, R13.
    '卫生间的门直接开向厨房，气味和卫生都不好。可以把门改到走廊或门厅一侧。',
    '厨房没有窗，白天也要开灯，做饭的油烟也散不出去。可以在外墙上加一扇窗。',
    '这扇门宽 0.60 米，偏窄，建议不小于 0.70 米。',
    '入户门宽 0.80 米，偏窄，建议不小于 0.90 米。',
    // Cutting a corner off the outline.
    '缺角长宽至少 0.60 米，并给房子留出至少 1.50 米',
    '缺角的边与已有墙线过近，请对齐或留出至少 0.30 米',
    '缺角处有楼梯，请先移动楼梯',
    '缺角处有 2 个门窗，请先移走或删除',
    '这层已经是完整的矩形',
    '这条线是缺角的边，请先恢复矩形外形',
    '房间和楼梯不能放在房屋外（缺角处）',
    // An edit the document rules refuse, e.g. a 2.0 m floor height.
    '操作无法完成：层高不得低于 2400 毫米',
    '操作无法完成：墙厚必须在 60 到 600 毫米之间',
    '操作无法完成：width 必须在 3000 到 100000 毫米之间',
    '操作无法完成：楼梯不能放在顶层',
    // Plot, utilities and schedule.
    '请填写名称',
    '还没有宅基地',
    '自带的施工阶段不能删除，可以标记为完成',
  ];
  tearDown(() => AppSettings.instance.lang = AppLang.zh);

  for (final lang in [AppLang.kk, AppLang.ru]) {
    test('core messages read in ${lang.name}', () {
      AppSettings.instance.lang = lang;
      for (final m in shown) {
        expect(coreMessage(m), isNot(contains(chinese)), reason: m);
      }
    });
  }

  test('a refused floor height names the limit in Russian', () {
    AppSettings.instance.lang = AppLang.ru;
    expect(coreMessage('操作无法完成：层高不得低于 2400 毫米'),
        'Действие не выполнено: Высота этажа не может быть меньше 2400 мм');
  });
}
