import 'package:flutter/material.dart';
import '../../app/settings.dart';
import '../../storage/project_store.dart';
import '../data/mock/mock_backend.dart';
import '../data/repositories.dart';
import 'l10n.dart';
import 'auth/login_page.dart';
import 'theme.dart';

/// Gives every platform page the repositories (mock today) and the local
/// design store.
class PlatformScope extends InheritedWidget {
  const PlatformScope(
      {super.key,
      required this.repos,
      required this.store,
      required super.child});
  final PlatformRepositories repos;
  final ProjectStore store;

  static PlatformScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PlatformScope>();
    assert(scope != null, 'PlatformScope missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(PlatformScope old) =>
      repos != old.repos || store != old.store;
}

extension PlatformContext on BuildContext {
  PlatformRepositories get repos => PlatformScope.of(this).repos;
  ProjectStore get projectStore => PlatformScope.of(this).store;

  /// The mock backend, for developer tools only.
  MockBackend? get mock {
    final r = repos;
    return r is MockBackend ? r : null;
  }

  DateTime get now => mock?.now ?? DateTime.now();
}

/// Route that keeps the platform look.
Route<T> platformRoute<T>(WidgetBuilder builder) => MaterialPageRoute<T>(
    builder: (context) => PlatformTheme(child: Builder(builder: builder)));

Future<T?> pushPage<T>(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push<T>(platformRoute(builder));

/// Loads data and reloads it whenever the backend reports a change.
class Live<T> extends StatefulWidget {
  const Live(
      {super.key,
      required this.load,
      required this.builder,
      this.error,
      this.loading});
  final Future<T> Function(PlatformRepositories repos) load;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context, Object error)? error;
  final Widget? loading;
  @override
  State<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<Live<T>> {
  PlatformRepositories? _repos;
  T? _data;
  Object? _error;
  bool _loaded = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = context.repos;
    if (!identical(repos, _repos)) {
      _repos?.changes.removeListener(_reload);
      _repos = repos;
      repos.changes.addListener(_reload);
      _reload();
    }
  }

  @override
  void didUpdateWidget(covariant Live<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reload();
  }

  @override
  void dispose() {
    _repos?.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final data = await widget.load(_repos!);
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _error = null;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded)
      return widget.loading ??
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator()));
    if (_error != null) {
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
  m?.showSnackBar(SnackBar(content: Text(text)));
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
