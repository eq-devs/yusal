import 'package:flutter/widgets.dart' show BuildContext;

import '../app/settings.dart';
import '../platform/data/repositories.dart';

/// One piece of wording in the app's three languages.
class L3 {
  const L3(this.zh, this.kk, this.ru);
  final String zh, kk, ru;

  String of(AppLang lang) => switch (lang) {
        AppLang.zh => zh,
        AppLang.kk => kk,
        AppLang.ru => ru,
      };

  bool get complete =>
      zh.trim().isNotEmpty && kk.trim().isNotEmpty && ru.trim().isNotEmpty;
}

/// How much an action can cost the user. The executor enforces it, so
/// nothing a language model returns can get around it.
enum Risk {
  /// Changes nothing.
  read,

  /// Changes data on this device and can be undone.
  undoable,

  /// Reaches other people or the server: voice must confirm first.
  outbound,

  /// Touch only. Never runs from voice.
  manual,
}

/// Where a call came from.
enum Source { touch, voice }

enum ParamType { text, number, integer, flag, choice, entity }

/// One named argument of an action.
class Param {
  const Param.text({this.optional = false})
      : type = ParamType.text,
        values = const [],
        kind = null;
  const Param.number({this.optional = false})
      : type = ParamType.number,
        values = const [],
        kind = null;
  const Param.integer({this.optional = false})
      : type = ParamType.integer,
        values = const [],
        kind = null;
  const Param.flag({this.optional = false})
      : type = ParamType.flag,
        values = const [],
        kind = null;

  /// One of [values].
  const Param.choice(this.values, {this.optional = false})
      : type = ParamType.choice,
        kind = null;

  /// Something on screen of this [kind], named by its alias or id.
  const Param.entity(String this.kind, {this.optional = false})
      : type = ParamType.entity,
        values = const [];

  final ParamType type;
  final bool optional;
  final List<String> values;
  final String? kind;
}

/// Something the current screen shows that an action can act on. [alias]
/// is the short name given to the language model ("r1", "w3").
class Entity {
  const Entity(this.kind, this.id, {required this.alias, this.title = ''});
  final String kind, id, alias, title;
}

/// What an action may read: the backend and what is on screen.
class ActionContext {
  const ActionContext(
      {required this.repos,
      required this.loggedIn,
      this.entities = const [],
      this.page});
  final PlatformRepositories repos;
  final bool loggedIn;
  final List<Entity> entities;

  /// The page the user is on, for actions that navigate from it.
  final BuildContext? page;

  bool has(String kind) => entities.any((e) => e.kind == kind);

  /// The entity of [kind] whose alias or id is [ref].
  Entity? find(String kind, String ref) => entities
      .where((e) => e.kind == kind && (e.alias == ref || e.id == ref))
      .firstOrNull;
}

/// Arguments after the executor has checked them against the action's
/// params: every getter is safe for a declared, present param.
class Args {
  const Args(this._values);
  final Map<String, Object> _values;

  bool has(String name) => _values.containsKey(name);
  String text(String name) => _values[name]! as String;
  num number(String name) => _values[name]! as num;
  int integer(String name) => _values[name]! as int;
  bool flag(String name) => _values[name]! as bool;
  String choice(String name) => _values[name]! as String;
  Entity entity(String name) => _values[name]! as Entity;
  String id(String name) => entity(name).id;
}

/// Failure codes the executor itself returns. Actions add their own.
abstract final class ActionCodes {
  static const unknownAction = 'unknown_action';
  static const manualOnly = 'manual_only';
  static const notAvailable = 'not_available';
  static const badArgs = 'bad_args';
  static const unknownEntity = 'unknown_entity';
  static const declined = 'declined';
  static const failed = 'failed';
}

/// What an action did. [code] is null on success. [changed] lists the ids
/// to highlight; [say] is data for the reply, not finished wording.
class ActionResult {
  const ActionResult.ok({this.changed = const [], this.say = const {}})
      : code = null;
  const ActionResult.fail(String this.code, {this.say = const {}})
      : changed = const [];

  final String? code;
  final List<String> changed;
  final Map<String, Object?> say;

  bool get ok => code == null;
}

/// One thing the app can do, registered once and called by buttons, voice
/// and tests alike.
class AppAction {
  const AppAction({
    required this.id,
    required this.title,
    required this.examples,
    this.params = const {},
    this.when,
    required this.risk,
    required this.run,
  });

  /// Dotted lower-case name, also the tool name: "demand.pause".
  final String id;
  final L3 title;

  /// Something a person would say to ask for this.
  final L3 examples;
  final Map<String, Param> params;

  /// Whether the action makes sense right now. Null means always.
  final bool Function(ActionContext ctx)? when;
  final Risk risk;
  final Future<ActionResult> Function(ActionContext ctx, Args args) run;
}
