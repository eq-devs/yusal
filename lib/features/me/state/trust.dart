import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/me/repository/trust_repository.dart';
import 'package:yusal/features/shared/model/admin_models.dart';

/// Appeals I filed.
final myAppealsProvider = FutureProvider.autoDispose<List<Appeal>>(
    (ref) => ref.watch(moderationRepositoryProvider).myAppeals());

/// My push preferences.
final notificationSettingsProvider =
    FutureProvider.autoDispose<NotificationSettings>(
        (ref) => ref.watch(trustRepositoryProvider).notificationSettings());

/// What new demands I am alerted to.
final demandAlertProvider = FutureProvider.autoDispose<DemandAlert>(
    (ref) => ref.watch(trustRepositoryProvider).demandAlert());

/// A profile's verification request, by profile id.
final myVerificationProvider = FutureProvider.autoDispose
    .family<Verification?, String>((ref, profileId) =>
        ref.watch(trustRepositoryProvider).myVerification(profileId));
