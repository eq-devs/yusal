/// How a backend call fails: a stable [code] from [ApiCodes] the screens
/// turn into words, and the server's details for the log.
class ApiFailure implements Exception {
  const ApiFailure(this.code, [this.details = '']);

  /// Stable code; see [ApiCodes].
  final String code;
  final String details;
  @override
  String toString() =>
      'ApiFailure($code${details.isEmpty ? '' : ': $details'})';
}

/// The codes the screens tell apart. All but [notSignedIn] and [network]
/// are the server's own (yusal-api's `docs/api_codes.json`, copied to this
/// repo's `docs/`); [ApiClient] maps the rest of the server's codes onto
/// these. `test/platform/api_codes_test.dart` checks every server code
/// lands on one of them.
abstract final class ApiCodes {
  /// Client-side: no session, or the server refused the token.
  static const notSignedIn = 'NOT_SIGNED_IN';
  static const forbidden = 'FORBIDDEN';
  static const notFound = 'NOT_FOUND';
  static const invalidState = 'INVALID_STATE';
  static const invalidInput = 'INVALID_INPUT';
  static const notAccepting = 'NOT_ACCEPTING';
  static const ownDemand = 'OWN_DEMAND';
  static const blocked = 'BLOCKED';
  static const rateLimited = 'RATE_LIMITED';

  /// Client-side: no answer, an unreadable one, or a server fault.
  static const network = 'NETWORK';
  static const restricted = 'RESTRICTED';
  static const conflict = 'CONFLICT';
  static const emailTaken = 'EMAIL_TAKEN';
  static const badCredentials = 'INVALID_CREDENTIALS';
  static const providerTaken = 'PROVIDER_TAKEN';
  static const providerLinked = 'PROVIDER_LINKED';
  static const lastMethod = 'LAST_METHOD';
  static const noEmail = 'NO_EMAIL';
  static const notLinked = 'NOT_LINKED';
  static const voiceBusy = 'VOICE_BUSY';
  static const voiceUnavailable = 'VOICE_UNAVAILABLE';
  static const voiceUpstream = 'VOICE_UPSTREAM';
}
