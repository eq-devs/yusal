import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/shared/settings/settings.dart';
import 'package:yusal/app/http_backend.dart';
import 'package:yusal/shared/model/models.dart';
import 'package:yusal/services/push/push_setup.dart';

import 'http_backend_test.dart' show FakeApi;

class FakeMessaging implements PushMessaging {
  FakeMessaging({this.available = true, this.allowed = true});
  final bool available;
  final bool allowed;
  int asked = 0;
  final refreshes = StreamController<String>();
  final taps = StreamController<Map<String, dynamic>>();
  Map<String, dynamic>? launch;

  /// Closes the fake streams; not awaited, since an unheard stream's close
  /// never completes.
  void close() {
    refreshes.close();
    taps.close();
  }

  @override
  Future<bool> init() async => available;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return allowed;
  }

  @override
  Future<String?> token() async => 'tok-1';
  @override
  Stream<String> get tokenRefreshes => refreshes.stream;
  @override
  Stream<Map<String, dynamic>> get opened => taps.stream;
  @override
  Future<Map<String, dynamic>?> launchedFrom() async => launch;
}

void main() {
  late FakeApi api;
  late HttpBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.lang = AppLang.kk;
    api = FakeApi();
    backend = HttpBackend('https://api.test', client: MockClient(api.handle));
  });

  Future<void> signIn() => backend.signInWithProvider('google', 'id-token');

  List<Map<String, dynamic>> registrations() => [
        for (final r in api.requests)
          if (r.method == 'POST' && r.url.path == '/client/devices')
            jsonDecode(r.body) as Map<String, dynamic>
      ];

  test('a push points at the object in its data', () {
    expect(pushTarget({'ref_type': 'conversation', 'ref_id': 'c1'}),
        (RefType.conversation, 'c1'));
    expect(pushTarget({'ref_type': 'cooperation', 'ref_id': 'k9'}),
        (RefType.cooperation, 'k9'));
    expect(pushTarget({'ref_type': 'nope', 'ref_id': 'x'}), isNull);
    expect(pushTarget({'ref_type': 'demand'}), isNull);
    expect(pushTarget(const {}), isNull);
  });

  test('registers the token with platform and language, and on refresh',
      () async {
    await signIn();
    final m = FakeMessaging();
    addTearDown(m.close);
    await PushSetup(backend, GlobalKey<NavigatorState>(), messaging: m).start();
    expect(registrations(), [
      {'token': 'tok-1', 'platform': PushSetup.platform, 'language': 'kk'}
    ]);
    m.refreshes.add('tok-2');
    await pumpEventQueue();
    expect(registrations().last['token'], 'tok-2');
  });

  test('permission is asked after sign-in, not at first launch', () async {
    final m = FakeMessaging();
    addTearDown(m.close);
    unawaited(
        PushSetup(backend, GlobalKey<NavigatorState>(), messaging: m).start());
    await pumpEventQueue();
    expect(m.asked, 0, reason: 'nobody is signed in yet');
    expect(registrations(), isEmpty);
    await signIn();
    await pumpEventQueue();
    expect(m.asked, 1);
    expect(registrations().single['token'], 'tok-1');
  });

  test('without Firebase config or permission nothing is registered', () async {
    await signIn();
    await PushSetup(backend, GlobalKey<NavigatorState>(),
            messaging: FakeMessaging(available: false))
        .start();
    await PushSetup(backend, GlobalKey<NavigatorState>(),
            messaging: FakeMessaging(allowed: false))
        .start();
    expect(registrations(), isEmpty);
  });

  testWidgets('tapping a push, or launching from one, opens its target',
      (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const SizedBox()));
    final opened = <(RefType, String)>[];
    // Routing works whether or not pushes are allowed; no token here keeps
    // the network out of the widget test (registration is tested above).
    final m = FakeMessaging(allowed: false)
      ..launch = {'ref_type': 'cooperation', 'ref_id': 'k1'};
    addTearDown(m.close);
    final setup = PushSetup(backend, nav,
        messaging: m, opener: (_, type, id) async => opened.add((type, id)));
    await setup.start();
    await t.pump();
    expect(opened, [(RefType.cooperation, 'k1')]);
    m.taps.add({'ref_type': 'conversation', 'ref_id': 'c7'});
    await t.pump();
    m.taps.add({'ref_type': 'unknown', 'ref_id': 'x'});
    await t.pump();
    expect(opened, [(RefType.cooperation, 'k1'), (RefType.conversation, 'c7')]);
    setup.dispose();
  });
}
