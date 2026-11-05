import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  HttpBackend(this.baseUrl, {http.Client? client, bool seed = false})
      : _http = client ?? http.Client(),
        super(latency: Duration.zero, seed: seed);

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

  static Account _account(Map<String, dynamic> u) => accountFrom(u);

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
      cooperationFrom(await f as Map<String, dynamic>);

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
    final c = cooperationFrom(j);
    await _names([c.ownerId, c.providerId]);
    return c;
  }

  @override
  Future<List<Cooperation>> myCooperations() async {
    final list = [
      for (final j in await _list('/client/me/cooperations')) cooperationFrom(j)
    ];
    await _names(list.expand((c) => [c.ownerId, c.providerId]));
    return list;
  }

  @override
  Future<List<Cooperation>> cooperationsFor(String demandId) async => [
        for (final j in await _list('/client/demands/$demandId/cooperations'))
          cooperationFrom(j)
      ];

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
  Future<List<Demand>> reviewQueue() async =>
      [for (final j in await _list('/client/admin/review-queue')) demandFrom(j)];

  @override
  Future<void> approve(String demandId) async {
    await _write('POST', '/client/admin/demands/$demandId/approve');
  }

  @override
  Future<void> reject(String demandId, String reason) async {
    await _write('POST', '/client/admin/demands/$demandId/reject',
        body: {'reason': reason});
  }

  @override
  Future<List<Report>> reports() async =>
      [for (final j in await _list('/client/admin/reports')) reportFrom(j)];

  @override
  Future<void> resolveReport(String reportId, bool upheld, String note) async {
    await _write('POST', '/client/admin/reports/$reportId/resolve',
        body: {'upheld': upheld, 'note': note});
  }

  @override
  Future<List<AuditEntry>> audit() async =>
      [for (final j in await _list('/client/admin/audit')) auditFrom(j)];
}
