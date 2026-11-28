import 'dart:convert';

import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/utils/json.dart';

/// Backup models to and from yusal-api JSON.

/// Snapshots keep their quantity lines in their own shape.
Map<String, dynamic> snapshotQtyJson(QtyItem q) => {
      'name': q.name,
      'quantity': q.quantity,
      'unit': q.unit,
      'source': q.source.name,
      if (q.stage != null) 'stage': q.stage,
    };

QtyItem _snapshotQty(Map<String, dynamic> j) => QtyItem(
    name: j['name'] as String,
    quantity: (j['quantity'] as num?)?.toDouble(),
    unit: j['unit'] as String? ?? '',
    source: QtySource.values.byName(j['source'] as String),
    stage: j['stage'] as String?);

DesignSnapshot snapshotFrom(Map<String, dynamic> j) => DesignSnapshot(
    id: j['id'] as String,
    ownerId: j['owner_id'] as String,
    projectId: j['project_id'] as String? ?? '',
    projectName: j['project_name'] as String? ?? '',
    designUpdatedAt: j['design_updated_at'] as String,
    extractedAt: DateTime.parse(j['extracted_at'] as String),
    stages: jsonStrings(j['stages']),
    lines: [for (final l in jsonMaps(j['lines'])) _snapshotQty(l)],
    summary: j['summary'] as String? ?? '',
    preview: j['preview'] == null ? null : base64Decode(j['preview'] as String),
    planJson: j['plan_json'] as String?);
