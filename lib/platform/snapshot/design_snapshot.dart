import '../../core/analysis/cost_estimate.dart';
import '../../core/document/house_document.dart';
import '../../core/serialization/house_codec.dart';
import '../../core/geometry/derived_house.dart';
import '../domain/models.dart';

/// Builds the frozen design extract attached to a contract demand. It only
/// reads the design core (geometry and the takeoff behind the budget); the
/// design and the .house format are left untouched. Pure Dart.

/// Stages a demand can be published for, in building order.
const snapshotStages = [
  'found',
  'walls',
  'roof',
  'openings',
  'mep',
  'finish',
  'site'
];

class DesignExtract {
  const DesignExtract(
      {required this.lines,
      required this.buildingArea,
      required this.width,
      required this.depth,
      required this.floors,
      this.rooms = 0,
      this.estimatedCost});

  /// Quantities of the chosen stages, measured from the design.
  final List<QtyItem> lines;

  /// m² over all floors.
  final double buildingArea;

  /// Footprint, mm.
  final int width, depth;
  final int floors;

  /// Rooms over all floors and the estimate's grand total in tenge.
  final int rooms;
  final int? estimatedCost;
}

/// Quantities for [stages] (all stages when empty). [nameOf] names a takeoff
/// line key in the interface language. Lines whose quantity is only a rule
/// of thumb are marked as manual so nobody reads them as measured.
DesignExtract extractDesign(HouseDocument doc, List<String> stages,
    {String Function(String key)? nameOf}) {
  final derived = deriveHouse(doc);
  final estimate = estimateCost(doc, derived, currency: Currency.kzt);
  final wanted = stages.isEmpty ? snapshotStages.toSet() : stages.toSet();
  final lines = [
    for (final l in estimate.lines)
      if (wanted.contains(l.stage))
        QtyItem(
            name: l.custom ? (l.name ?? l.key) : (nameOf?.call(l.key) ?? l.key),
            quantity: _round(l.quantity),
            unit: l.unit,
            source:
                l.estimated || l.custom ? QtySource.manual : QtySource.design,
            stage: l.stage)
  ];
  return DesignExtract(
      lines: lines,
      buildingArea: estimate.buildingArea,
      width: doc.footprint.width,
      depth: doc.footprint.depth,
      floors: doc.floors.length,
      rooms: doc.floors.fold(0, (n, f) => n + f.rooms.length),
      estimatedCost: estimate.total.round());
}

double _round(double v) => (v * 100).roundToDouble() / 100;

/// The publish-time snapshot, before the backend gives it an id.
DesignSnapshot buildSnapshot(
        {required String projectId,
        required HouseDocument doc,
        required List<String> stages,
        required List<QtyItem> lines,
        required String summary,
        List<int>? preview}) =>
    DesignSnapshot(
        id: '',
        ownerId: '',
        projectId: projectId,
        projectName: doc.meta.name,
        designUpdatedAt: doc.meta.updatedAt,
        extractedAt: DateTime.now().toUtc(),
        stages: stages,
        lines: lines,
        summary: summary,
        preview: preview,
        planJson: encodeHouse(HouseDocument(
          schemaVersion: doc.schemaVersion,
          meta: doc.meta,
          defaults: doc.defaults,
          footprint: doc.footprint,
          axes: doc.axes,
          floors: doc.floors,
          roof: doc.roof,
          mainEntranceOpeningId: doc.mainEntranceOpeningId,
        )));
