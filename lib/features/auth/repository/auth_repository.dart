import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/features/auth/model/auth_json.dart';
import 'package:yusal/service/push/push_setup.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/shared/model/models.dart';

/// Signing in and the signed-in account.

/// One way an account signs in: `google`, `apple`, `email` or `dev`, with
/// the address it uses ('' when unknown).
class SignInMethod {
  const SignInMethod(this.provider, this.email);
  final String provider;
  final String email;
}

abstract interface class AuthRepository {
  Account? get currentAccount;
  Future<void> requestCode(String phone);
  Future<Account> verify(String phone, String code, {String? displayName});
  Future<void> signOut();
  Future<Account> updateName(String name);

  /// The number shown when the caller shares it in a chat; "" clears it.
  Future<Account> updatePhone(String phone);

  /// Takes profiles and open demands down; cooperation records stay, shown
  /// with an anonymous name.
  Future<void> deleteAccount();
  Future<Account?> account(String id);
}

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => HttpAuthRepository(ref.watch(apiClientProvider)));

/// [AuthRepository] over yusal-api.
final class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this.api);
  final ApiClient api;

  @override
  Account? get currentAccount => api.currentAccount;

  /// Public account views, kept for [_fresh] so the many rows that name the
  /// same person (cards, comments, chats) ask the server once, not once
  /// each and again after every change.
  final _accounts = <String, Account?>{};
  final _accountAt = <String, DateTime>{};
  final _accountLoads = <String, Future<Account?>>{};
  static const _fresh = Duration(minutes: 1);

  @override
  Future<Account?> account(String id) async {
    if (id == api.currentId) return api.currentAccount;
    final at = _accountAt[id];
    if (at != null && DateTime.now().difference(at) < _fresh) {
      return _accounts[id];
    }
    return _accountLoads[id] ??= _loadAccount(id).whenComplete(() {
      _accountLoads.remove(id);
    });
  }

  Future<Account?> _loadAccount(String id) async {
    try {
      final a = accountFrom(await api.request('GET', '/client/accounts/$id')
          as Map<String, dynamic>);
      _accountAt[id] = DateTime.now();
      return _accounts[id] = a;
    } on ApiFailure catch (e) {
      if (e.code != ApiCodes.notFound) rethrow;
      _accountAt[id] = DateTime.now();
      return _accounts[id];
    }
  }

  /// Google / Apple sign-in: [idToken] comes from the native SDK. [name] is
  /// a fallback display name (Apple shares it only on the first sign-in).
  Future<Account> signInWithProvider(String provider, String idToken,
      {String? name}) async {
    final data = await api.request('POST', '/auth/oauth/$provider',
        body: {'id_token': idToken, if (name != null) 'name': name},
        auth: false) as Map<String, dynamic>;
    api.takeTokens(data);
    await api.saveTokens();
    final account = api.setMe(data['user'] as Map<String, dynamic>);
    api.notify();
    return account;
  }

  /// Email sign-in; [register] creates the account first. [name] is the
  /// display name of a new account (the server falls back to the email's
  /// local part).
  Future<Account> signInWithEmail(String email, String password,
      {bool register = false, String? name}) async {
    final data =
        await api.request('POST', register ? '/auth/register' : '/auth/login',
            body: {
              'email': email.trim(),
              'password': password,
              if (register && name != null && name.trim().isNotEmpty)
                'name': name.trim(),
            },
            auth: false) as Map<String, dynamic>;
    api.takeTokens(data);
    await api.saveTokens();
    final account = api.setMe(data['user'] as Map<String, dynamic>);
    api.notify();
    return account;
  }

  /// How the signed-in account signs in.
  Future<List<SignInMethod>> signInMethods() async =>
      _methods(await api.request('GET', '/client/auth/methods'));

  /// Adds a Google or Apple identity ([idToken] from the native SDK).
  Future<List<SignInMethod>> linkSignIn(
          String provider, String idToken) async =>
      _methods(await api.request('POST', '/client/auth/methods/$provider',
          body: {'id_token': idToken}));

  /// Removes one way to sign in; `email` drops the password.
  Future<List<SignInMethod>> unlinkSignIn(String provider) async =>
      _methods(await api.request('DELETE', '/client/auth/methods/$provider'));

  /// Turns email sign-in on, or changes its password.
  Future<List<SignInMethod>> setPassword(String password) async =>
      _methods(await api.request('PUT', '/client/auth/password',
          body: {'password': password}));

  static List<SignInMethod> _methods(Object? data) => [
        for (final m
            in (data as List? ?? const []).cast<Map<String, dynamic>>())
          SignInMethod(m['provider'] as String, m['email'] as String? ?? ''),
      ];

  @override
  Future<void> requestCode(String phone) async =>
      throw const ApiFailure(ApiCodes.invalidState, 'phone sign-in');

  @override
  Future<Account> verify(String phone, String code,
          {String? displayName}) async =>
      throw const ApiFailure(ApiCodes.invalidState, 'phone sign-in');

  @override
  Future<void> signOut() async {
    final token = PushSetup.token;
    if (token != null && api.accessToken != null) {
      try {
        await api.request('DELETE', '/client/devices', body: {'token': token});
      } on ApiFailure {
        // Offline: the server drops the token once FCM calls it dead.
      }
    }
    await api.forget();
  }

  @override
  Future<Account> updateName(String name) async {
    final a = api.setMe(await api.request('PATCH', '/client/auth/me',
        body: {'display_name': name}) as Map<String, dynamic>);
    api.notify();
    return a;
  }

  @override
  Future<Account> updatePhone(String phone) async {
    final a = api.setMe(
        await api.request('PATCH', '/client/auth/me', body: {'phone': phone})
            as Map<String, dynamic>);
    api.notify();
    return a;
  }

  @override
  Future<void> deleteAccount() async {
    await api.request('DELETE', '/client/auth/account');
    await api.forget();
  }
}
