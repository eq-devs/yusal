import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/features/shared/model/models.dart';

/// The caller's profiles, one of which signs the application.
final applyProfilesProvider = FutureProvider.autoDispose<List<ServiceProfile>>(
    (ref) => ref.watch(profileRepositoryProvider).myProfiles());
