# State machines

Every place in the app and in yusal-api where something moves through a set of states. **Explicit** machines have a typed list of states and the events that move between them, and refuse anything else. **Implicit** ones are booleans, strings or ad-hoc `if`s that together behave like a machine.

For people and agents alike: to know what can happen to a record now, read its machine, not the screen code.

## Explicit

### Market records (app and server, one definition)

`lib/platform/domain/rules.dart` (`demandMachine`, `applicationMachine`, `cooperationMachine`, `agreementMachine`, `milestoneMachine`, `reportMachine`) and yusal-api `internal/module/market/lifecycle.go` hold the same six machines. [`state_machines.json`](state_machines.json) is them written out, and a test on each side fails when its code and that file differ: after changing a machine, run `go test ./internal/module/market -run TestMachinesMatchDoc -update` in yusal-api, copy `docs/state_machines.json` here, and update `rules.dart` until `test/platform/state_machines_test.dart` passes.

Every status write in `MockBackend` and in the server goes through an event (`demandMachine.next(status, DemandEvent.pause)`, `DemandMachine.Fire(&d.Status, "pause")`). `allowed(status)` lists what can be done now; the demand page's owner buttons are those events.

| Machine | States | Events |
|---|---|---|
| demand | draft, pendingReview, open, paused, found, expired, closed, rejected | publish, recheck, approve, reject, pause, resume, renew, markFound, expire, close |
| application | submitted, withdrawn, notSelected, pendingConfirm, cooperating | resubmit, withdraw, notSelect, invite, uninvite, cooperate |
| cooperation | pending, confirmed, ended, notFormed | confirm, notForm, end |
| agreement | proposed, active, superseded, rejected | accept, reject, supersede |
| milestone | planned, requested, accepted, disputed | request, accept, dispute |
| report | open, upheld, dismissed | uphold, dismiss |

Events that move several records together: `invite` (application → pendingConfirm, a new cooperation pending with agreement proposed); both sides confirming (cooperation `confirm`, agreement `accept`, application `cooperate`); decline/revoke/withdraw (cooperation `notForm`, its agreements `reject`, application `uninvite` or `withdraw`); an accepted change (the new agreement `accept`, the old one `supersede`); an upheld report on a demand (report `uphold`, demand `reject`).

Not in the status: a confirmed cooperation's end request (`endRequest`: none → asked → disputed → asked again; a week unanswered fires `end`), and who has confirmed an agreement (`confirmedBy`).

### Voice

- `VoicePhase` (`lib/voice/session.dart`): idle → thinking ⇄ acting → done | failed, at most `maxSteps` acting rounds. A sentence said while busy stops the running one and runs next.
- The orb's microphone, `_Mic` in `lib/voice/voice_overlay.dart`: off → listening → transcribing → off (tapping the pill while listening goes straight to off). One enum, so it cannot be listening and transcribing at once.
- `_Mood` (the orb's colours) is derived from the two above and never stored.
- Gateway dialog (yusal-api `internal/gateway/dialog.go`): the house brief gathers size, floors and bedrooms; `design.create_house` is refused until they are known, the user said to decide, or `MaxQuestions` (4) questions were asked. State is the brief and the question count, derived by `missing()`.

### Other

- Editor tool, `EditorTool` in `lib/features/house_editor.dart`: the one thing a press on the plan does (browse, drawWall, selectWall, editWall, split, box, resize, placeOpening, placeFurniture, placeUtility, measure, and the advanced wall, opening, grid, room, stair). Browse is the rest state that Esc, the browse button, a tab or a floor change go back to; `browse` is derived from it, not stored. The voice context's `summary` says `tool: <name>` while any other tool is in hand.
- Editor save status, `_SaveStatus` in `lib/features/house_editor.dart`: saved | indexPending | unsaved | failed (retries every 5 s). An edit makes it unsaved.
- `HouseStage` (design → finding → building → done), derived from demands in `house_progress.dart`.
- `BackupState` (none, inSync, localNewer, cloudNewer, diverged), derived by comparing a design with its backup.
- `SendState` of a chat message: sending → sent | failed → (retry) sent.
- Posts (`published` ⇄ `hidden`), profiles (`active` ⇄ `hidden`), accounts (`active`, `blocked`, `deleted`): two- or three-state flags whose rules live in their services.

## Still implicit

Worth making explicit next, highest value first:

1. **Demand edit page** (`publish_page.dart`): which save a change takes (`saveDraft` for draft and rejected, `revise` otherwise) is chosen by status checks in the page; it could ask `demandMachine` (`recheck`).
2. **Sign-in page** (`login_page.dart`, `codeSent`): enter phone → code sent → verifying.
3. **HTTP read retries** (`http_backend.dart`): attempt counter over a backoff list; fine as it is, documented here for completeness.
