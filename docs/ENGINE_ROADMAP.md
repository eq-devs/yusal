# Design engine roadmap

Living checklist for the engine and editor work on branch `engine/redesign`
(started 2026-11-26 from `dev` at `0f78537`). Source: the technical audit
"Yusal House Design Engine — Technical Audit & Improvement Plan". Ids (R1,
P3, U2 …) are the audit's.

Baselines from `0f78537` are in `docs/perf/` (compiled engine bench on an
M-series Mac, and the JIT render baseline). Compare later runs on the same
machine only.

## Model decision

The document stays an **integer-millimetre orthogonal axis grid**, with
walls drawn on per-floor local axes and rooms recognised from walls.

Considered: a wall graph with half-edge room detection and free angles.

- What it would buy: angled and curved walls, rotated rooms.
- What it costs: exact integer arithmetic is lost (wall faces at arbitrary
  angles need snap rounding or robust predicates). Derivation,
  canonicalisation, mirror, the validator, 80 commands, the 3D scene, cost,
  heat and export all read `FloorBase` (29 files outside geometry).
- Evidence: the audit found no defect caused by the grid itself; the
  defects were in the editor shell. The target users build rectilinear
  rural houses. Rectilinear L/T/U footprints, cut corners, local axes and
  free-standing drawn walls already fit the grid.

So the grid stays, and angled walls are not started. The cheapest later step
if users need it is 45° walls on integer coordinates (centrelines stay
exact; faces need rounding).

## Phase 0 — correctness

- [x] Suite green, analyzer clean, CI (`.github/workflows/ci.yml`)
- [x] AOT crash in `editDrawnWall` under `dart compile exe`
- [x] R1 opening must lie within its host wall
- [x] R3 upper bounds for every document number
- [x] R14 low wall on an outline edge duplicates the exterior wall
- [x] R15 undo group longer than the history cap
- [x] R17 encoder validates in release builds too
- [x] Engine session reports created / removed walls
- [x] R2 R4 R5 R9 one interaction reset for every mode exit
      (`resetInteraction`; R2's own trigger is verified by code trace only)
- [x] R10 success toasts only on success
- [x] R13 outer-wall sheet title
- [x] R16 stale opening preview on an invalid drop
- [x] R7 orbit pitch snap near top-down
- [x] R8 tap on the roof selects what is underneath
- [x] One schema version: files are written as version 5; 1–4 load with
      the same decoder (they only added fields); no version gating
- [x] One command implementation: object edits only; the JSON file round
      trip (`_editThroughFile`) and `document_edits.dart` are gone
- [x] Drop the duplicate schema table (`schema_validator.dart`)

## Phase 1 — architecture

- [x] One screen-tolerance helper for every pick and snap (U1)
- [~] Typed gesture state: `WallGesture` enum done; `dragKind`, `wallGrip`,
      `furnitureGrip` are still strings
- [ ] Tool controllers with begin / move / end / cancel
- [ ] Split `page.dart`

## Phase 2 — performance

- [x] Static plan layer and overlay layer (P1)
- [x] Zoom-independent text cache with LRU (P5)
- [x] Single-floor drag previews, skipped when the command repeats (P2)
- [x] Section slider draws fast frames until released (P7)
- [x] One batch for translucent faces (P4)
- [x] 3D view repaint boundary (P6)
- [x] Indexes in floor derivation and checks (P8, P9)
- [x] Commands bring only the floors they changed in line with their
      walls, and check only those floors' doors and windows
- [x] The floor geometry cache keys on the shared lines and the floor's
      own, so a line added on one floor keeps the others' geometry
- [ ] Validate only what a command changed (full validation is ~1.1 ms of
      a large-plan command)

## Phase 3 — design tools

- [x] Snap hysteresis and axis lock (U2)
- [x] Measure snaps to wall corners and faces; shows metres and both sides
- [x] Free wall start: a drag from any point of a wall starts a wall (U7)
- [x] Hip roof follows the outline (R6): a hip over each largest rectangle
      of the top floor; their upper envelope is the straight-skeleton roof
      of a right-angled outline. Gable roofs still span the rectangle.
- [x] PDF tables never cut off silently: a "see schedule" row, and a
      paginated heat-load schedule for large houses (R12)
- [ ] Scaled vector PDF

## Blocked

- Real-device validation: no device attached on 2026-11-26 (`adb devices`
  empty).

## Status at pause (2026-11-26)

Done and committed on `engine/redesign`: Phase 0 (all items), and from
Phases 1–2 the tolerance helper, plan layers, text cache, glass batching,
3D repaint boundary, derivation and check indexes, single-floor drag
previews and the fast section slider. Suite: 910 passed, 6 skipped;
analyzer clean.

Not started yet:

- Typed gesture state, tool controllers, splitting `page.dart`
- Static GPU vertex buffers (P3), incremental validation
- Snap hysteresis and axis lock, measure snapping, free wall start
- Roof following the outline, scaled vector PDF
- Real-device measurements (no device was attached)
