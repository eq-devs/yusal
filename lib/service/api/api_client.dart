import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, Listenable;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/service/api/codec.dart';
import 'package:yusal/service/api/session_store.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The connection to the Go backend (`eq-devs/yusal-api`): requests and
/// their retries, the tokens, the signed-in account, this device's push
/// token, and a cache of accounts screens read synchronously. Nothing else
/// is served from memory.
///
/// Each feature's `Http…Repository` takes this client and calls [request]
/// and [write] on it, so they all share one session.
/// The backend (yusal-api on eqserver).
const apiBaseUrl = 'https://eqserver.tail920a63.ts.net';

/// A backend with its own clock (the in-memory test fake). Screens read the
/// time through it so tests can move time forward.
abstract interface class ClockSource {
  DateTime get now;
}

/// Fires whenever any data behind the repositories changes.
abstract interface class ChangeSource {
  Listenable get changes;
}

/// What every screen may ask of the backend session: who is signed in, and
/// when anything changed. The app's backend and the test fake both are one.
abstract interface class Session implements ChangeSource {
  Account? get currentAccount;
}

/// The app's one connection to yusal-api.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.app);

class ApiClient implements Session {
  /// The one client of the app; its session is read before the first frame.
  static final app = ApiClient(apiBaseUrl);

  ApiClient(this.baseUrl,
      {http.Client? client,
      this.timeout = const Duration(seconds: 45),
      this.session = const SessionStore()})
      : _http = client ?? http.Client();

  /// Where the tokens and the signed-in account live between launches.
  final SessionStore session;

  final _changes = ChangeNotifier();
  @override
  Listenable get changes => _changes;

  /// Accounts seen so far, by id, for screens that look a name up
  /// synchronously.
  final accounts = <String, Account>{};

  /// The signed-in account's id.
  String? currentId;

  @override
  Account? get currentAccount {
    final a = currentId == null ? null : accounts[currentId];
    return a == null || a.deleted ? null : a;
  }

  /// Tells every listening screen that something changed.
  void notify() {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _changes.notifyListeners();
  }

  /// e.g. `https://api.example.com`, no trailing slash.
  final String baseUrl;
  final http.Client _http;

  /// How long one request may take before it fails as a network error, so a
  /// server that stops answering mid-request never leaves a spinner forever.
  final Duration timeout;

  /// The refresh in flight, shared by every request that got a 401 at once.
  Future<bool>? _refreshing;

  String? accessToken;
  String? _refresh;

  /// Public account views, kept for [_accountFresh] so the many rows that
  /// name the same person (cards, comments, chats) ask the server once, not
  /// once each and again after every change.
  final _accountAt = <String, DateTime>{};
  final _accountLoads = <String, Future<Account?>>{};
  static const _accountFresh = Duration(minutes: 1);

  // ───────────────────────────── transport ─────────────────────────────

  Future<dynamic> request(String method, String path,
      {Object? body,
      List<int>? bytes,
      Map<String, String>? query,
      bool auth = true,
      Duration? limit}) async {
    final res = await sendRaw(method, path,
        body: body, bytes: bytes, query: query, auth: auth, limit: limit);
    if (res.statusCode == 401 && auth && _refresh != null) {
      if (await (_refreshing ??=
          _refreshTokens().whenComplete(() => _refreshing = null))) {
        return ApiClient.decode(await sendRaw(method, path,
            body: body, bytes: bytes, query: query, auth: auth, limit: limit));
      }
    }
    return ApiClient.decode(res);
  }

  /// GETs in flight by URL and token, so screens that ask for the same
  /// thing at once (a badge and a list, two pages in the stack) share one
  /// request instead of each sending its own.
  final _inflight = <String, Future<http.Response>>{};

  /// Waits before each retry of a read that lost its connection.
  static const _retryBackoff = [
    Duration(milliseconds: 300),
    Duration(milliseconds: 1200),
  ];

  /// [bytes] is a raw body (a recording), sent instead of a JSON [body].
  /// [limit] replaces [timeout] for a write that is known to be slow.
  Future<http.Response> sendRaw(String method, String path,
      {Object? body,
      List<int>? bytes,
      Map<String, String>? query,
      bool auth = true,
      Duration? limit}) {
    final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: query == null || query.isEmpty ? null : query);
    final token = auth ? accessToken : null;
    if (method != 'GET') {
      return _sendOnce(method, uri, token, body, limit ?? timeout,
          bytes: bytes);
    }
    final key = '$uri|$token';
    return _inflight[key] ??= _sendRead(uri, token).whenComplete(() {
      _inflight.remove(key);
    });
  }

  /// A read, tried again when the connection drops (a pooled socket the
  /// network or the phone closed while idle, a server restarting behind the
  /// proxy) so a blip never reaches the screen as "connection lost". Reads
  /// are safe to repeat; writes are sent once.
  Future<http.Response> _sendRead(Uri uri, String? token) async {
    for (var attempt = 0;; attempt++) {
      final last = attempt >= _retryBackoff.length;
      try {
        final res = await _sendOnce('GET', uri, token, null,
            last || timeout < _readTimeout ? timeout : _readTimeout);
        if (!last && _retryable(res.statusCode)) {
          await Future<void>.delayed(_retryBackoff[attempt]);
          continue;
        }
        return res;
      } on ApiFailure {
        if (last) rethrow;
        await Future<void>.delayed(_retryBackoff[attempt]);
      }
    }
  }

  /// One read attempt may take this long before it is tried again; a
  /// healthy server answers in well under a second.
  static const _readTimeout = Duration(seconds: 12);

  /// A proxy in front of a restarting server answers these.
  static bool _retryable(int status) =>
      status == 502 || status == 503 || status == 504;

  Future<http.Response> _sendOnce(
      String method, Uri uri, String? token, Object? body, Duration limit,
      {List<int>? bytes}) async {
    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (_deviceId != null) req.headers['X-Device-Id'] = _deviceId!;
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    if (bytes != null) {
      req.headers['Content-Type'] = 'application/octet-stream';
      req.bodyBytes = bytes;
    }
    try {
      return await _http
          .send(req)
          .then(http.Response.fromStream)
          .timeout(limit);
    } catch (e) {
      throw ApiFailure(ApiCodes.network, '$e');
    }
  }

  static dynamic decode(http.Response res) {
    Map<String, dynamic> env;
    try {
      env = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiFailure(ApiCodes.network, 'HTTP ${res.statusCode}');
    }
    if (env['success'] == true) return env['data'];
    throw ApiFailure(
        _mapCode(env['code'] as String? ?? ''), env['msg'] as String? ?? '');
  }

  /// Server codes are the app's [ApiCodes] where they exist.
  static String _mapCode(String code) => switch (code) {
        'UNAUTHORIZED' || 'INVALID_TOKEN' => ApiCodes.notSignedIn,
        'ACCOUNT_DISABLED' => ApiCodes.restricted,
        'VALIDATION_ERROR' || 'UNSUPPORTED_PROVIDER' => ApiCodes.invalidInput,
        'INTERNAL_ERROR' || '' => ApiCodes.network,
        _ => code,
      };

  Future<bool> _refreshTokens() async {
    final res = await sendRaw('POST', '/auth/refresh',
        body: {'refresh_token': _refresh}, auth: false);
    if (res.statusCode == 401 || res.statusCode == 403) {
      // The refresh token is expired or the account is gone: sign out.
      await forget();
      return false;
    }
    if (res.statusCode != 200) {
      // The server is down or restarting (a proxy answers 502/503): keep the
      // saved session for the next try instead of signing the user out.
      throw ApiFailure(ApiCodes.network, 'HTTP ${res.statusCode}');
    }
    takeTokens(ApiClient.decode(res) as Map<String, dynamic>);
    await saveTokens();
    return true;
  }

  void takeTokens(Map<String, dynamic> data) {
    accessToken = data['access_token'] as String?;
    _refresh = data['refresh_token'] as String?;
  }

  Future<void> saveTokens() => session.saveTokens(accessToken, _refresh);

  /// A random id for this install, sent as `X-Device-Id` so the dashboard
  /// counts active devices, guests included. Not tied to the account.
  String? _deviceId;
  static const _deviceKey = 'yusal_api.device_id';

  Future<void> _loadDeviceId() async {
    if (_deviceId != null) return;
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceKey);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceKey, _deviceId!);
    }
  }

  /// Run when the session ends, so repositories drop what they cached for
  /// the account.
  final onForget = <void Function()>[];

  Future<void> forget() async {
    for (final f in onForget) {
      f();
    }
    accessToken = null;
    _refresh = null;
    currentId = null;
    await session.clear();
    notify();
  }

  /// Reads the saved session from disk only: the tokens and the account as
  /// the server last sent it. Signed in from here on, offline included, so
  /// the first frame already shows who is signed in. Cheap; call it before
  /// the first frame, then [syncSession] in the background.
  Future<void> loadSession() async {
    await _loadDeviceId();
    if (currentId != null) return;
    final saved = await session.read();
    if (saved == null) return;
    _refresh = saved.refresh;
    accessToken = saved.access;
    if (saved.account case final account?) {
      final a = accountFrom(account);
      accounts[a.id] = a;
      currentId = a.id;
    }
  }

  /// Brings the saved session up to date with the server: refreshes the
  /// tokens and the account. A revoked session signs the user out; while
  /// the server cannot be reached the saved session stays and this tries
  /// again a few times in the background ([retryDelays]).
  Future<void> syncSession() => _sync(0);

  /// [loadSession], then [syncSession].
  Future<void> restore() async {
    await loadSession();
    await syncSession();
  }

  /// Waits between background sync attempts while the server is down.
  List<Duration> retryDelays = const [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
  ];

  Future<void> _sync(int attempt) async {
    if (_refresh == null) return;
    try {
      if (!await _refreshTokens()) return;
      setMe(await request('GET', '/client/auth/me') as Map<String, dynamic>);
      notify();
      // A late sync may come after the push setup handed over its token.
      unawaited(registerDevice());
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.network && attempt < retryDelays.length) {
        Timer(retryDelays[attempt], () => unawaited(_sync(attempt + 1)));
      }
    }
  }

  /// Registers the signed-in account with the in-memory part so mock-served
  /// features work under the real id.
  Account setMe(Map<String, dynamic> u) {
    final a = accountFrom(u);
    accounts[a.id] = a;
    currentId = a.id;
    unawaited(session.saveAccount(u));
    return a;
  }

  String? pushToken;
  String? _pushPlatform;
  String? _pushLanguage;

  /// The device's FCM token, from the push setup; registered now if signed
  /// in, else at the next sign-in. [language] is zh / kk / ru.
  Future<void> setPushToken(String token,
      {required String platform, required String language}) async {
    pushToken = token;
    _pushPlatform = platform;
    _pushLanguage = language;
    await registerDevice();
  }

  Future<void> registerDevice() async {
    final token = pushToken;
    if (token == null || currentId == null) return;
    try {
      await request('POST', '/client/devices', body: {
        'token': token,
        'platform': _pushPlatform,
        'language': _pushLanguage,
      });
    } on ApiFailure {
      // Retried at the next sign-in or token refresh.
    }
  }

  Future<Account?> account(String id) async {
    if (accounts[id] case final a? when id == currentId) return a;
    final at = _accountAt[id];
    if (at != null && DateTime.now().difference(at) < _accountFresh) {
      return accounts[id];
    }
    return _accountLoads[id] ??= _loadAccount(id).whenComplete(() {
      _accountLoads.remove(id);
    });
  }

  Future<Account?> _loadAccount(String id) async {
    try {
      final a = accountFrom(
          await request('GET', '/client/accounts/$id') as Map<String, dynamic>);
      // Keep it for mock-served screens that look accounts up by id.
      accounts[id] = a;
      _accountAt[id] = DateTime.now();
      return a;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) {
        _accountAt[id] = DateTime.now();
        return accounts[id];
      }
      rethrow;
    }
  }

  /// GET that answers null for NOT_FOUND.
  Future<Map<String, dynamic>?> maybe(String path) async {
    try {
      return await request('GET', path) as Map<String, dynamic>?;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getList(String path,
          {Map<String, String>? query}) async =>
      [
        for (final j in await request('GET', path, query: query) as List)
          j as Map<String, dynamic>
      ];

  /// A write: calls, then tells listening screens to reload.
  Future<dynamic> write(String method, String path, {Object? body}) async {
    final data = await request(method, path, body: body);
    notify();
    return data;
  }

  /// Loads accounts the screens will name, once each.
  Future<void> loadNames(Iterable<String> ids) => Future.wait([
        for (final id in ids.toSet())
          if (id.isNotEmpty && !accounts.containsKey(id))
            account(id).then((_) {}, onError: (Object _) {})
      ]);

  /// Photo bytes by `/media/` path; photos never change, so fetched once.
  final _media = <String, List<int>>{};

  Future<Cooperation> cooperationWithMedia(Map<String, dynamic> j) async {
    await Future.wait([
      for (final path in cooperationMedia(j).toSet())
        if (!_media.containsKey(path)) _loadMedia(path)
    ]);
    return cooperationFrom(j, media: _media);
  }

  Future<void> _loadMedia(String path) async {
    try {
      final res = await sendRaw('GET', path, auth: false);
      if (res.statusCode == 200) _media[path] = res.bodyBytes;
    } on ApiFailure {
      // Shown without that photo; retried on the next load.
    }
  }

  Cooperation plainCooperation(Map<String, dynamic> j) =>
      cooperationFrom(j, media: _media);
}
