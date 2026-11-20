import '../domain/models.dart';
import '../domain/rules.dart';
import 'action.dart';
import 'screen.dart';

/// Implemented by the demand page, so voice can manage the demand the way
/// the owner's buttons do.
abstract interface class DemandHost {
  /// The demand on the page as last loaded, when it is the user's own;
  /// null on someone else's.
  Demand? get ownDemand;

  /// Someone was hired through the platform, so "found on Yusal,
  /// confirmed" is a true outcome.
  bool get hiredSomeone;
}

/// Failure code when "found through the platform" is claimed with nobody
/// hired on it.
const nobodyHired = 'nobody_hired';

DemandHost? _host() {
  final Object? screen = VoiceScreens.current;
  return screen is DemandHost && screen.ownDemand != null ? screen : null;
}

/// Offered only while the demand's machine allows [event], exactly when the
/// page shows the button.
bool Function(ActionContext) _allows(DemandEvent event) => (ctx) {
      final d = _host()?.ownDemand;
      return d != null && demandButton(d.status, event);
    };

/// Whether the owner's page offers [event] for a demand in [status]: what
/// the machine allows, except that an expired one is renewed, not resumed.
bool demandButton(DemandStatus status, DemandEvent event) =>
    demandMachine.can(status, event) &&
    !(event == DemandEvent.resume && status == DemandStatus.expired);

AppAction _demandAction(DemandEvent event, String id, L3 title, L3 examples,
        Future<Object?> Function(ActionContext ctx, Demand d, Args args) call,
        {Map<String, Param> params = const {}}) =>
    AppAction(
      id: id,
      title: title,
      examples: examples,
      params: params,
      when: _allows(event),
      // Workers see the change: voice asks first.
      risk: Risk.outbound,
      run: (ctx, args) async {
        final d = _host()!.ownDemand!;
        await call(ctx, d, args);
        return ActionResult.ok(changed: [d.id]);
      },
    );

final demandActions = [
  _demandAction(
      DemandEvent.publish,
      'demand.publish',
      const L3('提交审核', 'Тексеруге жіберу', 'Отправить на проверку'),
      const L3('提交审核', 'Тексеруге жібер', 'Отправь на проверку'),
      (ctx, d, _) => ctx.repos.publish(d.id)),
  _demandAction(
      DemandEvent.pause,
      'demand.pause',
      const L3('暂停招募', 'Іздеуді тоқтату', 'Приостановить набор'),
      const L3('先暂停招人', 'Іздеуді уақытша тоқтат', 'Приостанови набор'),
      (ctx, d, _) => ctx.repos.pause(d.id)),
  _demandAction(
      DemandEvent.resume,
      'demand.resume',
      const L3('继续招募', 'Іздеуді жалғастыру', 'Возобновить набор'),
      const L3('继续招人', 'Іздеуді жалғастыр', 'Возобнови набор'),
      (ctx, d, _) => ctx.repos.resume(d.id)),
  _demandAction(
      DemandEvent.renew,
      'demand.renew',
      const L3('续期 30 天', '30 күнге ұзарту', 'Продлить на 30 дней'),
      const L3('再延长一个月', 'Тағы бір айға ұзарт', 'Продли ещё на месяц'),
      (ctx, d, _) => ctx.repos.renew(d.id)),
  AppAction(
    id: 'demand.mark_found',
    title: const L3('标记已找到人', 'Адам табылды деп белгілеу',
        'Отметить, что исполнитель найден'),
    examples: const L3('已经找到瓦工了，不再招人', 'Қалаушы табылды, енді іздемеймін',
        'Каменщика нашли, больше не ищем'),
    params: {
      'outcome': Param.choice([for (final o in OutcomeKind.values) o.name])
    },
    when: _allows(DemandEvent.markFound),
    risk: Risk.outbound,
    run: (ctx, args) async {
      final host = _host()!;
      final outcome = OutcomeKind.values.byName(args.choice('outcome'));
      if (outcome == OutcomeKind.platformConfirmed && !host.hiredSomeone) {
        return const ActionResult.fail(nobodyHired);
      }
      final id = host.ownDemand!.id;
      await ctx.repos.markFound(id, outcome);
      return ActionResult.ok(changed: [id]);
    },
  ),
  _demandAction(
      DemandEvent.close,
      'demand.close',
      const L3('关闭需求', 'Тапсырысты жабу', 'Закрыть заявку'),
      const L3('关掉这个需求，不需要了', 'Бұл тапсырысты жап, керек емес',
          'Закрой заявку, уже не нужно'),
      (ctx, d, args) => ctx.repos.close(d.id, args.text('reason')),
      params: const {'reason': Param.text()}),
];
