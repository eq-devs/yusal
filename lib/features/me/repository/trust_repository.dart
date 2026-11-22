import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/features/me/model/me_json.dart';
import 'package:yusal/utils/json.dart';
import 'package:yusal/features/shared/model/admin_models.dart';
import 'package:yusal/features/shared/model/models.dart';

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

final moderationRepositoryProvider = Provider<ModerationRepository>(
    (ref) => HttpModerationRepository(ref.watch(apiClientProvider)));
final trustRepositoryProvider = Provider<TrustRepository>(
    (ref) => HttpTrustRepository(ref.watch(apiClientProvider)));
final feedbackRepositoryProvider = Provider<FeedbackRepository>(
    (ref) => HttpFeedbackRepository(ref.watch(apiClientProvider)));

/// [ModerationRepository] over yusal-api.
final class HttpModerationRepository implements ModerationRepository {
  HttpModerationRepository(this.api);
  final ApiClient api;

  @override
  Future<void> report(
      ReportTarget target, String targetId, String reason) async {
    await api.write('POST', '/client/reports',
        body: {'target': target.name, 'target_id': targetId, 'reason': reason});
  }

  @override
  Future<Appeal> fileAppeal(
          String target, String targetId, String text) async =>
      appealFrom(await api.write('POST', '/client/appeals',
              body: {'target': target, 'target_id': targetId, 'text': text})
          as Map<String, dynamic>);

  @override
  Future<List<Appeal>> myAppeals() async =>
      [for (final j in await api.getList('/client/appeals')) appealFrom(j)];
}

/// [TrustRepository] over yusal-api.
final class HttpTrustRepository implements TrustRepository {
  HttpTrustRepository(this.api);
  final ApiClient api;

  @override
  Future<Verification> requestVerification(
          String profileId, String phone, List<Uint8List> photos,
          {String note = ''}) async =>
      verificationFrom(await api.write(
          'POST', '/client/profiles/$profileId/verification', body: {
        'phone': phone,
        'note': note,
        'photos': photosJson(photos)
      }) as Map<String, dynamic>);

  @override
  Future<Verification?> myVerification(String profileId) async {
    final j =
        await api.request('GET', '/client/profiles/$profileId/verification');
    return j == null ? null : verificationFrom(j as Map<String, dynamic>);
  }

  @override
  Future<DemandAlert> demandAlert() async => alertFrom(
      await api.request('GET', '/client/demand-alert') as Map<String, dynamic>);

  @override
  Future<DemandAlert> saveDemandAlert(DemandAlert alert) async => alertFrom(
      await api.write('PUT', '/client/demand-alert', body: alertJson(alert))
          as Map<String, dynamic>);

  @override
  Future<NotificationSettings> notificationSettings() async =>
      settingsFrom(await api.request('GET', '/client/notification-settings')
          as Map<String, dynamic>);

  @override
  Future<NotificationSettings> saveNotificationSettings(
          NotificationSettings s) async =>
      settingsFrom(
          await api.write('PUT', '/client/notification-settings', body: {
        'muted': s.muted,
        'quiet_start': s.quietStart,
        'quiet_end': s.quietEnd,
      }) as Map<String, dynamic>);
}

/// [FeedbackRepository] over yusal-api.
final class HttpFeedbackRepository implements FeedbackRepository {
  HttpFeedbackRepository(this.api);
  final ApiClient api;

  @override
  Future<void> sendFeedback(
      {required String requestId,
      required String text,
      Map<String, String>? context}) async {
    await api.request('POST', '/client/feedback', body: {
      'request_id': requestId,
      'text': text,
      if (context != null) 'context': context,
    });
  }
}
