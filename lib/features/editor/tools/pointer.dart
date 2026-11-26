part of '../page.dart';

/// The plan's pointer events: one finger draws, edits, drags or taps with
/// the tool in hand; two fingers always pan and zoom.
extension _PlanPointer on _HouseEditorState {
  /// A mouse's middle or right button drags the plan in every tool, as in
  /// desktop CAD; only the left button draws and picks.
  bool _mousePans(PointerEvent e) =>
      e.kind == PointerDeviceKind.mouse && e.buttons & kPrimaryButton == 0;

  void planPointerDown(PointerDownEvent e, Size size) {
    if (_mousePans(e)) {
      mousePan = e.position;
      return;
    }
    if (pointers.isEmpty) {
      cancelledStroke = false;
      wallFromAdjust = false;
    }
    pointers.add(e.pointer);
    canvasSize = size;
    if (pointers.length == 1) {
      scheduleWallHold(e.localPosition, e.position, size);
    }
    downPoint = e.localPosition;
    gestureScreen = e.position;
    wallGesture = null;
    if (pointers.length == 1) {
      if (browse && beginUtilityGesture(e.localPosition, size)) {
        update(() {});
      } else if (browse && beginFurnitureGesture(e.localPosition, size)) {
        update(() {});
      } else if (tool == EditorTool.selectWall) {
        if (attachmentAt(e.localPosition, size) != null) {
          update(() {
            tool = EditorTool.drawWall;
            wallFromAdjust = true;
            wallGesture = WallGesture.draw;
            clearWallSelection();
            beginWallStroke(e.localPosition, size);
          });
        } else {
          // 改墙 selects walls even where
          // a door sits on them.
          wallGesture = WallGesture.tap;
        }
      } else if (tool == EditorTool.drawWall) {
        update(() => beginWallTool(e.localPosition, size));
      } else if (tool == EditorTool.editWall) {
        update(() {
          beginWallEdit(e.localPosition, size);
          if (wallGrip == null && beginOpeningDrag(e.localPosition, size)) {
            wallGrip = null;
            wallGesture = WallGesture.opening;
          } else {
            wallGesture = wallGrip != null ? WallGesture.edit : WallGesture.tap;
          }
          if (wallGrip != null) {
            closeWallMenu();
          }
        });
      } else if (spatialTool) {
        if (stamping) {
          // Held where it is touched;
          // by its middle when the
          // finger lands elsewhere.
          final w = interactionPainter().worldPoint(e.localPosition, size);
          final r = spatialPreview;
          final inside = r != null &&
              w.x >= r.left &&
              w.x <= r.right &&
              w.y >= r.bottom &&
              w.y <= r.top;
          stampGrab = inside
              ? Offset(w.x - r.left, w.y - r.bottom)
              : Offset(roomStamp!.w / 2, roomStamp!.d / 2);
        } else {
          spatialStart = null;
        }
        update(() => updateSpatial(e.localPosition, size));
      } else {
        update(() => beginDrag(e.localPosition, size));
      }
    }
    if (pointers.length > 1) {
      cancelledStroke = true;
      update(() {
        stroke.clear();
        spatialStart = null;
        spatialPreview = null;
        cancelDrag();
      });
      lastPoint = null;
      return;
    }
    if (!browse &&
        !spatialTool &&
        tool != EditorTool.editWall &&
        tool != EditorTool.selectWall &&
        tool != EditorTool.drawWall &&
        tool != EditorTool.placeOpening &&
        tool != EditorTool.resize &&
        tool != EditorTool.wall &&
        tool != EditorTool.opening &&
        tool != EditorTool.grid &&
        tool != EditorTool.measure &&
        tool != EditorTool.placeFurniture &&
        tool != EditorTool.placeUtility) {
      update(() => record(e.localPosition, size));
    }
  }

  void planPointerMove(PointerMoveEvent e, Size size) {
    if (mousePan != null) {
      panCanvas(e.position - mousePan!);
      mousePan = e.position;
      return;
    }
    trackLoupe(e);
    if (wallHoldScreen != null && (e.position - wallHoldScreen!).distance > 8) {
      wallHoldTimer?.cancel();
    }
    final single = !cancelledStroke && pointers.length == 1;
    if (single && utilityDown != null) {
      update(() => previewUtility(e.localPosition, size));
      return;
    }
    if (single && furnitureGrip != null) {
      update(() => previewFurniture(e.localPosition, size));
      return;
    }
    if (single &&
        wallGesture == WallGesture.fromWall &&
        gestureScreen != null &&
        (e.position - gestureScreen!).distance > 8) {
      final wall = pressedWall!;
      update(() {
        if (pullWallFrom(wall, downPoint!, size)) {
          wallGesture = WallGesture.draw;
          wallHoldTimer?.cancel();
          previewWallStroke(e.localPosition, size);
        } else {
          wallGesture = WallGesture.pan;
          panCanvas(e.position - gestureScreen!);
        }
      });
      return;
    }
    if (single &&
        (wallGesture == WallGesture.tap || wallGesture == WallGesture.pan)) {
      if (wallGesture == WallGesture.tap &&
          gestureScreen != null &&
          (e.position - gestureScreen!).distance > 8) {
        wallGesture = WallGesture.pan;
        wallHoldTimer?.cancel();
        panCanvas(e.position - gestureScreen!);
      } else if (wallGesture == WallGesture.pan) {
        panCanvas(e.delta);
      }
    } else if (single && wallGesture == WallGesture.edit) {
      update(() => previewWallEdit(e.localPosition, size));
    } else if (single && wallGesture == WallGesture.draw) {
      update(() => previewWallStroke(e.localPosition, size));
    }
    if (spatialTool && !cancelledStroke && pointers.length == 1) {
      update(() => updateSpatial(e.localPosition, size));
    }
    if (!cancelledStroke &&
        pointers.length == 1 &&
        (draggingAxis != null || draggingOpening != null)) {
      update(() => previewDrag(e.localPosition, size));
    }
    if (!browse &&
        !spatialTool &&
        tool != EditorTool.editWall &&
        tool != EditorTool.selectWall &&
        tool != EditorTool.drawWall &&
        tool != EditorTool.placeOpening &&
        tool != EditorTool.resize &&
        tool != EditorTool.wall &&
        tool != EditorTool.opening &&
        tool != EditorTool.grid &&
        tool != EditorTool.measure &&
        tool != EditorTool.placeFurniture &&
        tool != EditorTool.placeUtility &&
        !cancelledStroke &&
        pointers.length == 1) {
      update(() => record(e.localPosition, size));
    }
  }

  void planPointerCancel(PointerCancelEvent e, Size size) {
    if (mousePan != null) {
      mousePan = null;
      return;
    }
    loupeAt = null;
    pointers.remove(e.pointer);
    update(() {
      stroke.clear();
      spatialStart = null;
      spatialEnd = null;
      spatialPreview = null;
      cancelDrag();
    });
    lastPoint = null;
  }

  void planPointerUp(PointerUpEvent e, Size size) {
    if (mousePan != null) {
      mousePan = null;
      return;
    }
    if (loupeAt != null) {
      update(() => loupeAt = null);
    }
    wallHoldTimer?.cancel();
    final gesture = wallGesture;
    wallGesture = null;
    final single = !cancelledStroke && pointers.length == 1;
    if (single && gesture == WallGesture.pan) {
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (single && utilityDown != null) {
      final moved = finishUtility();
      pointers.remove(e.pointer);
      downPoint = null;
      if (!moved) {
        tapObject(e.localPosition, size);
      }
      return;
    }
    if (single && furnitureGrip != null) {
      final tap =
          furnitureDraft == null && furnitureGrip != FurnitureGrip.rotate;
      finishFurniture();
      pointers.remove(e.pointer);
      final at = downPoint;
      downPoint = null;
      // A tap on the selected piece
      // may mean the door beside it.
      if (tap && at != null) {
        tapObject(e.localPosition, size);
      }
      return;
    }
    final tapped = single &&
        downPoint != null &&
        (downPoint! - e.localPosition).distance * canvasZoom < 8;
    if (tapped && tool == EditorTool.placeFurniture) {
      placeFurnitureAt(e.localPosition, size);
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (tapped && tool == EditorTool.placeUtility) {
      placeUtilityAt(e.localPosition, size);
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (tapped && tool == EditorTool.measure) {
      addMeasurePoint(e.localPosition, size);
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (single && gesture == WallGesture.opening && !dragAttempted) {
      final opening = draggingOpening;
      update(cancelDrag);
      if (opening != null) {
        selectOpening(opening.opening);
      }
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (single && gesture == WallGesture.edit) {
      final moved = editPreviewStart != null;
      finishWallEdit();
      if (!moved) {
        update(() => reopenWallMenu(e.localPosition, size));
      }
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (tool == EditorTool.drawWall &&
        single &&
        (gesture == WallGesture.tap || gesture == WallGesture.fromWall)) {
      wallToolTap(e.localPosition, size);
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (tool == EditorTool.drawWall &&
        single &&
        gesture == WallGesture.draw &&
        !wallFromAdjust &&
        strokeFromAttachment &&
        drawingEnd == null) {
      // A plus sits on a wall: tapping it
      // selects that wall; only a drag
      // draws a new one.
      update(cancelDrag);
      wallToolTap(e.localPosition, size);
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (tool == EditorTool.drawWall && single && gesture == WallGesture.draw) {
      final tapFromAdjust = wallFromAdjust &&
          downPoint != null &&
          (downPoint! - e.localPosition).distance * canvasZoom < 8;
      if (tapFromAdjust) {
        update(() {
          cancelDrag();
          tool = EditorTool.selectWall;
        });
        tapObject(e.localPosition, size);
      } else {
        finishWallStroke();
      }
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (tool == EditorTool.placeOpening &&
        !cancelledStroke &&
        pointers.length == 1 &&
        downPoint != null &&
        (downPoint! - e.localPosition).distance * canvasZoom < 8) {
      final box = canvasKey.currentContext!.findRenderObject()! as RenderBox;
      previewOpening(placingOpening!, box.localToGlobal(e.localPosition));
      final args = openingDrop;
      derive();
      if (args != null) {
        placeOpening(args);
      } else {
        update(() {});
      }
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (spatialTool && !cancelledStroke && pointers.length == 1) {
      // A stamp stays until 放下.
      if (stamping) {
        update(() {});
      } else {
        finishSpatial();
      }
      pointers.remove(e.pointer);
      downPoint = null;
      return;
    }
    if (dragAttempted && !cancelledStroke && pointers.length == 1) {
      final kind = dragKind;
      final arguments = dragArguments;
      final valid = dragValid;
      final message = placementHint;
      cancelDrag();
      final wall = selectedWall;
      if (valid &&
          kind == 'MoveLocalWall' &&
          wall != null &&
          arguments != null) {
        final pair = wallRooms(wall);
        final offset = (arguments['pos'] as int) - wall.axis.pos;
        if (pair != null && offset != 0) {
          final trial = prepareWallTrial(offset > 0 ? pair.$1 : pair.$2,
              offset > 0 ? pair.$2 : pair.$1, offset.abs(), null);
          if (!trial.ok) {
            update(() {});
            notify(tr3(
                '无法预览此次移墙',
                'Бұл өзгерісті алдын ала көру мүмкін емес',
                'Не удалось построить предпросмотр',
                'Cannot preview this wall move',
                ky: 'Алдын ала көрүү мүмкүн эмес',
                uz: 'Oldindan koʻrib boʻlmaydi'));
          }
          pointers.remove(e.pointer);
          lastPoint = null;
          downPoint = null;
          return;
        }
      }
      if (valid && kind != null && arguments != null) {
        action(kind, arguments);
      } else {
        update(() {});
        if (message != null) {
          notify(message);
        }
      }

      if (tool == EditorTool.wall) {
        update(() {
          tool = EditorTool.browse;
          selectedWall = null;
          placementHint = null;
        });
      }
      pointers.remove(e.pointer);
      lastPoint = null;
      downPoint = null;
      return;
    }
    if ((browse ||
            tool == EditorTool.editWall ||
            tool == EditorTool.selectWall ||
            tool == EditorTool.opening ||
            tool == EditorTool.grid) &&
        !cancelledStroke &&
        pointers.length == 1 &&
        downPoint != null &&
        (downPoint! - e.localPosition).distance * canvasZoom < 8) {
      tapObject(e.localPosition, size);
    }
    if (tool == EditorTool.room &&
        !browse &&
        !cancelledStroke &&
        pointers.length == 1 &&
        stroke.isNotEmpty) {
      final cells = List.of(stroke);
      stroke.clear();
      action(erase ? 'EraseCells' : 'PaintCells',
          {'floorId': floor.id, 'cells': cells, 'roomType': brush});
    }
    pointers.remove(e.pointer);
    lastPoint = null;
  }
}
