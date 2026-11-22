import 'dart:async';
import 'package:yusal/service/push/push_setup.dart';
import 'support/test_scope.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/shared/model/models.dart';

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
      {
        'key': 'walls',
        'percent': 40,
        'status': 'requested',
        'photos': ['/media/m1']
      }
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
      case ('GET', '/client/auth/methods'):
        return ok([
          {'provider': 'email', 'email': 'ana@example.com'},
          {'provider': 'google', 'email': 'ana@example.com'},
        ]);
      case ('DELETE', '/client/auth/methods/email'):
        return ok([
          {'provider': 'google', 'email': 'ana@example.com'},
        ]);
      case ('DELETE', '/client/auth/methods/google'):
        return fail(409, 'LAST_METHOD');
      case ('POST', '/client/auth/methods/apple'):
        return ok([
          {'provider': 'google'},
          {'provider': 'apple'},
        ]);
      case ('POST', '/auth/register'):
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (body['email'] == 'taken@example.com') {
          return fail(409, 'EMAIL_TAKEN');
        }
        return ok({...tokens(), 'user': user, 'is_new': true});
      case ('POST', '/auth/login'):
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (body['password'] != 'correct-horse') {
          return fail(401, 'INVALID_CREDENTIALS');
        }
        return ok({...tokens(), 'user': user, 'is_new': false});
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
        return ok({
          'items': [postJson],
          'total': 1,
          'page': 1,
          'page_size': 100
        });
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
  late TestHttp backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    backend = TestHttp('https://api.test', client: MockClient(api.handle));
  });

  test('Google sign-in stores the session and restores it later', () async {
    final a = await backend.auth.signInWithProvider('google', 'id-token');
    expect(a.id, 'u1');
    expect(a.displayName, 'Ана');
    expect(backend.api.currentAccount?.id, 'u1');
    expect(jsonDecode(api.requests.first.body), {'id_token': 'id-token'});

    final next = TestHttp('https://api.test', client: MockClient(api.handle));
    await next.api.restore();
    expect(next.api.currentAccount?.id, 'u1');
  });

  test('email sign-up and sign-in store the session', () async {
    final a = await backend.auth.signInWithEmail(
        ' ana@example.com ', 'correct-horse',
        register: true, name: ' Ана ');
    expect(a.id, 'u1');
    expect(jsonDecode(api.requests.first.body), {
      'email': 'ana@example.com',
      'password': 'correct-horse',
      'name': 'Ана'
    });
    expect(api.requests.first.headers.containsKey('Authorization'), isFalse);

    final next = TestHttp('https://api.test', client: MockClient(api.handle));
    await next.api.restore();
    expect(next.api.currentAccount?.id, 'u1');

    api.requests.clear();
    await backend.auth.signInWithEmail('ana@example.com', 'correct-horse');
    expect(api.requests.first.url.path, '/auth/login');
    expect(jsonDecode(api.requests.first.body),
        {'email': 'ana@example.com', 'password': 'correct-horse'});
  });

  test('a wrong password or a taken email fail with their own codes', () async {
    await expectLater(
        backend.auth.signInWithEmail('ana@example.com', 'nope'),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.badCredentials)));
    await expectLater(
        backend.auth.signInWithEmail('taken@example.com', 'correct-horse',
            register: true),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.emailTaken)));
    expect(backend.api.currentAccount, isNull);
  });

  test('an expired access token is refreshed once and the call retried',
      () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    api.expireNextAccess = true;
    final mine = await backend.posts.myPosts();
    expect(mine.single.id, 'p1');
    expect(
        api.requests.where((r) => r.url.path == '/auth/refresh'), hasLength(1));
  });

  test('requests that hit an expired token together refresh it once', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    api.expireNextAccess = true;
    final both =
        await Future.wait([backend.posts.myPosts(), backend.posts.myPosts()]);
    expect(both.map((l) => l.single.id), ['p1', 'p1']);
    expect(
        api.requests.where((r) => r.url.path == '/auth/refresh'), hasLength(1));
  });

  test('a server that never answers fails the call as a network error',
      () async {
    final silent = TestHttp('https://api.test',
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 50));
    await expectLater(
        silent.posts.feed(const FeedFilter()),
        throwsA(
            isA<ApiFailure>().having((e) => e.code, 'code', ApiCodes.network)));
  });

  test('sign-in methods: list, link, unlink, and the last one stays', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    final ms = await backend.auth.signInMethods();
    expect(ms.map((m) => '${m.provider}:${m.email}'),
        ['email:ana@example.com', 'google:ana@example.com']);
    expect((await backend.auth.unlinkSignIn('email')).map((m) => m.provider),
        ['google']);
    await expectLater(
        backend.auth.unlinkSignIn('google'),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.lastMethod)));
    api.requests.clear();
    expect(
        (await backend.auth.linkSignIn('apple', 'apple-token'))
            .map((m) => m.provider),
        ['google', 'apple']);
    expect(jsonDecode(api.requests.single.body), {'id_token': 'apple-token'});
  });

  test('a cold start shows the saved account before any request', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    api.requests.clear();
    final next = TestHttp('https://api.test', client: MockClient(api.handle));
    await next.api.loadSession();
    expect(next.api.currentAccount?.id, 'u1');
    expect(next.api.currentAccount?.displayName, 'Ана');
    expect(api.requests, isEmpty);
  });

  test('a server that is down at startup keeps the user signed in', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    api.refreshStatus = 502;
    final offline =
        TestHttp('https://api.test', client: MockClient(api.handle));
    await offline.api.restore();
    expect(offline.api.currentAccount?.id, 'u1');
  });

  test('a session that could not sync catches up once the server is back',
      () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    api.refreshStatus = 502;
    final offline = TestHttp('https://api.test', client: MockClient(api.handle))
      ..api.retryDelays = const [Duration(milliseconds: 20)];
    await offline.api.restore();
    api.requests.clear();
    api.refreshStatus = null;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(api.requests.map((r) => r.url.path),
        containsAll(['/auth/refresh', '/client/auth/me']));
    expect(offline.api.currentAccount?.id, 'u1');
  });

  test('signing out forgets the saved account too', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    await backend.auth.signOut();
    final next = TestHttp('https://api.test', client: MockClient(api.handle));
    await next.api.loadSession();
    expect(next.api.currentAccount, isNull);
  });

  test('a rejected refresh token signs the user out', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    api.refreshStatus = 401;
    final next = TestHttp('https://api.test', client: MockClient(api.handle));
    await next.api.restore();
    // Shown from the saved account at first, then signed out by the sync.
    expect(next.api.currentAccount, isNull);
    api.refreshStatus = null;
    final later = TestHttp('https://api.test', client: MockClient(api.handle));
    await later.api.restore();
    expect(later.api.currentAccount, isNull);
  });

  test('feed maps posts and loads their thumbnails', () async {
    final feed = await backend.posts.feed(const FeedFilter(
        region: 'almaty', sort: FeedSort.topRated, askingFeedback: true));
    final p = feed.single;
    expect(p.title, '两层砖房');
    expect(p.area, 120.5);
    expect(p.rating, 4);
    // A feed comes without pictures; each card asks for its own, once.
    expect(p.preview, isNull);
    expect(await backend.posts.postPreview(p.id), [1, 2, 3]);
    expect(backend.posts.postPreview(p.id), [1, 2, 3]);
    expect(
        api.requests.where((r) => r.url.path.endsWith('/preview')).length, 1);
    final q = api.requests.first.url.queryParameters;
    expect(q['region'], 'almaty');
    expect(q['sort'], 'topRated');
    expect(q['asking_feedback'], 'true');
  });

  test('rows naming the same person ask for the account once', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    final names = await Future.wait(
        [for (var i = 0; i < 5; i++) backend.auth.account('u9')]);
    expect(names.map((a) => a!.displayName).toSet(), {'邻居'});
    expect((await backend.auth.account('u9'))!.displayName, '邻居');
    expect(
        api.requests.where((r) => r.url.path == '/client/accounts/u9').length,
        1);
  });

  test('server error codes become ApiFailure codes', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    expect(
        () => backend.posts.comment('p1', 'hi'),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.rateLimited)));
    expect(
        () => backend.backups.upload(
            projectId: 'proj 1',
            name: 'x',
            houseText: '{}',
            designUpdatedAt: 't2',
            expectedPreviousUpdatedAt: 't1'),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.conflict)));
    expect(await backend.posts.post('missing'), isNull);
  });

  test('saving the phone patches the account and updates the session',
      () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    final a = await backend.auth.updatePhone('+77015550011');
    expect(a.phone, '+77015550011');
    expect(backend.api.currentAccount?.phone, '+77015550011');
    final patch = api.requests.last;
    expect(patch.method, 'PATCH');
    expect(jsonDecode(patch.body), {'phone': '+77015550011'});
  });

  test('the push token is dropped at sign-out', () async {
    PushSetup.token = 'fcm-1';
    addTearDown(() => PushSetup.token = null);
    await backend.auth.signInWithProvider('google', 'id-token');
    await backend.auth.signOut();
    final drop = api.requests.last;
    expect((drop.method, drop.url.path), ('DELETE', '/client/devices'));
    expect(backend.api.currentAccount, isNull);
  });

  test('cooperation photos are fetched from /media once', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    final c = await backend.cooperations.cooperation('c1');
    expect(c!.milestones.single.photos.single, [7, 8]);
    await backend.cooperations.cooperation('c1');
    expect(api.requests.where((r) => r.url.path == '/media/m1'), hasLength(1));
  });

  test('signed out, protected calls report notSignedIn', () async {
    expect(
        () => backend.backups.backups(),
        throwsA(isA<ApiFailure>()
            .having((e) => e.code, 'code', ApiCodes.notSignedIn)));
    expect(await backend.posts.likedPosts(), isEmpty);
  });

  test('signed out, polled lists fail without a request', () async {
    final before = api.requests.length;
    for (final call in [backend.chat.conversations, backend.posts.myPosts]) {
      await expectLater(
          call(),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', ApiCodes.notSignedIn)));
    }
    expect(api.requests.length, before);
  });

  test('a read that loses its connection is tried again', () async {
    var drops = 2;
    final flaky = TestHttp('https://api.test', client: MockClient((r) async {
      if (r.url.path == '/client/posts' && drops-- > 0) {
        throw http.ClientException(
            'Connection closed before full header was received');
      }
      return api.handle(r);
    }));
    final feed = await flaky.posts.feed(const FeedFilter());
    expect(feed.single.id, 'p1');
  });

  test('a write that loses its connection is not sent twice', () async {
    var sent = 0;
    final flaky = TestHttp('https://api.test', client: MockClient((r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/messages')) {
        sent++;
        throw http.ClientException('Connection reset by peer');
      }
      return api.handle(r);
    }));
    await flaky.auth.signInWithProvider('google', 'id-token');
    await expectLater(
        flaky.chat.send('c1', MessageKind.text, text: 'hi'),
        throwsA(
            isA<ApiFailure>().having((e) => e.code, 'code', ApiCodes.network)));
    expect(sent, 1);
  });

  test('the same read asked for at once goes out once', () async {
    await backend.auth.signInWithProvider('google', 'id-token');
    final before = api.requests.length;
    await Future.wait([
      backend.posts.myPosts(),
      backend.posts.myPosts(),
      backend.posts.myPosts()
    ]);
    expect(
        api.requests
            .skip(before)
            .where((r) => r.url.path == '/client/me/posts'),
        hasLength(1));
  });
}
