import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import 'package:yusal/services/api/api_client.dart';
import 'package:yusal/services/api/codec.dart';
import 'package:yusal/shared/model/admin_models.dart';
import 'package:yusal/shared/model/models.dart';

/// Reports and appeals, verification, alerts, push settings and feedback.

abstract interface class ModerationRepository {
  Future<void> report(ReportTarget target, String targetId, String reason);

  /// Asks a moderator to look again at a decision about the caller's own
  /// demand, profile, house (post) or account.
  Future<Appeal> fileAppeal(String target, String targetId, String text);
  Future<List<Appeal>> myAppeals();
}

/// Trust and reach for workers, and the user's push preferences.
abstract interface class TrustRepository {
  /// Sends a profile for verification: a phone and photos of past sites.
  Future<Verification> requestVerification(
      String profileId, String phone, List<Uint8List> photos,
      {String note = ''});
  Future<Verification?> myVerification(String profileId);
  Future<DemandAlert> demandAlert();
  Future<DemandAlert> saveDemandAlert(DemandAlert alert);
  Future<NotificationSettings> notificationSettings();
  Future<NotificationSettings> saveNotificationSettings(NotificationSettings s);
}

abstract interface class FeedbackRepository {
  /// Sends a short message to the team, signed in or not. [context] is what
  /// the app attached about itself (version, device, OS); null when the user
  /// switched it off. A retry with the same [requestId] is stored once.
  Future<void> sendFeedback(
      {required String requestId,
      required String text,
      Map<String, String>? context});
}

/// Overridden in `lib/app` with the one backend (the fake in tests).
final moderationRepositoryProvider = Provider<ModerationRepository>((ref) =>
    throw UnimplementedError('moderationRepositoryProvider is not overridden'));
final trustRepositoryProvider = Provider<TrustRepository>((ref) =>
    throw UnimplementedError('trustRepositoryProvider is not overridden'));
final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) =>
    throw UnimplementedError('feedbackRepositoryProvider is not overridden'));

/// [ModerationRepository] over yusal-api.
mixin HttpModerationRepository on ApiClient implements ModerationRepository {
  @override
  Future<void> report(
      ReportTarget target, String targetId, String reason) async {
    await write('POST', '/client/reports',
        body: {'target': target.name, 'target_id': targetId, 'reason': reason});
  }

  @override
  Future<Appeal> fileAppeal(
          String target, String targetId, String text) async =>
      appealFrom(await write('POST', '/client/appeals',
              body: {'target': target, 'target_id': targetId, 'text': text})
          as Map<String, dynamic>);

  @override
  Future<List<Appeal>> myAppeals() async =>
      [for (final j in await getList('/client/appeals')) appealFrom(j)];
}

/// [TrustRepository] over yusal-api.
mixin HttpTrustRepository on ApiClient implements TrustRepository {
  @override
  Future<Verification> requestVerification(
          String profileId, String phone, List<Uint8List> photos,
          {String note = ''}) async =>
      verificationFrom(await write(
          'POST', '/client/profiles/$profileId/verification', body: {
        'phone': phone,
        'note': note,
        'photos': photosJson(photos)
      }) as Map<String, dynamic>);

  @override
  Future<Verification?> myVerification(String profileId) async {
    final j = await request('GET', '/client/profiles/$profileId/verification');
    return j == null ? null : verificationFrom(j as Map<String, dynamic>);
  }

  @override
  Future<DemandAlert> demandAlert() async => alertFrom(
      await request('GET', '/client/demand-alert') as Map<String, dynamic>);

  @override
  Future<DemandAlert> saveDemandAlert(DemandAlert alert) async => alertFrom(
      await write('PUT', '/client/demand-alert', body: alertJson(alert))
          as Map<String, dynamic>);

  @override
  Future<NotificationSettings> notificationSettings() async =>
      settingsFrom(await request('GET', '/client/notification-settings')
          as Map<String, dynamic>);

  @override
  Future<NotificationSettings> saveNotificationSettings(
          NotificationSettings s) async =>
      settingsFrom(await write('PUT', '/client/notification-settings', body: {
        'muted': s.muted,
        'quiet_start': s.quietStart,
        'quiet_end': s.quietEnd,
      }) as Map<String, dynamic>);
}

/// [FeedbackRepository] over yusal-api.
mixin HttpFeedbackRepository on ApiClient implements FeedbackRepository {
  @override
  Future<void> sendFeedback(
      {required String requestId,
      required String text,
      Map<String, String>? context}) async {
    await request('POST', '/client/feedback', body: {
      'request_id': requestId,
      'text': text,
      if (context != null) 'context': context,
    });
  }
}
