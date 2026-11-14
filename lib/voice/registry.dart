import 'action.dart';

/// Every action the app offers, by id.
class ActionRegistry {
  ActionRegistry(Iterable<AppAction> actions) {
    for (final a in actions) {
      if (_byId.containsKey(a.id)) throw ArgumentError('Duplicate ${a.id}');
      _byId[a.id] = a;
    }
  }

  final _byId = <String, AppAction>{};

  AppAction? operator [](String id) => _byId[id];
  Iterable<AppAction> get all => _byId.values;

  /// The actions voice may offer in [ctx]: not touch-only, and available.
  Iterable<AppAction> offered(ActionContext ctx) =>
      all.where((a) => a.risk != Risk.manual && (a.when?.call(ctx) ?? true));

  static final _idShape = RegExp(r'^[a-z]+(\.[a-z_]+)+$');
  static final _paramShape = RegExp(r'^[a-z][a-z_]*$');

  /// What is wrong with the registered actions. Empty when all are fit to
  /// be offered to a language model; a test keeps it empty.
  List<String> problems() => [
        for (final a in all) ...[
          if (!_idShape.hasMatch(a.id)) '${a.id}: id is not dotted lower case',
          if (!a.title.complete) '${a.id}: title lacks a language',
          if (!a.examples.complete) '${a.id}: examples lack a language',
          for (final p in a.params.entries) ...[
            if (!_paramShape.hasMatch(p.key))
              '${a.id}: param ${p.key} is not lower case',
            if (p.value.type == ParamType.choice && p.value.values.isEmpty)
              '${a.id}: param ${p.key} has no choices',
          ],
        ],
      ];
}
