# Driving the design engine without the screen

The engine can be driven by anything that can write JSON: an assistant, a
script, a test. Nothing here needs a widget.

## A session

```dart
final session = EngineSession(document);

session.describe();   // sizes, grid lines, rooms, openings and stairs, with ids
session.apply('RenameRoom', {'roomId': id, 'value': 'Study'});
session.preview('MoveAxis', {'axisId': id, 'pos': 4200});   // changes nothing
session.transaction([                                       // one undo step,
  ('AddFloor', {'floorId': ground}),                        // all or nothing
  ('SetRoof', {'roof': {'type': 'hip', 'pitchDeg': 30, 'overhang': 400}}),
]);
session.check();      // what the layout rules find
session.cost();       // the estimate, by stage and in total
session.undo();
session.log;          // every command sent and what became of it
```

`EngineSession` is in `engine/core/session/engine_session.dart`. Every answer
is plain values, so `jsonEncode` takes it as it is.

A result has `ok`, a `code` and, when something was made or removed, the ids
in `created` and `removed`. The codes:

| code | meaning |
| --- | --- |
| `OK` | carried out |
| `UNKNOWN_COMMAND` | no command of that name |
| `BAD_ARGUMENT` | an argument is missing, unknown or of the wrong shape; the message names it, such as `anchor.startAxisId: expected a string` |
| `NEEDS_RESOLUTION` | the command would take something with it; send it again with one of `choices` set |
| anything else | the engine's own refusal, such as `NOT_FOUND`, `INVALID_VALUE`, `SPACING`, `OVERLAP`, `OUTSIDE`, `SPATIAL_CONFLICT`, `WALL_CONFLICT` |

## The catalogs

| what | where | as JSON |
| --- | --- | --- |
| the 77 commands and their arguments | `commands/command_catalog.dart` | `describeCommands()`, kept in `docs/engine_commands.json` |
| the 13 layout rules | `checks/rule_catalog.dart` | `ruleCatalog` |
| room types, furniture kinds and sizes, and the other kinds | `commands/object_catalog.dart` | `describeObjects()` |

Each command is described the way an assistant's tool is: a name, a summary,
whether it removes something, and a JSON Schema of its arguments. Enumerated
values are written by name (`"kind": "window"`), a wall as
`{"axisId", "startAxisId", "endAxisId"}`, grid cells as `[column, row]`.

Tests hold the catalogs to the code: a command added to the engine without a
catalog entry fails `test/command_catalog_test.dart`, and so does a rule
without one in `test/engine_session_test.dart`. After changing the catalog,
write the file again with

```
flutter test test/command_catalog_test.dart --dart-define=UPDATE_CATALOG=true
```
