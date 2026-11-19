import 'dart:async';

import 'package:flutter/material.dart';
import '../../app/settings.dart';
import '../../storage/project_store.dart';
import '../data/http/http_backend.dart';
import '../data/mock/mock_backend.dart';
import '../data/repositories.dart';
import 'l10n.dart';
import 'auth/login_page.dart';
import 'components.dart';
import 'theme.dart';
import 'widgets.dart';
import '../../motion/motion.dart';

/// Gives every platform page the repositories (mock today) and the local
/// design store.
class PlatformScope extends InheritedWidget {
  const PlatformScope(
      {super.key,
      required this.repos,
      required this.store,
      this.isDemo = false,
      required super.child});
  final PlatformRepositories repos;
  final ProjectStore store;
  final bool isDemo;

  static PlatformScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PlatformScope>();
    assert(scope != null, 'PlatformScope missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(PlatformScope old) =>
      repos != old.repos || store != old.store || isDemo != old.isDemo;
}

extension PlatformContext on BuildContext {
  PlatformRepositories get repos => PlatformScope.of(this).repos;
  ProjectStore get projectStore => PlatformScope.of(this).store;
  bool get isDemo => PlatformScope.of(this).isDemo;

  /// The mock backend, for developer tools only. Null against the real
  /// backend, even though [HttpBackend] still serves some parts in memory.
  MockBackend? get mock {
    final r = repos;
    return r is MockBackend && r is! HttpBackend ? r : null;
  }

  DateTime get now => mock?.now ?? DateTime.now();
}

/// Route that keeps the platform look.
Route<T> platformRoute<T>(WidgetBuilder builder) => MaterialPageRoute<T>(
    builder: (context) => PlatformTheme(child: Builder(builder: builder)));

Future<T?> pushPage<T>(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push<T>(platformRoute(builder));

/// Lets a pull-to-refresh reload a [Live] and wait until it has finished.
class LiveRefresh {
  Future<void> Function()? _run;
  Future<void> call() => _run?.call() ?? Future<void>.value();
}

/// Loads data and reloads it whenever the backend reports a change.
class Live<T> extends StatefulWidget {
  const Live(
      {super.key,
      required this.load,
      required this.builder,
      this.error,
      this.reloadKey,
      this.refreshError,
      this.loading,
      this.refresh,
      this.fadeIn = false});

  /// Calling it reloads this list; the future completes with the load.
  final LiveRefresh? refresh;
  final Future<T> Function(PlatformRepositories repos) load;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context, Object error)? error;
  final Widget? loading;

  /// Cross-fade from [loading] to the content. Box layouts only.
  final bool fadeIn;

  /// Stable identity of the query. Null preserves legacy rebuild loading.
  final Object? reloadKey;

  /// Must return the same layout protocol (box or sliver) as [builder].
  final Widget Function(BuildContext, T, Object, VoidCallback)? refreshError;
  @override
  State<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<Live<T>> {
  PlatformRepositories? _repos;
  T? _data;
  Object? _error;
  bool _loaded = false;
  int _generation = 0;
  String? _accountId;

  /// A load is running; a change seen meanwhile sets [_again] so one more
  /// load follows it, instead of a second one racing it.
  Future<void>? _running;
  bool _again = false;

  /// A coalesced reload is waiting for the burst of changes to settle.
  Timer? _queued;

  /// A change came while this page was covered by another route; it
  /// reloads once it is on top again instead of while hidden.
  bool _stale = false;
  bool _visible = true;

  /// One write can notify several times and several writes often come
  /// together; screens reload once after they settle.
  static const _settle = Duration(milliseconds: 60);

  @override
  void initState() {
    super.initState();
    widget.refresh?._run = _userReload;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depending on the route makes this run again when it is covered or
    // uncovered, so a page under a chat does not refetch on every message.
    final visible = (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    final shown = visible && !_visible;
    _visible = visible;
    final repos = context.repos;
    if (!identical(repos, _repos)) {
      _repos?.changes.removeListener(_changed);
      _repos = repos;
      _data = null;
      _loaded = false;
      _error = null;
      _accountId = repos.currentAccount?.id;
      repos.changes.addListener(_changed);
      _reload();
    } else if (shown && _stale) {
      _changed();
    }
  }

  @override
  void didUpdateWidget(covariant Live<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.refresh?._run = _userReload;
    if (widget.reloadKey != null && widget.reloadKey != oldWidget.reloadKey) {
      // A different query: load it now and drop the old one's answer.
      _reload();
    } else if (widget.reloadKey == null) {
      // Legacy callers rebuild with fresh closures; pick them up, but share
      // the load with any change that caused the rebuild.
      _changed();
    }
  }

  @override
  void dispose() {
    _queued?.cancel();
    _repos?.changes.removeListener(_changed);
    if (widget.refresh?._run == _userReload) widget.refresh?._run = null;
    super.dispose();
  }

  /// The backend changed: reload soon, once, and only if anyone sees it.
  void _changed() {
    if (!mounted) return;
    final accountId = _repos!.currentAccount?.id;
    if (accountId != _accountId) {
      // Signed in as someone else: never show the last person's data.
      _reload();
      return;
    }
    if (!_visible) {
      _stale = true;
      return;
    }
    _stale = false;
    if (_running != null) {
      _again = true;
      return;
    }
    _queued ??= Timer(_settle, () {
      _queued = null;
      if (mounted) _reload();
    });
  }

  /// Pull-to-refresh: a failure is said out loud, since the user asked.
  Future<void> _userReload() async {
    final error = await _reload();
    if (error != null && _data != null && mounted) {
      toast(context, failureText(error));
    }
  }

  /// Loads now, superseding any load in flight. Completes with the error,
  /// if the load failed.
  Future<Object?> _reload() async {
    if (!mounted) return null;
    _queued?.cancel();
    _queued = null;
    _stale = false;
    _again = false;
    final accountId = _repos!.currentAccount?.id;
    if (accountId != _accountId) {
      _accountId = accountId;
      setState(() {
        _data = null;
        _error = null;
        _loaded = false;
      });
    }
    final generation = ++_generation;
    final done = Completer<void>();
    _running = done.future;
    Object? failure;
    try {
      final data = await widget.load(_repos!);
      if (!mounted || generation != _generation) return null;
      setState(() {
        _data = data;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return null;
      failure = e;
      setState(() {
        // A failed refresh keeps what is on screen: a dropped connection
        // must not wipe a page the user is reading. Only a first load, or a
        // caller that draws its own banner, shows the error.
        if (_data == null || widget.refreshError != null) _error = e;
        _loaded = true;
      });
    } finally {
      if (generation == _generation) {
        _running = null;
        done.complete();
        if (_again && mounted) {
          _again = false;
          _changed();
        }
      }
    }
    return failure;
  }

  @override
  Widget build(BuildContext context) {
    final child = _build(context);
    if (!widget.fadeIn) return child;
    return FadeSwitcher(
        child: KeyedSubtree(
            key: ValueKey(_loaded ? 'loaded' : 'loading'), child: child));
  }

  Widget _build(BuildContext context) {
    if (!_loaded)
      return widget.loading ??
          const SkeletonList(padding: EdgeInsets.all(YSpace.xl));
    if (_error != null) {
      if (_data != null && widget.refreshError != null) {
        return widget.refreshError!(context, _data as T, _error!, _reload);
      }
      return widget.error?.call(context, _error!) ??
          Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(failureText(_error!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: _reload,
                        child: Text(tr3('重试', 'Қайталау', 'Повторить'))),
                  ])));
    }
    return widget.builder(context, _data as T);
  }
}

/// Rebuilds when the backend changes; for widgets that read synchronous
/// state such as the signed-in account.
class OnChange extends StatelessWidget {
  const OnChange({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: context.repos.changes, builder: (c, _) => builder(c));
}

void toast(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(text)),
      snackBarAnimationStyle: Motion.toastStyle);
}

/// Runs a backend call, showing a localized message on failure. A missing
/// sign-in opens the login page and retries once after success.
Future<T?> attempt<T>(BuildContext context, Future<T> Function() call,
    {String? success}) async {
  try {
    final result = await call();
    if (success != null && context.mounted) toast(context, success);
    return result;
  } on ApiFailure catch (e) {
    if (e.code == ApiCodes.notSignedIn && context.mounted) {
      if (await requireLogin(context) && context.mounted)
        return attempt(context, call, success: success);
      return null;
    }
    if (context.mounted) toast(context, failureText(e));
    return null;
  }
}

/// Opens the login page when signed out; true once signed in, so the
/// caller can carry on with what the user was doing.
Future<bool> requireLogin(BuildContext context) async {
  if (context.repos.currentAccount != null) return true;
  final ok = await Navigator.of(context)
      .push<bool>(platformRoute((_) => const LoginPage()));
  return ok == true;
}

/// Asks for the phone number that chats share on request; true once saved.
Future<bool> editPhone(BuildContext context) async {
  final me = context.repos.currentAccount;
  if (me == null) return false;
  final phone = await askText(
      context, tr3('手机号', 'Телефон нөмірі', 'Номер телефона'),
      hint: '+7 700 000 00 00', initial: me.phone, required: false, lines: 1);
  if (phone == null || !context.mounted) return false;
  final saved = await attempt(context, () => context.repos.updatePhone(phone),
      success: tr3('已保存', 'Сақталды', 'Сохранено'));
  return saved != null;
}
