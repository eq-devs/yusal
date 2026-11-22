import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/service/api/api_client.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/service/api/codec.dart';
import 'package:yusal/features/shared/model/models.dart';

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

final profileRepositoryProvider = Provider<ProfileRepository>(
    (ref) => HttpProfileRepository(ref.watch(apiClientProvider)));

/// [ProfileRepository] over yusal-api.
final class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this.api);
  final ApiClient api;

  @override
  Future<List<ServiceProfile>> myProfiles() async {
    if (api.currentId == null) throw const ApiFailure(ApiCodes.notSignedIn);
    return [
      for (final j in await api.getList('/client/me/profiles')) profileFrom(j)
    ];
  }

  @override
  Future<ServiceProfile?> profile(String id) async {
    final j = await api.maybe('/client/profiles/$id');
    if (j == null) return null;
    final p = profileFrom(j);
    await api.loadNames([p.ownerId]);
    return p;
  }

  @override
  Future<List<ServiceProfile>> profilesOf(String accountId) async => [
        for (final j
            in await api.getList('/client/api.accounts/$accountId/profiles'))
          profileFrom(j)
      ];

  @override
  Future<List<ServiceProfile>> searchProfiles(ProfileFilter f) async {
    final list = [
      for (final j in await api.getList('/client/profiles', query: {
        if (f.kind != null) 'kind': f.kind!.name,
        if (f.trade != null) 'trade': f.trade!,
        if (f.region != null) 'region': f.region!,
        if (f.availableNow) 'available_now': 'true',
        if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
      }))
        profileFrom(j)
    ];
    await api.loadNames(list.map((p) => p.ownerId));
    return list;
  }

  @override
  Future<ServiceProfile> saveProfile(ServiceProfile p) =>
      _profile(api.write('POST', '/client/profiles', body: profileJson(p)));

  @override
  Future<ServiceProfile> confirmAvailability(String profileId) => _profile(
      api.write('POST', '/client/profiles/$profileId/confirm-availability'));

  @override
  Future<ProfileStats> stats(String profileId) async =>
      statsFrom(await api.request('GET', '/client/profiles/$profileId/stats')
          as Map<String, dynamic>);

  @override
  Future<Set<String>> favourites() async {
    if (api.currentId == null) return {};
    return {
      for (final id
          in await api.request('GET', '/client/me/favourites') as List)
        id as String
    };
  }

  @override
  Future<void> toggleFavourite(String id) async {
    await api.write('POST', '/client/favourites/$id/toggle');
  }

  Future<ServiceProfile> _profile(Future<dynamic> f) async =>
      profileFrom(await f as Map<String, dynamic>);
}
