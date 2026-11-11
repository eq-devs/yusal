import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/platform/data/http/http_backend.dart';
import 'package:yusal/platform/data/repositories.dart';
import 'package:yusal/platform/domain/models.dart';

/// A tiny stand-in for yusal-api: just enough routes to check the client's
/// requests, response mapping, token handling and error codes.
class FakeApi {
  final requests = <http.Request>[];
  int accessVersion = 1;
  bool expireNextAccess = false;

  /// Answers /auth/refresh with this status (e.g. 502 while the server is down).
  int? refreshStatus;

  static const user = {
    'id': 'u1',
    'display_name': 'Ана',
    'email': 'ana@example.com',
    'status': 'active',
    'providers': [],
    'created_at': '2026-11-05T10:00:00Z',
  };

  static const postJson = {
    'id': 'p1',
    'owner_id': 'u1',
    'snapshot_id': 's1',
    'title': '两层砖房',
    'story': '',
    'region': 'almaty',
    'area': 120.5,
    'floors': 2,
    'rooms': 4,
    'tags': ['brick'],
    'open_for_builders': false,
    'focus': ['cost'],
    'show_build': false,
    'status': 'published',
    'like_count': 3,
    'comment_count': 1,
    'rating_sum': 4,
    'rating_count': 1,
    'reuse_count': 0,
    'preview_url': '/client/posts/p1/preview',
    'created_at': '2026-11-05T10:00:00Z',
    'updated_at': '2026-11-05T10:00:00Z',
  };

  static final coopJson = {
    'id': 'c1',
    'demand_id': 'd1',
    'application_id': 'a1',
    'owner_id': 'u1',
    'provider_id': 'u2',
    'profile_id': 'pr',
    'status': 'confirmed',
    'created_at': '2026-11-05T10:00:00Z',
    'agreements': [],
    'milestones': [
      {'key': 'walls', 'percent': 40, 'status': 'requested', 'photos': ['/media/m1']}
    ],
    'work_logs': [],
    'updates': [],
  };

  http.Response ok(Object? data, [int status = 200]) => http.Response(
      jsonEncode({'success': true, 'data': data, 'msg': '', 'code': ''}),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'});

  http.Response fail(int status, String code) => http.Response(
      jsonEncode({'success': false, 'data': null, 'msg': code, 'code': code}),
      status);

  Map<String, dynamic> tokens() =>
      {'access_token': 'a$accessVersion', 'refresh_token': 'r$accessVersion'};

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    final authed = r.headers['Authorization'] == 'Bearer a$accessVersion';
    if (path.startsWith('/client/') &&
        !path.startsWith('/client/posts') &&
        !authed) {
      return fail(401, 'UNAUTHORIZED');
    }
    if (expireNextAccess && path.startsWith('/client/me')) {
      expireNextAccess = false;
      accessVersion++;
      return fail(401, 'UNAUTHORIZED');
    }
    switch ((r.method, path)) {
      case ('POST', '/auth/oauth/google'):
        return ok({...tokens(), 'user': user, 'is_new': true});
      case ('POST', '/auth/refresh'):
        if (refreshStatus case final status?) {
          return http.Response('Bad Gateway', status);
        }
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (!(body['refresh_token'] as String).startsWith('r')) {
          return fail(401, 'INVALID_TOKEN');
        }
        return ok(tokens());
      case ('GET', '/client/auth/me'):
        return ok(user);
      case ('POST', '/client/devices'):
      case ('DELETE', '/client/devices'):
        return ok('ok');
      case ('GET', '/client/cooperations/c1'):
        return ok(coopJson);
      case ('GET', '/media/m1'):
        return http.Response.bytes([7, 8], 200);
      case ('PATCH', '/client/auth/me'):
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return ok({...user, ...body});
      case ('GET', '/client/posts'):
        return ok({'items': [postJson], 'total': 1, 'page': 1, 'page_size': 100});
      case ('GET', '/client/accounts/u9'):
        return ok({...user, 'id': 'u9', 'display_name': '邻居'});
      case ('GET', '/client/posts/p1/preview'):
        return http.Response.bytes([1, 2, 3], 200);
      case ('GET', '/client/me/posts'):
        return ok([postJson]);
      case ('POST', '/client/posts/p1/comments'):
        return fail(429, 'RATE_LIMITED');
      case ('PUT', '/client/backups/proj%201'):
      case ('PUT', '/client/backups/proj 1'):
        return fail(409, 'CONFLICT');
    }
    return fail(404, 'NOT_FOUND');
  }
}

void main() {
  late FakeApi api;
  late HttpBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    backend = HttpBackend('https://api.test',
        client: MockClient(api.handle), seed: false);
  });

  test('Google sign-in stores the session and restores it later', () async {
    final a = await backend.signInWithProvider('google', 'id-token');
    expect(a.id, 'u1');
    expect(a.displayName, 'Ана');
    expect(backend.currentAccount?.id, 'u1');
    expect(jsonDecode(api.requests.first.body), {'id_token': 'id-token'});

    final next = HttpBackend('https://api.test',
        client: MockClient(api.handle), seed: false);
    await next.restore();
    expect(next.currentAccount?.id, 'u1');
  });

  test('an expired access token is refreshed once and the call retried',
      () async {
    await backend.signInWithProvider('google', 'id-token');
    api.expireNextAccess = true;
    final mine = await backend.myPosts();
    expect(mine.single.id, 'p1');
    expect(api.requests.where((r) => r.url.path == '/auth/refresh'), hasLength(1));
  });

  test('requests that hit an expired token together refresh it once',
      () async {
    await backend.signInWithProvider('google', 'id-token');
    api.expireNextAccess = true;
    final both = await Future.wait([backend.myPosts(), backend.myPosts()]);
    expect(both.map((l) => l.single.id), ['p1', 'p1']);
    expect(
        api.requests.where((r) => r.url.path == '/auth/refresh'), hasLength(1));
  });

  test('a server that never answers fails the call as a network error',
      () async {
    final silent = HttpBackend('https://api.test',
        client: MockClient((_) => Completer<http.Response>().future),
        seed: false,
        timeout: const Duration(milliseconds: 50));
    await expectLater(
        silent.feed(const FeedFilter()),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.network)));
  });

  test('a server that is down at startup does not sign the user out',
      () async {
    await backend.signInWithProvider('google', 'id-token');
    api.refreshStatus = 502;
    final offline = HttpBackend('https://api.test',
        client: MockClient(api.handle), seed: false);
    await offline.restore();
    expect(offline.currentAccount, isNull);

    api.refreshStatus = null;
    final later = HttpBackend('https://api.test',
        client: MockClient(api.handle), seed: false);
    await later.restore();
    expect(later.currentAccount?.id, 'u1');
  });

  test('a session that could not restore comes back once the server does',
      () async {
    await backend.signInWithProvider('google', 'id-token');
    api.refreshStatus = 502;
    final offline = HttpBackend('https://api.test',
        client: MockClient(api.handle), seed: false)
      ..retryDelays = const [Duration(milliseconds: 20)];
    await offline.restore();
    expect(offline.currentAccount, isNull);
    api.refreshStatus = null;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(offline.currentAccount?.id, 'u1');
  });

  test('a rejected refresh token signs the user out', () async {
    await backend.signInWithProvider('google', 'id-token');
    api.refreshStatus = 401;
    final next = HttpBackend('https://api.test',
        client: MockClient(api.handle), seed: false);
    await next.restore();
    api.refreshStatus = null;
    final later = HttpBackend('https://api.test',
        client: MockClient(api.handle), seed: false);
    await later.restore();
    expect(later.currentAccount, isNull);
  });

  test('feed maps posts and loads their thumbnails', () async {
    final feed = await backend.feed(const FeedFilter(
        region: 'almaty', sort: FeedSort.topRated, askingFeedback: true));
    final p = feed.single;
    expect(p.title, '两层砖房');
    expect(p.area, 120.5);
    expect(p.rating, 4);
    // A feed comes without pictures; each card asks for its own, once.
    expect(p.preview, isNull);
    expect(await backend.postPreview(p.id), [1, 2, 3]);
    expect(backend.postPreview(p.id), [1, 2, 3]);
    expect(api.requests.where((r) => r.url.path.endsWith('/preview')).length,
        1);
    final q = api.requests.first.url.queryParameters;
    expect(q['region'], 'almaty');
    expect(q['sort'], 'topRated');
    expect(q['asking_feedback'], 'true');
  });

  test('rows naming the same person ask for the account once', () async {
    await backend.signInWithProvider('google', 'id-token');
    final names = await Future.wait(
        [for (var i = 0; i < 5; i++) backend.account('u9')]);
    expect(names.map((a) => a!.displayName).toSet(), {'邻居'});
    expect((await backend.account('u9'))!.displayName, '邻居');
    expect(
        api.requests.where((r) => r.url.path == '/client/accounts/u9').length,
        1);
  });

  test('server error codes become ApiFailure codes', () async {
    await backend.signInWithProvider('google', 'id-token');
    expect(
        () => backend.comment('p1', 'hi'),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.rateLimited)));
    expect(
        () => backend.upload(
            projectId: 'proj 1',
            name: 'x',
            houseText: '{}',
            designUpdatedAt: 't2',
            expectedPreviousUpdatedAt: 't1'),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.conflict)));
    expect(await backend.post('missing'), isNull);
  });

  test('saving the phone patches the account and updates the session',
      () async {
    await backend.signInWithProvider('google', 'id-token');
    final a = await backend.updatePhone('+77015550011');
    expect(a.phone, '+77015550011');
    expect(backend.currentAccount?.phone, '+77015550011');
    final patch = api.requests.last;
    expect(patch.method, 'PATCH');
    expect(jsonDecode(patch.body), {'phone': '+77015550011'});
  });

  test('the push token registers at sign-in and is dropped at sign-out',
      () async {
    await backend.setPushToken('fcm-1', platform: 'ios', language: 'ru');
    expect(api.requests.where((r) => r.url.path == '/client/devices'), isEmpty);
    await backend.signInWithProvider('google', 'id-token');
    await Future<void>.delayed(Duration.zero);
    final reg = api.requests.singleWhere((r) => r.url.path == '/client/devices');
    expect(reg.method, 'POST');
    expect(jsonDecode(reg.body),
        {'token': 'fcm-1', 'platform': 'ios', 'language': 'ru'});
    await backend.signOut();
    final drop = api.requests.last;
    expect((drop.method, drop.url.path), ('DELETE', '/client/devices'));
    expect(backend.currentAccount, isNull);
  });

  test('cooperation photos are fetched from /media once', () async {
    await backend.signInWithProvider('google', 'id-token');
    final c = await backend.cooperation('c1');
    expect(c!.milestones.single.photos.single, [7, 8]);
    await backend.cooperation('c1');
    expect(api.requests.where((r) => r.url.path == '/media/m1'), hasLength(1));
  });

  test('signed out, protected calls report notSignedIn', () async {
    expect(
        () => backend.backups(),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.notSignedIn)));
    expect(await backend.likedPosts(), isEmpty);
  });

  test('signed out, polled lists fail without a request', () async {
    final before = api.requests.length;
    for (final call in [backend.conversations, backend.myPosts]) {
      await expectLater(
          call(),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', ApiCodes.notSignedIn)));
    }
    expect(api.requests.length, before);
  });
}
