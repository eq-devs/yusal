import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/services/api/api_client.dart';
import 'package:yusal/services/api/api_failure.dart';
import 'package:yusal/shared/model/models.dart';

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

/// Overridden in `lib/app` with the one backend (the fake in tests).
final authRepositoryProvider = Provider<AuthRepository>((ref) =>
    throw UnimplementedError('authRepositoryProvider is not overridden'));

/// [AuthRepository] over yusal-api.
mixin HttpAuthRepository on ApiClient implements AuthRepository {
  /// Google / Apple sign-in: [idToken] comes from the native SDK. [name] is
  /// a fallback display name (Apple shares it only on the first sign-in).
  Future<Account> signInWithProvider(String provider, String idToken,
      {String? name}) async {
    final data = await request('POST', '/auth/oauth/$provider',
        body: {'id_token': idToken, if (name != null) 'name': name},
        auth: false) as Map<String, dynamic>;
    takeTokens(data);
    await saveTokens();
    final account = setMe(data['user'] as Map<String, dynamic>);
    notify();
    unawaited(registerDevice());
    return account;
  }

  /// Email sign-in; [register] creates the account first. [name] is the
  /// display name of a new account (the server falls back to the email's
  /// local part).
  Future<Account> signInWithEmail(String email, String password,
      {bool register = false, String? name}) async {
    final data =
        await request('POST', register ? '/auth/register' : '/auth/login',
            body: {
              'email': email.trim(),
              'password': password,
              if (register && name != null && name.trim().isNotEmpty)
                'name': name.trim(),
            },
            auth: false) as Map<String, dynamic>;
    takeTokens(data);
    await saveTokens();
    final account = setMe(data['user'] as Map<String, dynamic>);
    notify();
    unawaited(registerDevice());
    return account;
  }

  /// How the signed-in account signs in.
  Future<List<SignInMethod>> signInMethods() async =>
      _methods(await request('GET', '/client/auth/methods'));

  /// Adds a Google or Apple identity ([idToken] from the native SDK).
  Future<List<SignInMethod>> linkSignIn(
          String provider, String idToken) async =>
      _methods(await request('POST', '/client/auth/methods/$provider',
          body: {'id_token': idToken}));

  /// Removes one way to sign in; `email` drops the password.
  Future<List<SignInMethod>> unlinkSignIn(String provider) async =>
      _methods(await request('DELETE', '/client/auth/methods/$provider'));

  /// Turns email sign-in on, or changes its password.
  Future<List<SignInMethod>> setPassword(String password) async =>
      _methods(await request('PUT', '/client/auth/password',
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
    final token = pushToken;
    if (token != null && accessToken != null) {
      try {
        await request('DELETE', '/client/devices', body: {'token': token});
      } on ApiFailure {
        // Offline: the server drops the token once FCM calls it dead.
      }
    }
    await forget();
  }

  @override
  Future<Account> updateName(String name) async {
    final a = setMe(
        await request('PATCH', '/client/auth/me', body: {'display_name': name})
            as Map<String, dynamic>);
    notify();
    return a;
  }

  @override
  Future<Account> updatePhone(String phone) async {
    final a = setMe(
        await request('PATCH', '/client/auth/me', body: {'phone': phone})
            as Map<String, dynamic>);
    notify();
    return a;
  }

  @override
  Future<void> deleteAccount() async {
    await request('DELETE', '/client/auth/account');
    final me = currentId;
    if (me != null) accounts.remove(me);
    await forget();
  }
}
