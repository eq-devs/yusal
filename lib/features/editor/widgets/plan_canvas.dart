part of '../page.dart';

extension _PlanCanvas on _HouseEditorState {
  /// The plan drawing with all editing gestures; sized by its sheet.
  Widget planCanvas() => ListenableBuilder(
      listenable: canvasZoomChanged,
      builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            canvasSize = size;
            final displayBase = spatialBase ?? base;
            final displayRooms = spatialDocument?.floors
                    .firstWhere((f) => f.id == floor.id)
                    .rooms ??
                floor.rooms;
            final displayOpenings = spatialDocument == null
                ? derived.floors[floorIndex].openings
                : deriveOpenings(spatialDocument!, displayBase, floor.id);
            return InteractiveViewer(
                transformationController: canvasTransform,
                // On a phone the drawing runs on under the frosted bars.
                clipBehavior: phone ? Clip.none : Clip.hardEdge,
                boundaryMargin: const EdgeInsets.all(200),
                panEnabled: ((browse ||
                            tool == EditorTool.measure ||
                            tool == EditorTool.placeFurniture ||
                            tool == EditorTool.placeUtility) &&
                        draggingOpening == null &&
                        furnitureGrip == null &&
                        utilityDown == null) ||
                    pointers.length > 1,
                minScale: 0.4,
                maxScale: 5,
                child: MouseRegion(
                    cursor: canvasCursor,
                    onHover: (e) {
                      final cursor = hoverCursor(e.localPosition, size);
                      if (cursor != canvasCursor) {
                        update(() => canvasCursor = cursor);
                      }
                    },
                    child: Listener(
                        onPointerDown: (e) => planPointerDown(e, size),
                        onPointerMove: (e) => planPointerMove(e, size),
                        onPointerCancel: (e) => planPointerCancel(e, size),
                        onPointerUp: (e) => planPointerUp(e, size),
                        child: DragTarget<OpeningKind>(
                            onWillAcceptWithDetails: (_) => true,
                            onMove: (details) => update(() => previewOpening(
                                details.data,
                                details.offset +
                                    _HouseEditorState.openingDropPoint)),
                            onLeave: (_) => update(() {
                                  openingDrop = null;
                                  placementHint = null;
                                  derive();
                                }),
                            onAcceptWithDetails: (details) {
                              previewOpening(
                                  details.data,
                                  details.offset +
                                      _HouseEditorState.openingDropPoint);
                              final arguments = openingDrop;
                              final message = placementHint;
                              openingDrop = null;
                              placementHint = null;
                              derive();
                              if (arguments != null) {
                                placeOpening(arguments);
                              } else {
                                update(() {});
                                notify(message == null ||
                                        message == dragOntoWallHint
                                    ? tr3(
                                        '没有放上墙：请把${openingNames[details.data]}拖到墙上再松手',
                                        '${openingNames[details.data]} қабырғаға қойылмады: оны қабырғаға апарып жіберіңіз',
                                        'Не на стене: ${openingNames[details.data]}. Перетащите на стену и отпустите',
                                        'Not on a wall: ${openingNames[details.data]}. Drag it onto a wall and release',
                                        ky: 'Дубалда эмес: ${openingNames[details.data]}. Аны дубалга сүйрөп барып коё бериңиз',
                                        uz: 'Devorda emas: ${openingNames[details.data]}. Uni devorga sudrab, qoʻyib yuboring')
                                    : message);
                              }
                            },
                            // The plan in its own layer: panning moves the
                            // cached picture, and a drag repaints only the
                            // overlay above it unless the plan changed.
                            builder: (context, candidates, rejected) {
                              final plan = FloorPlanPainter(
                                  layered: true,
                                  areaBasis: history.present.extras.areaBasis,
                                  displayBase,
                                  {
                                    for (final r in displayRooms)
                                      r.id: displayRoomName(r)
                                  },
                                  {
                                    // A room with a use is tinted by it, lightly: the
                                    // sheet stays a drawing, and uses read at a glance.
                                    for (final r in displayRooms)
                                      if (r.type != RoomType.custom)
                                        r.id: Color.lerp(
                                            Tokens.of(context).room,
                                            roomColors[r.type],
                                            0.42)!
                                  },
                                  viewportInsets: canvasInsets,
                                  showGaps: history.present.floors[floorIndex].explicitWalls &&
                                      drawingEnd == null,
                                  openings: displayOpenings,
                                  below: floorIndex > 0 && showBelow
                                      ? derived.floors[floorIndex - 1].base
                                      : null,
                                  belowOpenings: [
                                    if (floorIndex > 0)
                                      for (final s in derived
                                          .floors[floorIndex - 1].stairs)
                                        s.opening
                                  ],
                                  belowLabel: tr3('楼梯口', 'Баспалдақ ойығы', 'Проём лестницы', 'Stair opening',
                                      ky: 'Тепкич оюгу',
                                      uz: 'Zinapoya teshigi'),
                                  stairs: derived.floors[floorIndex].stairs,
                                  northAngleDeg:
                                      history.present.footprint.northAngleDeg,
                                  focus: focus,
                                  editableWall: (tool == EditorTool.editWall || tool == EditorTool.drawWall) &&
                                          editStart != null &&
                                          editEnd != null
                                      ? PlanRect(
                                          (editPreviewStart ?? editStart)!.dx,
                                          (editPreviewStart ?? editStart)!.dy,
                                          (editPreviewEnd ?? editEnd)!.dx,
                                          (editPreviewEnd ?? editEnd)!.dy)
                                      : null,
                                  wallSeed: tool == EditorTool.drawWall
                                      ? drawingOrigin
                                      : null,
                                  wallAttachments:
                                      (tool == EditorTool.drawWall || tool == EditorTool.selectWall) &&
                                              drawingEnd == null &&
                                              editPreviewStart == null
                                          ? visibleWallAttachments(size)
                                          : const [],
                                  handleScale: canvasZoom,
                                  selectedDimension: editingDimension,
                                  draftLabel: _wallTrial?.distanceLabel ?? wallDraftLabel,
                                  draftEnd: tool == EditorTool.drawWall && drawingStrokeActive && drawingEnd != null
                                      ? drawingEnd
                                      : wallGrip == WallGrip.start
                                          ? editPreviewStart
                                          : wallGrip == WallGrip.end
                                              ? editPreviewEnd
                                              : null,
                                  draftConnected: drawConnected,
                                  guides: [
                                    if (alignGuide case final g?
                                        when (tool == EditorTool.drawWall &&
                                                drawingStrokeActive &&
                                                drawingEnd != null) ||
                                            wallGrip == WallGrip.start ||
                                            wallGrip == WallGrip.end)
                                      g
                                  ],
                                  coach: coachArrow(size),
                                  draft: _wallTrial?.line ?? (tool == EditorTool.drawWall && drawingEnd != null && drawingOrigin != null ? PlanRect(math.min(drawingOrigin!.dx, drawingEnd!.dx), math.min(drawingOrigin!.dy, drawingEnd!.dy), math.max(drawingOrigin!.dx, drawingEnd!.dx), math.max(drawingOrigin!.dy, drawingEnd!.dy)) : spatialPreview),
                                  showGridDimensions: tool == EditorTool.grid,
                                  draftInvalid: spatialError != null,
                                  draftIsLine: _wallTrial != null || tool == EditorTool.split || tool == EditorTool.drawWall,
                                  viewport: draggingAxis?.kind == 'boundary' && dragAttempted && dragCoordinatePainter != null
                                      ? (
                                          scale: dragCoordinatePainter!
                                              .scale(size),
                                          origin: dragCoordinatePainter!
                                              .origin(size)
                                        )
                                      : null,
                                  resizeHandles: tool == EditorTool.resize,
                                  wallHandle: tool == EditorTool.wall && selectedWall != null ? (selectedWall!.axis.dir == AxisDir.V ? PlanRect((dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.start.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.end.pos.toDouble()) : PlanRect(selectedWall!.start.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()), selectedWall!.end.pos.toDouble(), (dragValid && dragKind == 'MoveLocalWall' ? (dragArguments!['pos'] as num).toDouble() : selectedWall!.axis.pos.toDouble()))) : null,
                                  tokens: Tokens.of(context),
                                  bearingMin: history.present.extras.foundation.bearingMin,
                                  furniture: [
                                    for (final f
                                        in history.present.extras.furniture)
                                      if (f.floorId == floor.id &&
                                          f.id != furnitureDraft?.id)
                                        f
                                  ],
                                  furnitureDraft: furnitureDraft,
                                  utilities: showUtilities ? [for (final u in floorUtilities) u.id == utilityDraft?.id ? utilityDraft! : u] : const [],
                                  selectedUtility: selectedUtilityId,
                                  selectedFurniture: selectedFurnitureId,
                                  selectedOpening: selectedOpeningId,
                                  selectedRoom: selectedRoomId,
                                  showFurniture: showFurniture,
                                  showDimensions: showDimensions,
                                  foundation: showFoundation && floorIndex == 0 ? foundationTakeoff(history.present, derived) : null,
                                  sleeves: history.present.extras.sleeves,
                                  highlights: highlights,
                                  pulse: pulse,
                                  measure: measurePoints,
                                  preview: List.of(stroke));
                              return Stack(children: [
                                RepaintBoundary(
                                    child: CustomPaint(
                                        key: canvasKey,
                                        size: size,
                                        painter: plan)),
                                IgnorePointer(
                                    child: CustomPaint(
                                        size: size,
                                        painter: PlanOverlayPainter(plan))),
                              ]);
                            }))));
          }));
}
