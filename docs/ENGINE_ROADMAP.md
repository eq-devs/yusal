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
- [ ] R17 encoder validates in release builds too
- [ ] Engine session reports created / removed walls
- [ ] R2 R4 R5 R9 one interaction reset for every mode exit
- [ ] R10 success toasts only on success
- [ ] R13 outer-wall sheet title
- [ ] R16 stale opening preview on an invalid drop
- [ ] R7 orbit pitch snap near top-down
- [ ] R8 tap on the roof selects what is underneath
- [x] One schema version: files are written as version 5; 1–4 load with
      the same decoder (they only added fields); no version gating
- [x] One command implementation: object edits only; the JSON file round
      trip (`_editThroughFile`) and `document_edits.dart` are gone
- [ ] Drop the duplicate schema table (`schema_validator.dart`)

## Phase 1 — architecture

- [ ] One screen-tolerance helper for every pick and snap (U1)
- [ ] Typed gesture state instead of strings
- [ ] Tool controllers with begin / move / end / cancel
- [ ] Split `page.dart`

## Phase 2 — performance

- [ ] Static plan layer and overlay layer (P1)
- [ ] Zoom-independent text cache with LRU (P5)
- [ ] Throttled, single-floor drag previews (P2)
- [ ] One batch for translucent faces (P4)
- [ ] 3D view repaint boundary (P6)
- [ ] Indexes in floor derivation and checks (P8, P9)

## Phase 3 — design tools

- [ ] Snap hysteresis and axis lock (U2)
- [ ] Measure snaps to walls and corners
- [ ] Free wall start (U7)
- [ ] Pitched roof follows the outline (R6)
- [ ] Scaled vector PDF with paginated tables (R12)

## Blocked

- Real-device validation: no device attached on 2026-11-26 (`adb devices`
  empty).
