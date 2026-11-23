import 'package:yusal/features/editor/engine/core/commands/extras_commands.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';

/// What a house can hold, for a caller choosing among them: every kind of
/// thing by the name commands take, and for furniture the size a piece
/// gets when none is given (millimetres).
Map<String, Object?> describeObjects() => {
      'roomTypes': [for (final v in RoomType.values) v.name],
      'openingKinds': [for (final v in OpeningKind.values) v.name],
      'stairTypes': [for (final v in StairType.values) v.name],
      'furniture': [
        for (final k in FurnitureKind.values)
          if (furnitureDefaults[k] case (final w, final d, final h, final z))
            {
              'kind': k.name,
              'width': w,
              'depth': d,
              'height': h,
              'elevation': z,
            }
          else
            {'kind': k.name}
      ],
      'utilityKinds': [for (final v in UtilityKind.values) v.name],
      'siteKinds': [for (final v in SiteKind.values) v.name],
      'sleeveKinds': [for (final v in SleeveKind.values) v.name],
      'layerMaterials': [for (final v in LayerMaterial.values) v.name],
      'issueLevels': [for (final v in IssueLevel.values) v.name],
      'stageStatuses': [for (final v in StageStatus.values) v.name],
      'fuels': [for (final v in FuelKind.values) v.name],
      'currencies': [for (final v in Currency.values) v.name],
    };
