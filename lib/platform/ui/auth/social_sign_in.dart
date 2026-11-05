import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Native Google / Apple sign-in. Each returns the provider's ID token for
/// the backend to verify, or null when the user cancelled.
///
/// Client IDs come from `--dart-define`:
///   GOOGLE_SERVER_CLIENT_ID  the Web client ID; the backend accepts tokens
///                            issued to it (Android needs it to get a token)
///   GOOGLE_IOS_CLIENT_ID     the iOS client ID (iOS also needs its reversed
///                            form as a URL scheme in Info.plist)
abstract final class SocialSignIn {
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static bool get googleAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get appleAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool _googleReady = false;

  static Future<({String idToken, String? name})?> google() async {
    final g = GoogleSignIn.instance;
    if (!_googleReady) {
      await g.initialize(
          clientId: _iosClientId.isEmpty ? null : _iosClientId,
          serverClientId: _serverClientId.isEmpty ? null : _serverClientId);
      _googleReady = true;
    }
    try {
      final account = await g.authenticate();
      final token = account.authentication.idToken;
      if (token == null) return null;
      return (idToken: token, name: account.displayName);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  static Future<({String idToken, String? name})?> apple() async {
    try {
      final c = await SignInWithApple.getAppleIDCredential(scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ]);
      final token = c.identityToken;
      if (token == null) return null;
      final name = [c.givenName, c.familyName]
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
      return (idToken: token, name: name.isEmpty ? null : name);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
  }
}
