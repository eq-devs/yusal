import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/services/api/api_failure.dart';
import 'package:yusal/services/storage/project_store.dart';
import 'package:yusal/shared/l10n/l10n.dart';
import 'package:yusal/shared/motion/motion.dart';
import 'package:yusal/shared/settings/settings.dart';
import 'package:yusal/shared/state/session.dart';
import 'package:yusal/shared/theme/theme.dart';
import 'package:yusal/shared/ui/components.dart';

export 'package:yusal/shared/state/session.dart' show ProviderContext;

extension ProjectStoreContext on BuildContext {
  /// The local design store.
  ProjectStore get projectStore => read(projectStoreProvider);
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

/// What a [Live] shows: a feature's `state/` provider, usually a
/// `FutureProvider.autoDispose.family` over its repository.
typedef LiveSource<T> = ProviderBase<AsyncValue<T>>;

/// Shows a provider's data and reloads it whenever the backend reports a
/// change: once the burst of changes settles, and only while the page is
/// on top (a covered page reloads when it is uncovered). Signing in as
/// someone else drops what is on screen at once.
class Live<T> extends ConsumerStatefulWidget {
  const Live(
      {super.key,
      required this.provider,
      required this.builder,
      this.error,
      this.refreshError,
      this.loading,
      this.refresh,
      this.fadeIn = false});

  final LiveSource<T> provider;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context, Object error)? error;
  final Widget? loading;

  /// Calling it reloads this list; the future completes with the load.
  final LiveRefresh? refresh;

  /// Cross-fade from [loading] to the content. Box layouts only.
  final bool fadeIn;

  /// Shown when a reload fails while data is on screen. Must return the
  /// same layout protocol (box or sliver) as [builder]. Null keeps the data
  /// and stays quiet: a dropped connection never wipes a page being read.
  final Widget Function(BuildContext, T, Object, VoidCallback)? refreshError;

  @override
  ConsumerState<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends ConsumerState<Live<T>> {
  Session? _session;
  String? _accountId;

  /// Signed in as someone else: show nothing until their own data is in.
  bool _blank = false;

  /// The last data shown, kept when the provider changes (a new query):
  /// the old answer stays on screen while the new one loads, and if the new
  /// one fails. Dropped when the account changes.
  T? _last;
  bool _hasLast = false;

  /// A coalesced reload is waiting for the burst of changes to settle.
  Timer? _queued;

  /// A change came while this page was covered by another route.
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
    final session = ref.read(sessionProvider);
    if (!identical(session, _session)) {
      _session?.changes.removeListener(_changed);
      _session = session;
      _accountId = session.currentAccount?.id;
      session.changes.addListener(_changed);
    } else if (shown && _stale) {
      _changed();
    }
  }

  @override
  void didUpdateWidget(covariant Live<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.refresh?._run = _userReload;
  }

  @override
  void dispose() {
    _queued?.cancel();
    _session?.changes.removeListener(_changed);
    if (widget.refresh?._run == _userReload) widget.refresh?._run = null;
    super.dispose();
  }

  /// The backend changed: reload soon, once, and only if anyone sees it.
  void _changed() {
    if (!mounted) return;
    final accountId = _session!.currentAccount?.id;
    if (accountId != _accountId) {
      // Signed in as someone else: never show the last person's data.
      _accountId = accountId;
      _queued?.cancel();
      _queued = null;
      setState(() {
        _blank = true;
        _hasLast = false;
        _last = null;
      });
      ref.invalidate(widget.provider);
      return;
    }
    if (!_visible) {
      _stale = true;
      return;
    }
    _stale = false;
    _queued ??= Timer(_settle, () {
      _queued = null;
      if (mounted) ref.invalidate(widget.provider);
    });
  }

  void _reload() => ref.invalidate(widget.provider);

  /// Pull-to-refresh: waits for the load, and says a failure out loud,
  /// since the user asked.
  Future<void> _userReload() async {
    if (!mounted) return;
    final done = Completer<Object?>();
    final sub = ref.listenManual<AsyncValue<T>>(widget.provider, (_, next) {
      if (next.isLoading || done.isCompleted) return;
      done.complete(next.hasError ? next.error : null);
    });
    ref.invalidate(widget.provider);
    final error = await done.future;
    sub.close();
    if (error != null && mounted && ref.read(widget.provider).hasValue) {
      toast(context, failureText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    var value = ref.watch(widget.provider);
    if (_blank && !value.isLoading) _blank = false;
    if (!_blank) {
      if (value.hasValue) {
        _last = value.value;
        _hasLast = true;
      } else if (_hasLast) {
        // A new query with nothing yet: keep the last answer meanwhile.
        final last = AsyncData<T>(_last as T);
        value = value.hasError
            ? AsyncError<T>(value.error!, value.stackTrace!)
                .copyWithPrevious(last)
            : last;
      }
    }
    final loaded = !_blank && (value.hasValue || value.hasError);
    final child = _build(context, value, loaded);
    if (!widget.fadeIn) return child;
    return FadeSwitcher(
        child: KeyedSubtree(
            key: ValueKey(loaded ? 'loaded' : 'loading'), child: child));
  }

  Widget _build(BuildContext context, AsyncValue<T> value, bool loaded) {
    if (!loaded || (value.isLoading && !value.hasValue && !value.hasError)) {
      return widget.loading ??
          const SkeletonList(padding: EdgeInsets.all(YSpace.xl));
    }
    if (value.hasError) {
      final error = value.error!;
      if (value.hasValue) {
        final refreshError = widget.refreshError;
        if (refreshError == null) {
          return widget.builder(context, value.requireValue);
        }
        return refreshError(context, value.requireValue, error, _reload);
      }
      return widget.error?.call(context, error) ??
          Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(failureText(error), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: _reload,
                        child: Text(tr3('重试', 'Қайталау', 'Повторить'))),
                  ])));
    }
    return widget.builder(context, value.requireValue);
  }
}

/// Rebuilds when the backend changes; for widgets that read synchronous
/// state such as the signed-in account.
class OnChange extends StatelessWidget {
  const OnChange({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: context.session.changes, builder: (c, _) => builder(c));
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
      if (await requireLogin(context) && context.mounted) {
        return attempt(context, call, success: success);
      }
      return null;
    }
    if (context.mounted) toast(context, failureText(e));
    return null;
  }
}

/// Opens the login page when signed out; true once signed in, so the
/// caller can carry on with what the user was doing.
Future<bool> requireLogin(BuildContext context) async {
  if (context.session.currentAccount != null) return true;
  final page = context.read(loginPageProvider);
  if (page == null) return false;
  final ok = await Navigator.of(context).push<bool>(platformRoute(page));
  return ok == true;
}
