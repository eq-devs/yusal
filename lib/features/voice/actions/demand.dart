import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/rules.dart';
import 'package:yusal/features/voice/model/action.dart';
import 'package:yusal/features/voice/state/screen.dart';

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
      const L3('提交审核', 'Тексеруге жіберу', 'Отправить на проверку', 'Send for review', ky: 'Текшерүүгө жөнөтүү', uz: 'Tekshiruvga yuborish'),
      const L3('提交审核', 'Тексеруге жібер', 'Отправь на проверку', 'Send it for review', ky: 'Текшерүүгө жөнөт', uz: 'Tekshiruvga yubor'),
      (ctx, d, _) => ctx.repos.demands.publish(d.id)),
  _demandAction(
      DemandEvent.pause,
      'demand.pause',
      const L3('暂停招募', 'Іздеуді тоқтату', 'Приостановить набор', 'Pause hiring', ky: 'Жалдоону тындыруу', uz: 'Yollashni toʻxtatish'),
      const L3('先暂停招人', 'Іздеуді уақытша тоқтат', 'Приостанови набор', 'Pause hiring', ky: 'Жалдоону тындыр', uz: 'Yollashni toʻxtat'),
      (ctx, d, _) => ctx.repos.demands.pause(d.id)),
  _demandAction(
      DemandEvent.resume,
      'demand.resume',
      const L3('继续招募', 'Іздеуді жалғастыру', 'Возобновить набор', 'Resume hiring', ky: 'Жалдоону улантуу', uz: 'Yollashni davom ettirish'),
      const L3('继续招人', 'Іздеуді жалғастыр', 'Возобнови набор', 'Resume hiring', ky: 'Жалдоону улант', uz: 'Yollashni davom ettir'),
      (ctx, d, _) => ctx.repos.demands.resume(d.id)),
  _demandAction(
      DemandEvent.renew,
      'demand.renew',
      const L3('续期 30 天', '30 күнге ұзарту', 'Продлить на 30 дней', 'Extend by 30 days', ky: '30 күнгө узартуу', uz: '30 kunga uzaytirish'),
      const L3('再延长一个月', 'Тағы бір айға ұзарт', 'Продли ещё на месяц', 'Extend it another month', ky: 'Дагы бир айга узарт', uz: 'Yana bir oyga uzaytir'),
      (ctx, d, _) => ctx.repos.demands.renew(d.id)),
  AppAction(
    id: 'demand.mark_found',
    title: const L3('标记已找到人', 'Адам табылды деп белгілеу',
        'Отметить, что исполнитель найден',
        'Mark that someone was found', ky: 'Адам табылганын белгилөө', uz: 'Odam topilganini belgilash'),
    examples: const L3('已经找到瓦工了，不再招人', 'Қалаушы табылды, енді іздемеймін',
        'Каменщика нашли, больше не ищем',
        'We found a mason, not looking any more', ky: 'Дубалчы таптык, мындан ары издебейбиз', uz: 'Gʻishtchi topdik, boshqa qidirmaymiz'),
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
      await ctx.repos.demands.markFound(id, outcome);
      return ActionResult.ok(changed: [id]);
    },
  ),
  _demandAction(
      DemandEvent.close,
      'demand.close',
      const L3('关闭需求', 'Тапсырысты жабу', 'Закрыть заявку', 'Close the request', ky: 'Суроо-талапты жабуу', uz: 'Soʻrovni yopish'),
      const L3('关掉这个需求，不需要了', 'Бұл тапсырысты жап, керек емес',
          'Закрой заявку, уже не нужно',
          "Close the request, it's not needed any more", ky: 'Суроо-талапты жап, мындан ары кереги жок', uz: 'Soʻrovni yop, endi kerak emas'),
      (ctx, d, args) => ctx.repos.demands.close(d.id, args.text('reason')),
      params: const {'reason': Param.text()}),
];
