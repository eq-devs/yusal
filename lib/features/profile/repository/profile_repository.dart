import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/services/api/api_client.dart';
import 'package:yusal/services/api/api_failure.dart';
import 'package:yusal/services/api/codec.dart';
import 'package:yusal/shared/model/models.dart';

/// Workers' and teams' service profiles, and favourites.

abstract interface class ProfileRepository {
  Future<List<ServiceProfile>> myProfiles();
  Future<ServiceProfile?> profile(String id);
  Future<List<ServiceProfile>> profilesOf(String accountId);
  Future<List<ServiceProfile>> searchProfiles(ProfileFilter filter);

  /// Creates when [profile.id] is empty, else updates the caller's own.
  Future<ServiceProfile> saveProfile(ServiceProfile profile);

  /// "Still taking work": refreshes the confirmation time.
  Future<ServiceProfile> confirmAvailability(String profileId);
  Future<ProfileStats> stats(String profileId);
  Future<Set<String>> favourites();
  Future<void> toggleFavourite(String id);
}

/// Overridden in `lib/app` with the one backend (the fake in tests).
final profileRepositoryProvider = Provider<ProfileRepository>((ref) =>
    throw UnimplementedError('profileRepositoryProvider is not overridden'));

/// [ProfileRepository] over yusal-api.
mixin HttpProfileRepository on ApiClient implements ProfileRepository {
  @override
  Future<List<ServiceProfile>> myProfiles() async {
    if (currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    return [
      for (final j in await getList('/client/me/profiles')) profileFrom(j)
    ];
  }

  @override
  Future<ServiceProfile?> profile(String id) async {
    final j = await maybe('/client/profiles/$id');
    if (j == null) return null;
    final p = profileFrom(j);
    await loadNames([p.ownerId]);
    return p;
  }

  @override
  Future<List<ServiceProfile>> profilesOf(String accountId) async => [
        for (final j in await getList('/client/accounts/$accountId/profiles'))
          profileFrom(j)
      ];

  @override
  Future<List<ServiceProfile>> searchProfiles(ProfileFilter f) async {
    final list = [
      for (final j in await getList('/client/profiles', query: {
        if (f.kind != null) 'kind': f.kind!.name,
        if (f.trade != null) 'trade': f.trade!,
        if (f.region != null) 'region': f.region!,
        if (f.availableNow) 'available_now': 'true',
        if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
      }))
        profileFrom(j)
    ];
    await loadNames(list.map((p) => p.ownerId));
    return list;
  }

  @override
  Future<ServiceProfile> saveProfile(ServiceProfile p) =>
      _profile(write('POST', '/client/profiles', body: profileJson(p)));

  @override
  Future<ServiceProfile> confirmAvailability(String profileId) => _profile(
      write('POST', '/client/profiles/$profileId/confirm-availability'));

  @override
  Future<ProfileStats> stats(String profileId) async =>
      statsFrom(await request('GET', '/client/profiles/$profileId/stats')
          as Map<String, dynamic>);

  @override
  Future<Set<String>> favourites() async {
    if (currentId == null) return {};
    return {
      for (final id in await request('GET', '/client/me/favourites') as List)
        id as String
    };
  }

  @override
  Future<void> toggleFavourite(String id) async {
    await write('POST', '/client/favourites/$id/toggle');
  }

  Future<ServiceProfile> _profile(Future<dynamic> f) async =>
      profileFrom(await f as Map<String, dynamic>);
}
