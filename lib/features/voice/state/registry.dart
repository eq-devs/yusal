import 'package:yusal/features/voice/model/action.dart';

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

  /// The actions as tool definitions for the language model: name, what
  /// it does, example sentences and a JSON schema of its arguments.
  /// Touch-only actions are left out. `docs/voice_tools.json` is this list.
  List<Map<String, Object?>> tools() => [
        for (final a in all)
          if (a.risk != Risk.manual)
            {
              'name': a.id,
              'title': {'zh': a.title.zh, 'kk': a.title.kk, 'ru': a.title.ru},
              'examples': {
                'zh': a.examples.zh,
                'kk': a.examples.kk,
                'ru': a.examples.ru
              },
              'risk': a.risk.name,
              'parameters': {
                'type': 'object',
                'properties': {
                  for (final p in a.params.entries)
                    p.key: switch (p.value.type) {
                      ParamType.text => {'type': 'string'},
                      ParamType.number => {'type': 'number'},
                      ParamType.integer => {'type': 'integer'},
                      ParamType.flag => {'type': 'boolean'},
                      ParamType.choice => {
                          'type': 'string',
                          'enum': p.value.values
                        },
                      // An alias from the context's entities.
                      ParamType.entity => {
                          'type': 'string',
                          'entity': p.value.kind
                        },
                      // Values by name from the context's fields.
                      ParamType.fields => {'type': 'object'},
                      ParamType.object => p.value.schema,
                    }
                },
                'required': [
                  for (final p in a.params.entries)
                    if (!p.value.optional) p.key
                ],
              },
            }
      ];

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
