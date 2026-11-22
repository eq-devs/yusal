import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yusal/services/api/api_client.dart';
import 'package:yusal/services/api/api_failure.dart';
import 'package:yusal/services/api/codec.dart';
import 'package:yusal/shared/model/models.dart';

/// Frozen design extracts (snapshots) and cloud backups of designs.

abstract interface class SnapshotRepository {
  Future<DesignSnapshot> saveSnapshot(DesignSnapshot snapshot);
  Future<DesignSnapshot?> snapshot(String id,
      {String? postId, String? demandId});
}

/// Result of comparing a local design with its cloud backup.
enum BackupState { none, inSync, localNewer, cloudNewer, diverged }

abstract interface class BackupRepository {
  Future<List<BackupRecord>> backups();
  Future<BackupRecord?> backup(String projectId);
  Future<BackupRecord> upload(
      {required String projectId,
      required String name,
      required String houseText,
      required String designUpdatedAt,
      String? expectedPreviousUpdatedAt});
}

/// Overridden in `lib/app` with the one backend (the fake in tests).
final snapshotRepositoryProvider = Provider<SnapshotRepository>((ref) =>
    throw UnimplementedError('snapshotRepositoryProvider is not overridden'));
final backupRepositoryProvider = Provider<BackupRepository>((ref) =>
    throw UnimplementedError('backupRepositoryProvider is not overridden'));

/// [SnapshotRepository] over yusal-api.
mixin HttpSnapshotRepository on ApiClient implements SnapshotRepository {
  @override
  Future<DesignSnapshot> saveSnapshot(DesignSnapshot s) async {
    final data = await request('POST', '/client/snapshots', body: {
      'project_id': s.projectId,
      'project_name': s.projectName,
      'design_updated_at': s.designUpdatedAt,
      'stages': s.stages,
      'lines': [for (final l in s.lines) snapshotQtyJson(l)],
      'summary': s.summary,
      if (s.preview != null) 'preview': base64Encode(s.preview!),
      if (s.planJson != null) 'plan_json': s.planJson,
    });
    final saved = snapshotFrom(data as Map<String, dynamic>);
    notify();
    return saved;
  }

  @override
  Future<DesignSnapshot?> snapshot(String id,
      {String? postId, String? demandId}) async {
    if (demandId != null) {
      final j = await maybe('/client/demands/$demandId/snapshot');
      return j == null ? null : snapshotFrom(j);
    }
    try {
      return snapshotFrom(await request('GET', '/client/snapshots/$id')
          as Map<String, dynamic>);
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }
}

/// [BackupRepository] over yusal-api.
mixin HttpBackupRepository on ApiClient implements BackupRepository {
  static BackupRecord _backup(Map<String, dynamic> j) => BackupRecord(
      projectId: j['project_id'] as String,
      name: j['name'] as String? ?? '',
      houseText: j['house_text'] as String,
      backedUpAt: DateTime.parse(j['backed_up_at'] as String),
      designUpdatedAt: j['design_updated_at'] as String);

  @override
  Future<List<BackupRecord>> backups() async => [
        for (final b in await request('GET', '/client/backups') as List)
          _backup(b as Map<String, dynamic>)
      ];

  @override
  Future<BackupRecord?> backup(String projectId) async {
    try {
      return _backup(await request(
              'GET', '/client/backups/${Uri.encodeComponent(projectId)}')
          as Map<String, dynamic>);
    } on ApiFailure catch (e) {
      if (e.code == ApiCodes.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<BackupRecord> upload(
      {required String projectId,
      required String name,
      required String houseText,
      required String designUpdatedAt,
      String? expectedPreviousUpdatedAt}) async {
    final data = await request(
        'PUT', '/client/backups/${Uri.encodeComponent(projectId)}',
        body: {
          'name': name,
          'house_text': houseText,
          'design_updated_at': designUpdatedAt,
          if (expectedPreviousUpdatedAt != null)
            'expected_previous_updated_at': expectedPreviousUpdatedAt,
        });
    notify();
    return _backup(data as Map<String, dynamic>);
  }
}
