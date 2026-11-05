import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';
import '../mock/mock_backend.dart';
import '../repositories.dart';

/// Talks to the real Go backend (`eq-devs/yusal-api`) for what it already
/// serves: sign-in and accounts, design snapshots, house posts with likes
/// and critiques, and cloud backup. Everything else (profiles, demands,
/// quotes, cooperations, chat, notifications, moderation) still runs on the
/// in-memory [MockBackend] it extends, under the real account id, until the
/// server has those modules.
class HttpBackend extends MockBackend {
  HttpBackend(this.baseUrl, {http.Client? client, super.seed})
      : _http = client ?? http.Client(),
        super(latency: Duration.zero);

  /// e.g. `https://api.example.com`, no trailing slash.
  final String baseUrl;
  final http.Client _http;

  static const _refreshKey = 'yusal_api.refresh_token';

  String? _access;
  String? _refresh;

  /// Posts' plan thumbnails, fetched once per post.
  final _previews = <String, List<int>?>{};

  // ───────────────────────────── transport ─────────────────────────────

  Future<dynamic> _call(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true}) async {
    final res = await _send(method, path, body: body, query: query, auth: auth);
    if (res.statusCode == 401 && auth && _refresh != null) {
      if (await _refreshTokens()) {
        return _decode(
            await _send(method, path, body: body, query: query, auth: auth));
      }
    }
    return _decode(res);
  }

  Future<http.Response> _send(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path').replace(
        queryParameters: query == null || query.isEmpty ? null : query);
    final req = http.Request(method, uri);
    req.headers['Accept'] = 'application/json';
    if (auth && _access != null) {
      req.headers['Authorization'] = 'Bearer $_access';
    }
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    try {
      return await http.Response.fromStream(await _http.send(req));
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
    if (res.statusCode != 200) {
      await _forget();
      return false;
    }
    _takeTokens(_decode(res) as Map<String, dynamic>);
    await _save();
    return true;
  }

  void _takeTokens(Map<String, dynamic> data) {
    _access = data['access_token'] as String?;
    _refresh = data['refresh_token'] as String?;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_refresh == null) {
      await prefs.remove(_refreshKey);
    } else {
      await prefs.setString(_refreshKey, _refresh!);
    }
  }

  Future<void> _forget() async {
    _access = null;
    _refresh = null;
    currentId = null;
    await _save();
    notify();
  }

  // ─────────────────────────────── auth ───────────────────────────────

  /// Signs back in with the refresh token saved on this device, if any.
  /// Call once at startup; failures just leave the user signed out.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _refresh = prefs.getString(_refreshKey);
    if (_refresh == null) return;
    try {
      if (!await _refreshTokens()) return;
      _setMe(await _call('GET', '/client/auth/me') as Map<String, dynamic>);
      notify();
    } on ApiFailure {
      // Offline or revoked: stay signed out, keep nothing.
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

  static Account _account(Map<String, dynamic> u) => Account(
      id: u['id'] as String,
      phone: '',
      phoneVerified: false,
      displayName: u['display_name'] as String? ?? '',
      deleted: u['deleted'] == true || u['status'] == 'deleted',
      restricted: u['status'] == 'blocked',
      createdAt: DateTime.parse(u['created_at'] as String));

  @override
  Future<void> requestCode(String phone) async =>
      throw const ApiFailure(ApiCodes.invalidState, 'phone sign-in');

  @override
  Future<Account> verify(String phone, String code,
          {String? displayName}) async =>
      throw const ApiFailure(ApiCodes.invalidState, 'phone sign-in');

  @override
  Future<void> signOut() => _forget();

  @override
  Future<Account> updateName(String name) async {
    final a = _setMe(await _call('PATCH', '/client/auth/me',
        body: {'display_name': name}) as Map<String, dynamic>);
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
    try {
      final a = _account(
          await _call('GET', '/client/accounts/$id') as Map<String, dynamic>);
      // Keep it for mock-served screens that look accounts up by id.
      accounts[id] = a;
      return a;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return accounts[id];
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
    // Demands (still mock-served) attach snapshots by id.
    snapshots[saved.id] = saved;
    notify();
    return saved;
  }

  @override
  Future<DesignSnapshot?> snapshot(String id,
      {String? postId, String? demandId}) async {
    if (demandId != null) {
      return super.snapshot(id, postId: postId, demandId: demandId);
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

  /// Maps posts and fills in their thumbnails (fetched once each).
  Future<List<HousePost>> _posts(List raw) async {
    final list = [for (final j in raw) j as Map<String, dynamic>];
    await Future.wait([
      for (final j in list)
        if (!_previews.containsKey(j['id'])) _loadPreview(j['id'] as String)
    ]);
    return [for (final j in list) _post(j)];
  }

  Future<void> _loadPreview(String postId) async {
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
    return _posts(data['items'] as List);
  }

  @override
  Future<HousePost?> post(String id) async {
    try {
      final j = await _call('GET', '/client/posts/$id') as Map<String, dynamic>;
      return (await _posts([j])).single;
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<List<HousePost>> myPosts() async =>
      _posts(await _call('GET', '/client/me/posts') as List);

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
    notify();
    return data['liked'] as bool;
  }

  @override
  Future<bool> liked(String postId) async {
    if (currentId == null) return false;
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
}
