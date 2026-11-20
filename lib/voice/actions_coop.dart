import '../data/repositories.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import 'action.dart';
import 'screen.dart';

/// Implemented by the cooperation page, so voice can answer and end a
/// cooperation the way that page's buttons do.
abstract interface class CoopHost {
  /// The cooperation on the page, as last loaded.
  Cooperation get coop;
}

Cooperation? _coop() {
  final Object? screen = VoiceScreens.current;
  return screen is CoopHost ? screen.coop : null;
}

/// Offered only while [coopMoves] has [move] for the signed-in side,
/// exactly when the page shows its button.
bool Function(ActionContext) _allows(CoopMove move) => (ctx) {
      final c = _coop(), me = ctx.repos.currentAccount?.id;
      return c != null && me != null && coopMoves(c, me).contains(move);
    };

AppAction _coopAction(
        CoopMove move,
        String id,
        L3 title,
        L3 examples,
        Future<Object?> Function(
                PlatformRepositories repos, String id, Args args)
            call,
        {Map<String, Param> params = const {}}) =>
    AppAction(
      id: id,
      title: title,
      examples: examples,
      params: params,
      when: _allows(move),
      // The other side is told: voice asks first.
      risk: Risk.outbound,
      run: (ctx, args) async {
        final c = _coop()!;
        await call(ctx.repos, c.id, args);
        return ActionResult.ok(changed: [c.id]);
      },
    );

final coopActions = [
  _coopAction(
      CoopMove.confirm,
      'coop.confirm',
      const L3('确认合作', 'Келісімді растау', 'Подтвердить сотрудничество'),
      const L3('同意，确认合作', 'Келісемін, раста', 'Согласен, подтверди'),
      (repos, id, _) => repos.confirm(id)),
  _coopAction(
      CoopMove.decline,
      'coop.decline',
      const L3('拒绝邀请', 'Шақырудан бас тарту', 'Отказаться от приглашения'),
      const L3('这个活我不接了', 'Бұл жұмысты алмаймын', 'Я не возьму эту работу'),
      (repos, id, _) => repos.decline(id)),
  _coopAction(
      CoopMove.revoke,
      'coop.revoke',
      const L3('撤回邀请', 'Шақыруды қайтару', 'Отозвать приглашение'),
      const L3('把邀请撤回来', 'Шақыруды қайтар', 'Отзови приглашение'),
      (repos, id, _) => repos.revoke(id)),
  _coopAction(
      CoopMove.requestEnd,
      'coop.request_end',
      const L3('请求结束合作', 'Аяқтауды сұрау', 'Попросить завершить'),
      const L3('活干完了，请求结束', 'Жұмыс бітті, аяқтауды сұра',
          'Работа сделана, попроси завершить'),
      (repos, id, args) =>
          repos.requestEnd(id, args.has('note') ? args.text('note') : ''),
      params: const {'note': Param.text(optional: true)}),
  _coopAction(
      CoopMove.confirmEnd,
      'coop.confirm_end',
      const L3('确认结束合作', 'Аяқтауды растау', 'Подтвердить завершение'),
      const L3('同意结束', 'Аяқтауға келісемін', 'Согласен завершить'),
      (repos, id, _) => repos.confirmEnd(id)),
  _coopAction(
      CoopMove.disputeEnd,
      'coop.dispute_end',
      const L3('对结束提出异议', 'Аяқтауға қарсылық', 'Оспорить завершение'),
      const L3('还没干完，不同意结束', 'Әлі бітпеді, келіспеймін',
          'Ещё не закончено, не согласен'),
      (repos, id, args) => repos.disputeEnd(id, args.text('note')),
      params: const {'note': Param.text()}),
  _coopAction(
      CoopMove.answerChange,
      'coop.answer_change',
      const L3('答复约定变更', 'Өзгеріске жауап беру', 'Ответить на изменение'),
      const L3('接受新的约定', 'Жаңа келісімді қабылда', 'Прими новые условия'),
      (repos, id, args) => repos.answerChange(id, args.flag('accept')),
      params: const {'accept': Param.flag()}),
  _milestoneAction(
      MilestoneEvent.request,
      'coop.request_milestone',
      const L3('申请节点验收', 'Кезеңді қабылдауды сұрау', 'Попросить принять этап'),
      const L3('地基做完了，请房主来验收', 'Іргетас бітті, қабылдауды сұра',
          'Фундамент готов, попроси принять'),
      (repos, id, i, args) => repos.requestMilestone(id, i,
          note: args.has('note') ? args.text('note') : ''),
      params: const {'note': Param.text(optional: true)}),
  _milestoneAction(
      MilestoneEvent.accept,
      'coop.accept_milestone',
      const L3('验收通过', 'Кезеңді қабылдау', 'Принять этап'),
      const L3('看过了，验收通过', 'Көрдім, қабылдаймын', 'Посмотрел, принимаю'),
      (repos, id, i, _) => repos.answerMilestone(id, i, true)),
  _milestoneAction(
      MilestoneEvent.dispute,
      'coop.dispute_milestone',
      const L3('验收有问题', 'Кезеңге ескерту', 'Замечания по этапу'),
      const L3('墙不直，这个节点不通过', 'Қабырға қисық, қабылдамаймын',
          'Стена кривая, не принимаю'),
      (repos, id, i, args) =>
          repos.answerMilestone(id, i, false, note: args.text('note')),
      params: const {'note': Param.text()}),
];

/// Acts on the first milestone not yet accepted, offered only while
/// [milestoneMoves] has [event] for it, as the site section's buttons are.
AppAction _milestoneAction(
        MilestoneEvent event,
        String id,
        L3 title,
        L3 examples,
        Future<Object?> Function(
                PlatformRepositories repos, String id, int index, Args args)
            call,
        {Map<String, Param> params = const {}}) =>
    AppAction(
      id: id,
      title: title,
      examples: examples,
      params: params,
      when: (ctx) {
        final c = _coop(), me = ctx.repos.currentAccount?.id;
        final i = c == null ? null : currentMilestone(c);
        return i != null && milestoneMoves(c!, me, i).contains(event);
      },
      risk: Risk.outbound,
      run: (ctx, args) async {
        final c = _coop()!;
        final i = currentMilestone(c)!;
        await call(ctx.repos, c.id, i, args);
        return ActionResult.ok(
            changed: [c.id], say: {'milestone': c.milestones[i].key});
      },
    );
