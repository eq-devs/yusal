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

abstract final class ApiCodes {
  static const notSignedIn = 'NOT_SIGNED_IN';
  static const badCode = 'BAD_CODE';
  static const badPhone = 'BAD_PHONE';
  static const forbidden = 'FORBIDDEN';
  static const notFound = 'NOT_FOUND';
  static const invalidState = 'INVALID_STATE';
  static const invalidInput = 'INVALID_INPUT';
  static const notAccepting = 'NOT_ACCEPTING';
  static const ownDemand = 'OWN_DEMAND';
  static const blocked = 'BLOCKED';
  static const rateLimited = 'RATE_LIMITED';
  static const network = 'NETWORK';
  static const restricted = 'RESTRICTED';
  static const conflict = 'CONFLICT';
  static const emailTaken = 'EMAIL_TAKEN';
  static const badCredentials = 'INVALID_CREDENTIALS';
  static const providerTaken = 'PROVIDER_TAKEN';
  static const providerLinked = 'PROVIDER_LINKED';
  static const lastMethod = 'LAST_METHOD';
  static const noEmail = 'NO_EMAIL';
}
