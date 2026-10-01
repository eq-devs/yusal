import '../document/house_document.dart';
import 'derived_house.dart';
import 'floor_base.dart';

/// Editing checks need 2D hosts and opening bounds, not a full 3D mesh.
List<OpeningPlacement> documentOpenings(HouseDocument doc, {String? floorId}) =>
    [
      for (final floor
          in doc.floors.where((f) => floorId == null || f.id == floorId))
        ...deriveOpenings(doc, deriveFloorBase(doc, floor.id), floor.id),
    ];
