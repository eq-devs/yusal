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
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (!(body['refresh_token'] as String).startsWith('r')) {
          return fail(401, 'INVALID_TOKEN');
        }
        return ok(tokens());
      case ('GET', '/client/auth/me'):
        return ok(user);
      case ('PATCH', '/client/auth/me'):
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return ok({...user, ...body});
      case ('GET', '/client/posts'):
        return ok({'items': [postJson], 'total': 1, 'page': 1, 'page_size': 100});
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

  test('feed maps posts and loads their thumbnails', () async {
    final feed = await backend.feed(const FeedFilter(
        region: 'almaty', sort: FeedSort.topRated, askingFeedback: true));
    final p = feed.single;
    expect(p.title, '两层砖房');
    expect(p.area, 120.5);
    expect(p.rating, 4);
    expect(p.preview, [1, 2, 3]);
    final q = api.requests.first.url.queryParameters;
    expect(q['region'], 'almaty');
    expect(q['sort'], 'topRated');
    expect(q['asking_feedback'], 'true');
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
