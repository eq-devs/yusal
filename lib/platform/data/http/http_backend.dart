import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models.dart';
import '../mock/mock_backend.dart';
import '../repositories.dart';
import 'codec.dart';

/// Talks to the real Go backend (`eq-devs/yusal-api`) for every repository:
/// accounts, snapshots, posts, backups, profiles, demands, quotes,
/// cooperations, reviews, chat, notifications and moderation. It extends
/// [MockBackend] only for the shared plumbing (the change notifier and the
/// account cache screens read synchronously); no data is served from it.
class HttpBackend extends MockBackend {
  HttpBackend(this.baseUrl,
      {http.Client? client,
      bool seed = false,
      this.timeout = const Duration(seconds: 45)})
      : _http = client ?? http.Client(),
        super(latency: Duration.zero, seed: seed);

  /// e.g. `https://api.example.com`, no trailing slash.
  final String baseUrl;
  final http.Client _http;

  static const _refreshKey = 'yusal_api.refresh_token';

  /// How long one request may take before it fails as a network error, so a
  /// server that stops answering mid-request never leaves a spinner forever.
  final Duration timeout;

  /// The refresh in flight, shared by every request that got a 401 at once.
  Future<bool>? _refreshing;

  String? _access;
  String? _refresh;

  /// Posts' plan thumbnails, fetched once per post.
  final _previews = <String, List<int>?>{};
  final _previewLoads = <String, Future<void>>{};

  /// Public account views, kept for [_accountFresh] so the many rows that
  /// name the same person (cards, comments, chats) ask the server once, not
  /// once each and again after every change.
  final _accountAt = <String, DateTime>{};
  final _accountLoads = <String, Future<Account?>>{};
  static const _accountFresh = Duration(minutes: 1);

  /// "Liked" as the last [post] call reported it, for the [liked] call
  /// that follows it on the house page.
  final _likedSeen = <String, bool>{};

  // ───────────────────────────── transport ─────────────────────────────

  Future<dynamic> _call(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true}) async {
    final res = await _send(method, path, body: body, query: query, auth: auth);
    if (res.statusCode == 401 && auth && _refresh != null) {
      if (await (_refreshing ??=
          _refreshTokens().whenComplete(() => _refreshing = null))) {
        return _decode(
            await _send(method, path, body: body, query: query, auth: auth));
      }
    }
    return _decode(res);
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

  Future<http.Response> _send(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true}) {
    final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: query == null || query.isEmpty ? null : query);
    final token = auth ? _access : null;
    if (method != 'GET') return _sendOnce(method, uri, token, body, timeout);
    final key = '$uri|$token';
    return _inflight[key] ??=
        _sendRead(uri, token).whenComplete(() {
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

  Future<http.Response> _sendOnce(String method, Uri uri, String? token,
      Object? body, Duration limit) async {
    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (_deviceId != null) req.headers['X-Device-Id'] = _deviceId!;
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
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

  static dynamic _decode(http.Response res) {
    Map<String, dynamic> env;
    try {
      env = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiFailure(ApiCodes.network, 'HTTP ${res.statusCode}');
    }
    if (env['success'] == true) return env['data'];
    throw ApiFailure(_mapCode(env['code'] as String? ?? ''),
        env['msg'] as String? ?? '');
  }

  /// Server codes are the app's [ApiCodes] where they exist.
  static String _mapCode(String code) => switch (code) {
        'UNAUTHORIZED' || 'INVALID_TOKEN' => ApiCodes.notSignedIn,
        'ACCOUNT_DISABLED' => ApiCodes.restricted,
        'VALIDATION_ERROR' || 'UNSUPPORTED_PROVIDER' => ApiCodes.invalidInput,
        'EMAIL_TAKEN' => ApiCodes.conflict,
        'INTERNAL_ERROR' || '' => ApiCodes.network,
        _ => code,
      };

  Future<bool> _refreshTokens() async {
    final res = await _send('POST', '/auth/refresh',
        body: {'refresh_token': _refresh}, auth: false);
    if (res.statusCode == 401 || res.statusCode == 403) {
      // The refresh token is expired or the account is gone: sign out.
      await _forget();
      return false;
    }
    if (res.statusCode != 200) {
      // The server is down or restarting (a proxy answers 502/503): keep the
      // saved session for the next try instead of signing the user out.
      throw ApiFailure(ApiCodes.network, 'HTTP ${res.statusCode}');
    }
    _takeTokens(_decode(res) as Map<String, dynamic>);
    await _save();
    return true;
  }

  void _takeTokens(Map<String, dynamic> data) {
    _access = data['access_token'] as String?;
    _refresh = data['refresh_token'] as String?;
  }

  /// The refresh token lives in the platform keystore (Keychain, Android
  /// Keystore, encrypted on the web). Where that is missing (tests, an old
  /// desktop) it falls back to plain preferences; a token found there from
  /// an older build moves to the keystore on the next save.
  static const _vault = FlutterSecureStorage();

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (_refresh == null) {
        await _vault.delete(key: _refreshKey);
      } else {
        await _vault.write(key: _refreshKey, value: _refresh!);
      }
      await prefs.remove(_refreshKey);
      return;
    } catch (_) {
      // No keystore here: keep it in preferences.
    }
    if (_refresh == null) {
      await prefs.remove(_refreshKey);
    } else {
      await prefs.setString(_refreshKey, _refresh!);
    }
  }

  Future<String?> _savedRefresh() async {
    String? token;
    try {
      token = await _vault.read(key: _refreshKey);
    } catch (_) {
      // No keystore: preferences only.
    }
    final prefs = await SharedPreferences.getInstance();
    return token ?? prefs.getString(_refreshKey);
  }

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

  Future<void> _forget() async {
    _access = null;
    _refresh = null;
    currentId = null;
    _likedSeen.clear();
    await _save();
    notify();
  }

  // ─────────────────────────────── auth ───────────────────────────────

  /// Signs back in with the refresh token saved on this device, if any.
  /// Call once at startup. A revoked session leaves the user signed out; when
  /// the server cannot be reached the saved session is kept and tried again
  /// a few times in the background ([retryDelays]), so the user is signed
  /// back in once the server answers without restarting the app.
  Future<void> restore() => _restore(0);

  /// Waits between background restore attempts while the server is down.
  List<Duration> retryDelays = const [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
  ];

  Future<void> _restore(int attempt) async {
    if (currentId != null) return;
    await _loadDeviceId();
    _refresh = await _savedRefresh();
    if (_refresh == null) return;
    try {
      if (!await _refreshTokens()) return;
      _setMe(await _call('GET', '/client/auth/me') as Map<String, dynamic>);
      notify();
      // A late restore may come after the push setup handed over its token.
      unawaited(_registerDevice());
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.network && attempt < retryDelays.length) {
        Timer(retryDelays[attempt], () => unawaited(_restore(attempt + 1)));
      }
    }
  }

  /// Google / Apple sign-in: [idToken] comes from the native SDK. [name] is
  /// a fallback display name (Apple shares it only on the first sign-in).
  Future<Account> signInWithProvider(String provider, String idToken,
      {String? name}) async {
    final data = await _call('POST', '/auth/oauth/$provider',
        body: {'id_token': idToken, if (name != null) 'name': name},
        auth: false) as Map<String, dynamic>;
    _takeTokens(data);
    await _save();
    final account = _setMe(data['user'] as Map<String, dynamic>);
    notify();
    unawaited(_registerDevice());
    return account;
  }

  /// Registers the signed-in account with the in-memory part so mock-served
  /// features work under the real id.
  Account _setMe(Map<String, dynamic> u) {
    final a = _account(u);
    accounts[a.id] = a;
    currentId = a.id;
    return a;
  }

  static Account _account(Map<String, dynamic> u) => accountFrom(u);

  @override
  Future<void> requestCode(String phone) async =>
      throw const ApiFailure(ApiCodes.invalidState, 'phone sign-in');

  @override
  Future<Account> verify(String phone, String code,
          {String? displayName}) async =>
      throw const ApiFailure(ApiCodes.invalidState, 'phone sign-in');

  @override
  Future<void> signOut() async {
    final token = _pushToken;
    if (token != null && _access != null) {
      try {
        await _call('DELETE', '/client/devices', body: {'token': token});
      } on ApiFailure {
        // Offline: the server drops the token once FCM calls it dead.
      }
    }
    await _forget();
  }

  // ─────────────────────────────── push ───────────────────────────────

  String? _pushToken, _pushPlatform, _pushLanguage;

  /// The device's FCM token, from the push setup; registered now if signed
  /// in, else at the next sign-in. [language] is zh / kk / ru.
  Future<void> setPushToken(String token,
      {required String platform, required String language}) async {
    _pushToken = token;
    _pushPlatform = platform;
    _pushLanguage = language;
    await _registerDevice();
  }

  Future<void> _registerDevice() async {
    final token = _pushToken;
    if (token == null || currentId == null) return;
    try {
      await _call('POST', '/client/devices', body: {
        'token': token,
        'platform': _pushPlatform,
        'language': _pushLanguage,
      });
    } on ApiFailure {
      // Retried at the next sign-in or token refresh.
    }
  }

  @override
  Future<Account> updateName(String name) async {
    final a = _setMe(await _call('PATCH', '/client/auth/me',
        body: {'display_name': name}) as Map<String, dynamic>);
    notify();
    return a;
  }

  @override
  Future<Account> updatePhone(String phone) async {
    final a = _setMe(await _call('PATCH', '/client/auth/me',
        body: {'phone': phone}) as Map<String, dynamic>);
    notify();
    return a;
  }

  @override
  Future<void> deleteAccount() async {
    await _call('DELETE', '/client/auth/account');
    final me = currentId;
    if (me != null) accounts.remove(me);
    await _forget();
  }

  @override
  Future<Account?> account(String id) async {
    if (accounts[id] case final a? when id == currentId) return a;
    final at = _accountAt[id];
    if (at != null && DateTime.now().difference(at) < _accountFresh) {
      return accounts[id];
    }
    return _accountLoads[id] ??=
        _loadAccount(id).whenComplete(() {
      _accountLoads.remove(id);
    });
  }

  Future<Account?> _loadAccount(String id) async {
    try {
      final a = _account(
          await _call('GET', '/client/accounts/$id') as Map<String, dynamic>);
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

  // ───────────────────────────── snapshots ─────────────────────────────

  static Map<String, dynamic> _qtyJson(QtyItem q) => {
        'name': q.name,
        'quantity': q.quantity,
        'unit': q.unit,
        'source': q.source.name,
        if (q.stage != null) 'stage': q.stage,
      };

  static QtyItem _qty(Map<String, dynamic> j) => QtyItem(
      name: j['name'] as String,
      quantity: (j['quantity'] as num?)?.toDouble(),
      unit: j['unit'] as String? ?? '',
      source: QtySource.values.byName(j['source'] as String),
      stage: j['stage'] as String?);

  static DesignSnapshot _snapshot(Map<String, dynamic> j) => DesignSnapshot(
      id: j['id'] as String,
      ownerId: j['owner_id'] as String,
      projectId: j['project_id'] as String? ?? '',
      projectName: j['project_name'] as String? ?? '',
      designUpdatedAt: j['design_updated_at'] as String,
      extractedAt: DateTime.parse(j['extracted_at'] as String),
      stages: [for (final s in j['stages'] as List? ?? const []) s as String],
      lines: [
        for (final l in j['lines'] as List? ?? const [])
          _qty(l as Map<String, dynamic>)
      ],
      summary: j['summary'] as String? ?? '',
      preview:
          j['preview'] == null ? null : base64Decode(j['preview'] as String),
      planJson: j['plan_json'] as String?);

  @override
  Future<DesignSnapshot> saveSnapshot(DesignSnapshot s) async {
    final data = await _call('POST', '/client/snapshots', body: {
      'project_id': s.projectId,
      'project_name': s.projectName,
      'design_updated_at': s.designUpdatedAt,
      'stages': s.stages,
      'lines': [for (final l in s.lines) _qtyJson(l)],
      'summary': s.summary,
      if (s.preview != null) 'preview': base64Encode(s.preview!),
      if (s.planJson != null) 'plan_json': s.planJson,
    });
    final saved = _snapshot(data as Map<String, dynamic>);
    notify();
    return saved;
  }

  @override
  Future<DesignSnapshot?> snapshot(String id,
      {String? postId, String? demandId}) async {
    if (demandId != null) {
      final j = await _maybe('/client/demands/$demandId/snapshot');
      return j == null ? null : _snapshot(j);
    }
    try {
      return _snapshot(
          await _call('GET', '/client/snapshots/$id') as Map<String, dynamic>);
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }

  // ───────────────────────────── backups ─────────────────────────────

  static BackupRecord _backup(Map<String, dynamic> j) => BackupRecord(
      projectId: j['project_id'] as String,
      name: j['name'] as String? ?? '',
      houseText: j['house_text'] as String,
      backedUpAt: DateTime.parse(j['backed_up_at'] as String),
      designUpdatedAt: j['design_updated_at'] as String);

  @override
  Future<List<BackupRecord>> backups() async => [
        for (final b in await _call('GET', '/client/backups') as List)
          _backup(b as Map<String, dynamic>)
      ];

  @override
  Future<BackupRecord?> backup(String projectId) async {
    try {
      return _backup(await _call(
              'GET', '/client/backups/${Uri.encodeComponent(projectId)}')
          as Map<String, dynamic>);
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<BackupRecord> upload(
      {required String projectId,
      required String name,
      required String houseText,
      required String designUpdatedAt,
      String? expectedPreviousUpdatedAt}) async {
    final data = await _call(
        'PUT', '/client/backups/${Uri.encodeComponent(projectId)}',
        body: {
          'name': name,
          'house_text': houseText,
          'design_updated_at': designUpdatedAt,
          if (expectedPreviousUpdatedAt != null)
            'expected_previous_updated_at': expectedPreviousUpdatedAt,
        });
    notify();
    return _backup(data as Map<String, dynamic>);
  }

  // ───────────────────────────── house posts ─────────────────────────────

  HousePost _post(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return HousePost(
        id: id,
        ownerId: j['owner_id'] as String,
        projectId: j['project_id'] as String? ?? '',
        snapshotId: j['snapshot_id'] as String,
        title: j['title'] as String,
        story: j['story'] as String? ?? '',
        region: j['region'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
        area: (j['area'] as num? ?? 0).toDouble(),
        floors: j['floors'] as int? ?? 1,
        rooms: j['rooms'] as int? ?? 0,
        estimatedCost: j['estimated_cost'] as int?,
        tags: [for (final t in j['tags'] as List? ?? const []) t as String],
        openForBuilders: j['open_for_builders'] as bool? ?? false,
        status: j['status'] == 'hidden'
            ? PostStatus.hidden
            : PostStatus.published,
        likeCount: j['like_count'] as int? ?? 0,
        commentCount: j['comment_count'] as int? ?? 0,
        ratingSum: j['rating_sum'] as int? ?? 0,
        ratingCount: j['rating_count'] as int? ?? 0,
        reuseCount: j['reuse_count'] as int? ?? 0,
        showBuild: j['show_build'] as bool? ?? false,
        focus: [for (final f in j['focus'] as List? ?? const []) f as String],
        preview: _previews[id]);
  }

  /// Maps posts and fills in their thumbnails (fetched once each). With
  /// [previews] off only thumbnails already here are filled in; the rest
  /// come through [postPreview] as their cards scroll into view.
  Future<List<HousePost>> _posts(List raw, {bool previews = true}) async {
    final list = [for (final j in raw) j as Map<String, dynamic>];
    if (previews) {
      await Future.wait([
        for (final j in list)
          if (!_previews.containsKey(j['id'])) _loadPreview(j['id'] as String)
      ]);
    }
    return [for (final j in list) _post(j)];
  }

  @override
  FutureOr<List<int>?> postPreview(String postId) {
    if (_previews.containsKey(postId)) return _previews[postId];
    return _loadPreview(postId).then((_) => _previews[postId]);
  }

  Future<void> _loadPreview(String postId) => _previewLoads[postId] ??=
      _fetchPreview(postId).whenComplete(() {
        _previewLoads.remove(postId);
      });

  Future<void> _fetchPreview(String postId) async {
    try {
      final res = await _send('GET', '/client/posts/$postId/preview');
      _previews[postId] = res.statusCode == 200 ? res.bodyBytes : null;
    } on ApiFailure {
      // Leave it uncached; the card shows without a picture.
    }
  }

  @override
  Future<List<HousePost>> feed(FeedFilter f) async {
    final data = await _call('GET', '/client/posts', query: {
      if (f.region != null) 'region': f.region!,
      'sort': f.sort.name,
      if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
      if (f.openForBuilders) 'open_for_builders': 'true',
      if (f.askingFeedback) 'asking_feedback': 'true',
      'page_size': '100',
    }) as Map<String, dynamic>;
    return _posts(data['items'] as List, previews: false);
  }

  @override
  Future<HousePost?> post(String id) async {
    try {
      final j = await _call('GET', '/client/posts/$id') as Map<String, dynamic>;
      if (currentId != null) _likedSeen[id] = j['liked'] == true;
      return (await _posts([j])).single;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<List<HousePost>> myPosts() async {
    if (currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    return _posts(await _call('GET', '/client/me/posts') as List);
  }

  @override
  Future<List<HousePost>> postsBy(String accountId) async =>
      _posts(await _call('GET', '/client/accounts/$accountId/posts') as List);

  @override
  Future<HousePost> publishPost(HousePost d) async {
    final j = await _call('POST', '/client/posts', body: {
      'snapshot_id': d.snapshotId,
      'project_id': d.projectId,
      'title': d.title,
      'story': d.story,
      'region': d.region,
      'area': d.area,
      'floors': d.floors,
      'rooms': d.rooms,
      if (d.estimatedCost != null) 'estimated_cost': d.estimatedCost,
      'tags': d.tags,
      'open_for_builders': d.openForBuilders,
      'focus': d.focus,
    }) as Map<String, dynamic>;
    notify();
    return (await _posts([j])).single;
  }

  @override
  Future<HousePost> updatePost(HousePost p) async {
    final j = await _call('PATCH', '/client/posts/${p.id}', body: {
      'title': p.title,
      'story': p.story,
      'region': p.region,
      'tags': p.tags,
      'open_for_builders': p.openForBuilders,
      'show_build': p.showBuild,
      'focus': p.focus,
    }) as Map<String, dynamic>;
    notify();
    return (await _posts([j])).single;
  }

  @override
  Future<void> hidePost(String id) async {
    await _call('POST', '/client/posts/$id/hide');
    notify();
  }

  @override
  Future<String?> reusePost(String postId) async {
    final data =
        await _call('POST', '/client/posts/$postId/reuse') as Map<String, dynamic>;
    notify();
    return data['plan_json'] as String?;
  }

  @override
  Future<bool> toggleLike(String postId) async {
    final data =
        await _call('POST', '/client/posts/$postId/like') as Map<String, dynamic>;
    _likedSeen.remove(postId);
    notify();
    return data['liked'] as bool;
  }

  @override
  Future<bool> liked(String postId) async {
    if (currentId == null) return false;
    if (_likedSeen.remove(postId) case final seen?) return seen;
    final j = await _call('GET', '/client/posts/$postId') as Map<String, dynamic>;
    return j['liked'] == true;
  }

  @override
  Future<List<String>> likedPosts() async {
    if (currentId == null) return const [];
    return [
      for (final id in await _call('GET', '/client/me/liked-posts') as List)
        id as String
    ];
  }

  static PostComment _comment(Map<String, dynamic> j) => PostComment(
      id: j['id'] as String,
      postId: j['post_id'] as String,
      authorId: j['author_id'] as String,
      text: j['text'] as String? ?? '',
      createdAt: DateTime.parse(j['created_at'] as String),
      rating: j['rating'] as int?,
      topic: j['topic'] as String?,
      parentId: j['parent_id'] as String?,
      helpful: j['helpful'] as bool? ?? false);

  @override
  Future<List<PostComment>> comments(String postId) async {
    try {
      final list = [
        for (final c in await _call('GET', '/client/posts/$postId/comments')
            as List)
          _comment(c as Map<String, dynamic>)
      ];
      // Screens show author names through account(id); load them once.
      await Future.wait([
        for (final id in {for (final c in list) c.authorId})
          if (!accounts.containsKey(id)) account(id)
      ]);
      return list;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return const [];
      rethrow;
    }
  }

  @override
  Future<PostComment> comment(String postId, String text,
      {int? rating, String? topic, String? parentId}) async {
    final c = _comment(await _call('POST', '/client/posts/$postId/comments',
        body: {
          'text': text,
          if (rating != null) 'rating': rating,
          if (topic != null) 'topic': topic,
          if (parentId != null) 'parent_id': parentId,
        }) as Map<String, dynamic>);
    notify();
    return c;
  }

  @override
  Future<void> deleteComment(String id) async {
    await _call('DELETE', '/client/comments/$id');
    notify();
  }

  @override
  Future<PostComment> markHelpful(String commentId, bool helpful) async {
    final c = _comment(await _call('POST', '/client/comments/$commentId/helpful',
        body: {'helpful': helpful}) as Map<String, dynamic>);
    notify();
    return c;
  }

  // ───────────────────────────── helpers ─────────────────────────────

  /// GET that answers null for NOT_FOUND.
  Future<Map<String, dynamic>?> _maybe(String path) async {
    try {
      return await _call('GET', path) as Map<String, dynamic>?;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _list(String path,
          {Map<String, String>? query}) async =>
      [for (final j in await _call('GET', path, query: query) as List) j as Map<String, dynamic>];

  /// A write: calls, then tells listening screens to reload.
  Future<dynamic> _write(String method, String path, {Object? body}) async {
    final data = await _call(method, path, body: body);
    notify();
    return data;
  }

  /// Loads accounts the screens will name, once each.
  Future<void> _names(Iterable<String> ids) => Future.wait([
        for (final id in ids.toSet())
          if (id.isNotEmpty && !accounts.containsKey(id))
            account(id).then((_) {}, onError: (Object _) {})
      ]);

  Future<ServiceProfile> _profile(Future<dynamic> f) async =>
      profileFrom(await f as Map<String, dynamic>);
  Future<Demand> _demand(Future<dynamic> f) async =>
      demandFrom(await f as Map<String, dynamic>);
  Future<Application> _app(Future<dynamic> f) async =>
      applicationFrom(await f as Map<String, dynamic>);
  Future<Cooperation> _coop(Future<dynamic> f) async =>
      _coopFrom(await f as Map<String, dynamic>);

  /// Photo bytes by `/media/` path; photos never change, so fetched once.
  final _media = <String, List<int>>{};

  Future<Cooperation> _coopFrom(Map<String, dynamic> j) async {
    await Future.wait([
      for (final path in cooperationMedia(j).toSet())
        if (!_media.containsKey(path)) _loadMedia(path)
    ]);
    return cooperationFrom(j, media: _media);
  }

  Future<void> _loadMedia(String path) async {
    try {
      final res = await _send('GET', path, auth: false);
      if (res.statusCode == 200) _media[path] = res.bodyBytes;
    } on ApiFailure {
      // Shown without that photo; retried on the next load.
    }
  }

  // ───────────────────────────── profiles ─────────────────────────────

  @override
  Future<List<ServiceProfile>> myProfiles() async {
    if (currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    return [for (final j in await _list('/client/me/profiles')) profileFrom(j)];
  }

  @override
  Future<ServiceProfile?> profile(String id) async {
    final j = await _maybe('/client/profiles/$id');
    if (j == null) return null;
    final p = profileFrom(j);
    await _names([p.ownerId]);
    return p;
  }

  @override
  Future<List<ServiceProfile>> profilesOf(String accountId) async => [
        for (final j in await _list('/client/accounts/$accountId/profiles'))
          profileFrom(j)
      ];

  @override
  Future<List<ServiceProfile>> searchProfiles(ProfileFilter f) async {
    final list = [
      for (final j in await _list('/client/profiles', query: {
        if (f.kind != null) 'kind': f.kind!.name,
        if (f.trade != null) 'trade': f.trade!,
        if (f.region != null) 'region': f.region!,
        if (f.availableNow) 'available_now': 'true',
        if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
      }))
        profileFrom(j)
    ];
    await _names(list.map((p) => p.ownerId));
    return list;
  }

  @override
  Future<ServiceProfile> saveProfile(ServiceProfile p) =>
      _profile(_write('POST', '/client/profiles', body: profileJson(p)));

  @override
  Future<ServiceProfile> confirmAvailability(String profileId) => _profile(
      _write('POST', '/client/profiles/$profileId/confirm-availability'));

  @override
  Future<ProfileStats> stats(String profileId) async => statsFrom(
      await _call('GET', '/client/profiles/$profileId/stats')
          as Map<String, dynamic>);

  @override
  Future<Set<String>> favourites() async {
    if (currentId == null) return {};
    return {
      for (final id in await _call('GET', '/client/me/favourites') as List)
        id as String
    };
  }

  @override
  Future<void> toggleFavourite(String id) async {
    await _write('POST', '/client/favourites/$id/toggle');
  }

  // ───────────────────────────── demands ─────────────────────────────

  @override
  Future<List<Demand>> searchDemands(DemandFilter f) async {
    final list = [
      for (final j in await _list('/client/demands', query: {
        if (f.type != null) 'type': f.type!.name,
        if (f.trade != null) 'trade': f.trade!,
        if (f.region != null) 'region': f.region!,
        if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
        if (f.includeInactive) 'include_inactive': 'true',
      }))
        demandFrom(j)
    ];
    await _names(list.map((d) => d.ownerId));
    return list;
  }

  @override
  Future<Demand?> demand(String id) async {
    final j = await _maybe('/client/demands/$id');
    if (j == null) return null;
    final d = demandFrom(j);
    await _names([d.ownerId]);
    return d;
  }

  @override
  Future<List<Demand>> myDemands() async =>
      [for (final j in await _list('/client/me/demands')) demandFrom(j)];

  @override
  Future<Demand> saveDraft(DemandType type, DemandVersion draft,
          {PublisherRole role = PublisherRole.owner,
          String? existingId,
          String? designProjectId}) =>
      _demand(_write('POST', '/client/demands', body: {
        'type': type.name,
        'version': versionJson(draft),
        'publisher_role': role.name,
        if (existingId != null) 'existing_id': existingId,
        if (designProjectId != null) 'design_project_id': designProjectId,
      }));

  @override
  Future<Demand> publish(String demandId) =>
      _demand(_write('POST', '/client/demands/$demandId/publish'));

  @override
  Future<Demand> revise(String demandId, DemandVersion next) => _demand(_write(
      'POST', '/client/demands/$demandId/revise',
      body: {'version': versionJson(next)}));

  @override
  Future<Demand> pause(String demandId) =>
      _demand(_write('POST', '/client/demands/$demandId/pause'));

  @override
  Future<Demand> resume(String demandId) =>
      _demand(_write('POST', '/client/demands/$demandId/resume'));

  @override
  Future<Demand> renew(String demandId) =>
      _demand(_write('POST', '/client/demands/$demandId/renew'));

  @override
  Future<Demand> markFound(String demandId, OutcomeKind outcome) => _demand(
      _write('POST', '/client/demands/$demandId/found',
          body: {'outcome': outcome.name}));

  @override
  Future<Demand> close(String demandId, String reason) => _demand(_write(
      'POST', '/client/demands/$demandId/close',
      body: {'reason': reason}));

  @override
  Future<Demand> recordOutcome(String demandId, OutcomeKind outcome) =>
      _demand(_write('POST', '/client/demands/$demandId/outcome',
          body: {'outcome': outcome.name}));

  @override
  Future<Demand> setShareRevoked(String demandId, bool revoked) => _demand(
      _write('POST', '/client/demands/$demandId/share',
          body: {'revoked': revoked}));

  @override
  Future<PublicDemandView?> publicView(String shareToken) async {
    final token = Uri.encodeComponent(shareToken);
    final j = await _maybe('/client/share/$token');
    if (j == null) return null;
    DesignSnapshot? snap;
    if (j['available'] == true && j['snapshot_id'] != null) {
      final s = await _maybe('/client/share/$token/snapshot');
      if (s != null) snap = _snapshot(s);
    }
    return publicViewFrom(j, snap);
  }

  // ─────────────────────────── applications ───────────────────────────

  @override
  Future<Map<String, ({int total, int unread})>> myQuoteCounts() async {
    final m = await _call('GET', '/client/me/quote-counts') as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        e.key: (
          total: ((e.value as Map)['total'] as num).toInt(),
          unread: ((e.value as Map)['unread'] as num).toInt()
        )
    };
  }

  @override
  Future<List<Application>> applicationsFor(String demandId) async {
    final list = [
      for (final j in await _list('/client/demands/$demandId/applications'))
        applicationFrom(j)
    ];
    await _names(list.map((a) => a.applicantId));
    return list;
  }

  @override
  Future<List<Application>> myApplications() async => [
        for (final j in await _list('/client/me/applications'))
          applicationFrom(j)
      ];

  @override
  Future<Application?> application(String id) async {
    if (currentId == null) return null;
    final j = await _maybe('/client/applications/$id');
    return j == null ? null : applicationFrom(j);
  }

  @override
  Future<Application> submit(
          {required String demandId,
          required String profileId,
          required ApplicationVersion version,
          required String requestId}) =>
      _app(_write('POST', '/client/applications', body: {
        'demand_id': demandId,
        'profile_id': profileId,
        'version': appVersionJson(version),
        'request_id': requestId,
      }));

  @override
  Future<Application> withdraw(String applicationId) =>
      _app(_write('POST', '/client/applications/$applicationId/withdraw'));

  @override
  Future<Application> markNotSelected(String applicationId) =>
      _app(_write('POST', '/client/applications/$applicationId/not-selected'));

  // ─────────────────────────── cooperations ───────────────────────────

  String _c(String id) => '/client/cooperations/$id';

  @override
  Future<Cooperation> invite(String applicationId, Agreement terms) => _coop(
      _write('POST', '/client/applications/$applicationId/invite',
          body: agreementJson(terms)));

  @override
  Future<Cooperation> confirm(String id) =>
      _coop(_write('POST', '${_c(id)}/confirm'));

  @override
  Future<Cooperation> decline(String id) =>
      _coop(_write('POST', '${_c(id)}/decline'));

  @override
  Future<Cooperation> revoke(String id) =>
      _coop(_write('POST', '${_c(id)}/revoke'));

  @override
  Future<Cooperation> proposeChange(String id, Agreement terms) =>
      _coop(_write('POST', '${_c(id)}/change', body: agreementJson(terms)));

  @override
  Future<Cooperation> answerChange(String id, bool accept) => _coop(
      _write('POST', '${_c(id)}/change/answer', body: {'accept': accept}));

  @override
  Future<Cooperation> requestEnd(String id, String note) =>
      _coop(_write('POST', '${_c(id)}/end-request', body: {'note': note}));

  @override
  Future<Cooperation> confirmEnd(String id) =>
      _coop(_write('POST', '${_c(id)}/end-confirm'));

  @override
  Future<Cooperation> disputeEnd(String id, String note) =>
      _coop(_write('POST', '${_c(id)}/end-dispute', body: {'note': note}));

  @override
  Future<Cooperation> addUpdate(String id, String text) =>
      _coop(_write('POST', '${_c(id)}/updates', body: {'text': text}));

  @override
  Future<Cooperation> requestMilestone(String id, int index,
          {String note = '', List<List<int>> photos = const []}) =>
      _coop(_write('POST', '${_c(id)}/milestones/$index/request',
          body: {'note': note, 'photos': photosJson(photos)}));

  @override
  Future<Cooperation> setMilestones(String id, List<Milestone> plan) =>
      _coop(_write('PUT', '${_c(id)}/milestones',
          body: {'milestones': [for (final m in plan) milestoneJson(m)]}));

  @override
  Future<Cooperation> answerMilestone(String id, int index, bool accept,
          {String note = ''}) =>
      _coop(_write('POST', '${_c(id)}/milestones/$index/answer',
          body: {'accept': accept, 'note': note}));

  @override
  Future<Cooperation> logWork(String id, int headcount,
          {String note = '', List<List<int>> photos = const []}) =>
      _coop(_write('POST', '${_c(id)}/work-logs', body: {
        'headcount': headcount,
        'note': note,
        'photos': photosJson(photos),
      }));

  @override
  Future<Cooperation> confirmWork(String id, String logId) =>
      _coop(_write('POST', '${_c(id)}/work-logs/$logId/confirm'));

  @override
  Future<Cooperation?> cooperation(String id) async {
    if (currentId == null) return null;
    final j = await _maybe(_c(id));
    if (j == null) return null;
    final c = await _coopFrom(j);
    await _names([c.ownerId, c.providerId]);
    return c;
  }

  @override
  Future<List<Cooperation>> myCooperations() async {
    final list = await Future.wait(
        [for (final j in await _list('/client/me/cooperations')) _coopFrom(j)]);
    await _names(list.expand((c) => [c.ownerId, c.providerId]));
    return list;
  }

  @override
  Future<List<Cooperation>> cooperationsFor(String demandId) async =>
      Future.wait([
        for (final j in await _list('/client/demands/$demandId/cooperations'))
          _coopFrom(j)
      ]);

  // ───────────────────────────── reviews ─────────────────────────────

  @override
  Future<Review> submitReview(
          String cooperationId, Map<String, int> scores, String text) async =>
      reviewFrom(await _write('POST', '${_c(cooperationId)}/reviews',
          body: {'scores': scores, 'text': text}) as Map<String, dynamic>);

  @override
  Future<List<Review>> reviewsFor(String cooperationId) async => [
        for (final j in await _list('${_c(cooperationId)}/reviews'))
          reviewFrom(j)
      ];

  @override
  Future<List<Review>> reviewsAbout(String accountId) async {
    final list = [
      for (final j in await _list('/client/accounts/$accountId/reviews'))
        reviewFrom(j)
    ];
    await _names(list.map((r) => r.authorId));
    return list;
  }

  // ─────────────────────────────── chat ───────────────────────────────

  @override
  Future<List<Conversation>> conversations() async {
    // Polled by the shell; signed out there is nothing to ask the server.
    if (currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    final list = [
      for (final j in await _list('/client/conversations')) conversationFrom(j)
    ];
    await _names(list.expand((c) => c.participants));
    return list;
  }

  @override
  Future<Conversation> openConversation(String otherAccountId,
      {String? demandId}) async {
    final c = conversationFrom(await _write('POST', '/client/conversations',
        body: {
          'account_id': otherAccountId,
          if (demandId != null) 'demand_id': demandId,
        }) as Map<String, dynamic>);
    await _names(c.participants);
    return c;
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
        for (final j
            in await _list('/client/conversations/$conversationId/messages'))
          messageFrom(j)
      ];

  @override
  Future<ChatMessage> send(String conversationId, MessageKind kind,
          {String text = '', String? refId}) async =>
      messageFrom(await _write(
          'POST', '/client/conversations/$conversationId/messages',
          body: {
            'kind': kind.name,
            'text': text,
            if (refId != null) 'ref_id': refId,
          }) as Map<String, dynamic>);

  @override
  Future<ChatMessage> resend(String messageId) async => messageFrom(
      await _write('POST', '/client/messages/$messageId/resend')
          as Map<String, dynamic>);

  @override
  Future<void> markConversationRead(String conversationId) async {
    await _write('POST', '/client/conversations/$conversationId/read');
  }

  @override
  Future<void> block(String accountId) async {
    await _write('POST', '/client/blocks', body: {'account_id': accountId});
  }

  @override
  Future<void> unblock(String accountId) async {
    await _write('DELETE', '/client/blocks/$accountId');
  }

  @override
  Future<Set<String>> blocked() async {
    if (currentId == null) return {};
    return {for (final id in await _call('GET', '/client/blocks') as List) id as String};
  }

  @override
  Future<ChatMessage> sharePhone(String conversationId) async => messageFrom(
      await _write('POST', '/client/conversations/$conversationId/share-phone')
          as Map<String, dynamic>);

  @override
  Future<int> unreadMessages() async {
    if (currentId == null) return 0;
    final j = await _call('GET', '/client/messages/unread-count') as Map<String, dynamic>;
    return (j['count'] as num).toInt();
  }

  // ─────────────────────────── notifications ───────────────────────────

  @override
  Future<List<AppNotification>> notifications() async {
    if (currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    return [for (final j in await _list('/client/notifications')) noticeFrom(j)];
  }

  @override
  Future<int> unreadNotifications() async {
    if (currentId == null) return 0;
    final j = await _call('GET', '/client/notifications/unread-count')
        as Map<String, dynamic>;
    return (j['count'] as num).toInt();
  }

  @override
  Future<void> markRead(String id) async {
    await _write('POST', '/client/notifications/$id/read');
  }

  @override
  Future<void> markAllRead() async {
    await _write('POST', '/client/notifications/read-all');
  }

  // ─────────────────────── posts ↔ demands ───────────────────────

  @override
  Future<List<Demand>> demandsForPost(String postId) async =>
      [for (final j in await _list('/client/posts/$postId/demands')) demandFrom(j)];

  @override
  Future<PostBuild?> postBuild(String postId) async {
    final j = await _call('GET', '/client/posts/$postId/build');
    if (j == null) return null;
    final b = postBuildFrom(j as Map<String, dynamic>);
    await _names(b.builders.map((x) => x.profile.ownerId));
    return b;
  }

  @override
  Future<HousePost?> postForDemand(String demandId) async {
    final j = await _call('GET', '/client/demands/$demandId/post');
    if (j == null) return null;
    return (await _posts([j])).single;
  }

  // ───────────────────────────── moderation ─────────────────────────────

  @override
  Future<void> report(ReportTarget target, String targetId, String reason) async {
    await _write('POST', '/client/reports',
        body: {'target': target.name, 'target_id': targetId, 'reason': reason});
  }

  @override
  Future<Appeal> fileAppeal(String target, String targetId, String text) async =>
      appealFrom(await _write('POST', '/client/appeals',
              body: {'target': target, 'target_id': targetId, 'text': text})
          as Map<String, dynamic>);

  @override
  Future<List<Appeal>> myAppeals() async =>
      [for (final j in await _list('/client/appeals')) appealFrom(j)];

  // ───────────────────────────── trust ─────────────────────────────

  @override
  Future<Verification> requestVerification(
          String profileId, String phone, List<Uint8List> photos,
          {String note = ''}) async =>
      verificationFrom(await _write('POST', '/client/profiles/$profileId/verification',
          body: {'phone': phone, 'note': note, 'photos': photosJson(photos)}) as Map<String, dynamic>);

  @override
  Future<Verification?> myVerification(String profileId) async {
    final j = await _call('GET', '/client/profiles/$profileId/verification');
    return j == null ? null : verificationFrom(j as Map<String, dynamic>);
  }

  @override
  Future<DemandAlert> demandAlert() async =>
      alertFrom(await _call('GET', '/client/demand-alert') as Map<String, dynamic>);

  @override
  Future<DemandAlert> saveDemandAlert(DemandAlert alert) async => alertFrom(
      await _write('PUT', '/client/demand-alert', body: alertJson(alert))
          as Map<String, dynamic>);

  @override
  Future<NotificationSettings> notificationSettings() async => settingsFrom(
      await _call('GET', '/client/notification-settings') as Map<String, dynamic>);

  @override
  Future<NotificationSettings> saveNotificationSettings(NotificationSettings s) async =>
      settingsFrom(await _write('PUT', '/client/notification-settings', body: {
        'muted': s.muted,
        'quiet_start': s.quietStart,
        'quiet_end': s.quietEnd,
      }) as Map<String, dynamic>);

  // ───────────────────────────── back office ─────────────────────────────

  Cooperation _coopPlain(Map<String, dynamic> j) => cooperationFrom(j, media: _media);

  Future<Paged<T>> _paged<T>(String path, T Function(Map<String, dynamic>) item,
          {int page = 1, int pageSize = 20, Map<String, String> query = const {}}) async =>
      pagedFrom(
          await _call('GET', path, query: {
            ...query,
            'page': '$page',
            'page_size': '$pageSize',
          }),
          item);

  @override
  Future<AdminTodo> todo() async =>
      todoFrom(await _call('GET', '/admin/todo') as Map<String, dynamic>, _coopPlain);

  @override
  Future<AdminDashboard> dashboard() async =>
      dashboardFrom(await _call('GET', '/admin/dashboard') as Map<String, dynamic>);

  @override
  Future<Paged<Demand>> reviewQueue({int page = 1, int pageSize = 20}) =>
      _paged('/admin/review-queue', demandFrom, page: page, pageSize: pageSize);

  @override
  Future<Paged<Demand>> adminDemands(
          {DemandStatus? status, String query = '', int page = 1, int pageSize = 20}) =>
      _paged('/admin/demands', demandFrom, page: page, pageSize: pageSize, query: {
        if (status != null) 'status': status.name,
        if (query.trim().isNotEmpty) 'q': query.trim(),
      });

  @override
  Future<void> approve(String demandId) async {
    await _write('POST', '/admin/demands/$demandId/approve');
  }

  @override
  Future<void> reject(String demandId, String reason) async {
    await _write('POST', '/admin/demands/$demandId/reject', body: {'reason': reason});
  }

  @override
  Future<BatchResult> decideMany(List<String> ids, bool approve,
      {String reason = ''}) async {
    final j = await _write('POST', '/admin/demands/batch',
        body: {'ids': ids, 'approve': approve, 'reason': reason}) as Map<String, dynamic>;
    return BatchResult(_int(j['done']), [for (final f in j['failed'] as List? ?? const []) f as String]);
  }

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Future<Paged<ReportView>> reports(
          {ReportStatus? status, int page = 1, int pageSize = 20}) =>
      _paged('/admin/reports', reportViewFrom,
          page: page, pageSize: pageSize, query: {if (status != null) 'status': status.name});

  @override
  Future<void> resolveReport(String reportId, bool upheld, String note) async {
    await _write('POST', '/admin/reports/$reportId/resolve',
        body: {'upheld': upheld, 'note': note});
  }

  @override
  Future<Paged<Appeal>> appeals(
          {AppealStatus? status, int page = 1, int pageSize = 20}) =>
      _paged('/admin/appeals', appealFrom,
          page: page, pageSize: pageSize, query: {if (status != null) 'status': status.name});

  @override
  Future<void> resolveAppeal(String id, bool accept, String note) async {
    await _write('POST', '/admin/appeals/$id/resolve', body: {'accept': accept, 'note': note});
  }

  @override
  Future<Paged<Verification>> verifications(
          {VerificationStatus? status, int page = 1, int pageSize = 20}) =>
      _paged('/admin/verifications', verificationFrom,
          page: page, pageSize: pageSize, query: {if (status != null) 'status': status.name});

  @override
  Future<void> resolveVerification(String id, bool approve, String note) async {
    await _write('POST', '/admin/verifications/$id/resolve',
        body: {'accept': approve, 'note': note});
  }

  @override
  Future<void> setRestriction(String accountId, bool restricted, String note) async {
    await _write('POST', '/admin/accounts/$accountId/restriction',
        body: {'restricted': restricted, 'note': note});
  }

  @override
  Future<void> setPostHidden(String postId, bool hidden, String note) async {
    await _write('POST', '/admin/posts/$postId/visibility',
        body: {'hidden': hidden, 'note': note});
  }

  @override
  Future<Paged<AuditEntry>> audit(
          {String? by, String? targetId, int page = 1, int pageSize = 20}) =>
      _paged('/admin/audit', auditFrom, page: page, pageSize: pageSize, query: {
        if (by != null) 'by': by,
        if (targetId != null) 'target_id': targetId,
      });

  @override
  Future<Paged<AdminUserRow>> users(
          {String query = '',
          bool restricted = false,
          bool admins = false,
          int page = 1,
          int pageSize = 20}) =>
      _paged('/admin/users', userRowFrom, page: page, pageSize: pageSize, query: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (restricted) 'restricted': 'true',
        if (admins) 'admins': 'true',
      });

  @override
  Future<List<AdminUserRow>> team() async =>
      [for (final j in await _list('/admin/team')) userRowFrom(j)];

  @override
  Future<void> setRole(String accountId, String? role) async {
    await _write('PUT', '/admin/users/$accountId/role', body: {'role': role ?? ''});
  }

  @override
  Future<AccountDetail> accountDetail(String accountId) async {
    final j = await _call('GET', '/admin/accounts/$accountId') as Map<String, dynamic>;
    return accountDetailFrom(j, _coopPlain);
  }

  @override
  Future<PushPolicy> pushPolicy() async =>
      policyFrom(await _call('GET', '/admin/push-policy') as Map<String, dynamic>);

  @override
  Future<PushPolicy> savePushPolicy(PushPolicy p) async => policyFrom(await _write(
      'PUT', '/admin/push-policy',
      body: {'quiet_start': p.quietStart, 'quiet_end': p.quietEnd, 'daily_cap': p.dailyCap})
      as Map<String, dynamic>);
}
