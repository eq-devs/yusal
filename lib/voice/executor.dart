import 'action.dart';
import 'registry.dart';

/// Asks the user to approve an outbound action. True means go ahead.
typedef Confirm = Future<bool> Function(AppAction action, Args args);

/// Runs actions by id. Every call, from a button or from voice, passes
/// through here, so availability, argument checks and risk rules cannot
/// be skipped.
class ActionExecutor {
  const ActionExecutor(this.registry, {required this.confirm});
  final ActionRegistry registry;
  final Confirm confirm;

  Future<ActionResult> run(
    String id,
    Map<String, Object?> rawArgs,
    ActionContext ctx, {
    required Source source,
  }) async {
    final action = registry[id];
    if (action == null) {
      return const ActionResult.fail(ActionCodes.unknownAction);
    }
    final voice = source == Source.voice;
    if (voice && action.risk == Risk.manual) {
      return const ActionResult.fail(ActionCodes.manualOnly);
    }
    if (!(action.when?.call(ctx) ?? true)) {
      return const ActionResult.fail(ActionCodes.notAvailable);
    }

    final values = <String, Object>{};
    for (final name in rawArgs.keys) {
      if (!action.params.containsKey(name)) return _bad(name);
    }
    for (final MapEntry(key: name, value: param) in action.params.entries) {
      final raw = rawArgs[name];
      if (raw == null) {
        if (param.optional) continue;
        return _bad(name);
      }
      if (param.type == ParamType.entity) {
        final entity = raw is String ? ctx.find(param.kind!, raw) : null;
        if (entity == null) {
          return ActionResult.fail(ActionCodes.unknownEntity,
              say: {'param': name});
        }
        values[name] = entity;
        continue;
      }
      final value = _checked(param, raw);
      if (value == null) return _bad(name);
      values[name] = value;
    }
    final args = Args(values);

    // A button shows its own confirmation where it needs one.
    if (voice && action.risk == Risk.outbound && !await confirm(action, args)) {
      return const ActionResult.fail(ActionCodes.declined);
    }
    try {
      return await action.run(ctx, args);
    } catch (e) {
      return ActionResult.fail(ActionCodes.failed, say: {'error': '$e'});
    }
  }

  static ActionResult _bad(String param) =>
      ActionResult.fail(ActionCodes.badArgs, say: {'param': param});

  /// [raw] as the param's type, or null when it does not fit.
  static Object? _checked(Param param, Object raw) => switch (param.type) {
        ParamType.text => raw is String ? raw : null,
        ParamType.number => raw is num && raw.isFinite ? raw : null,
        // JSON decoders may hand a whole number over as a double.
        ParamType.integer => raw is num && raw.isFinite && raw == raw.truncate()
            ? raw.toInt()
            : null,
        ParamType.flag => raw is bool ? raw : null,
        ParamType.choice =>
          raw is String && param.values.contains(raw) ? raw : null,
        ParamType.entity => null,
      };
}
