# State machines

Every place in the app and in yusal-api where something moves through a set of states. **Explicit** machines have a typed list of states and the events that move between them, and refuse anything else. **Implicit** ones are booleans, strings or ad-hoc `if`s that together behave like a machine.

For people and agents alike: to know what can happen to a record now, read its machine, not the screen code.

## Explicit

### Market records (app and server, one definition)

`lib/platform/domain/rules.dart` (`demandMachine`, `applicationMachine`, `cooperationMachine`, `agreementMachine`, `milestoneMachine`, `reportMachine`) and yusal-api `internal/module/market/lifecycle.go` hold the same six machines. [`state_machines.json`](state_machines.json) is them written out, and a test on each side fails when its code and that file differ: after changing a machine, run `go test ./internal/module/market -run TestMachinesMatchDoc -update` in yusal-api, copy `docs/state_machines.json` here, and update `rules.dart` until `test/platform/state_machines_test.dart` passes.

Every status write in `MockBackend` and in the server goes through an event (`demandMachine.next(status, DemandEvent.pause)`, `DemandMachine.Fire(&d.Status, "pause")`). `allowed(status)` lists what can be done now; the demand page's owner buttons are those events. The voice assistant gets the same set: on the owner's demand page it is offered `demand.publish`, `demand.pause`, `demand.resume`, `demand.renew`, `demand.mark_found` and `demand.close` only when `demandButton(status, event)` is true (`lib/voice/actions_demand.dart`), each confirmed before it runs, and the page's `summary` names the status.

| Machine | States | Events |
|---|---|---|
| demand | draft, pendingReview, open, paused, found, expired, closed, rejected | publish, recheck, approve, reject, pause, resume, renew, markFound, expire, close |
| application | submitted, withdrawn, notSelected, pendingConfirm, cooperating | resubmit, withdraw, notSelect, invite, uninvite, cooperate |
| cooperation | pending, confirmed, ended, notFormed | confirm, notForm, end |
| agreement | proposed, active, superseded, rejected | accept, reject, supersede |
| milestone | planned, requested, accepted, disputed | request, accept, dispute |
| report | open, upheld, dismissed | uphold, dismiss |

Events that move several records together: `invite` (application → pendingConfirm, a new cooperation pending with agreement proposed); both sides confirming (cooperation `confirm`, agreement `accept`, application `cooperate`); decline/revoke/withdraw (cooperation `notForm`, its agreements `reject`, application `uninvite` or `withdraw`); an accepted change (the new agreement `accept`, the old one `supersede`); an upheld report on a demand (report `uphold`, demand `reject`).

A confirmed cooperation's ending is its own small machine, `EndPhase` (`Cooperation.endPhase`, server `Cooperation.EndPhase()`), read from `endRequest`: none → asked → `end` fired by the other side's yes or after a week unanswered, or → disputed → asked again by a new request. `endAskedOf(me)` says whether it is mine to answer. `coopMoves(c, me)` (`rules.dart`) is what one side can do now (confirm, decline, revoke, request, confirm or dispute the end, answer a change): the cooperation page's buttons and the voice assistant's `coop.*` actions both come from it. `milestoneMoves(c, me, i)` does the same for inspection points (the provider asks for the first open one, the owner accepts or questions a requested one); voice acts on `currentMilestone(c)`. Who has confirmed an agreement (`confirmedBy`) stays a set, not a state.

### Voice

- `VoicePhase` (`lib/voice/session.dart`): idle → thinking ⇄ acting → done | failed, at most `maxSteps` acting rounds. A sentence said while busy stops the running one and runs next.
- The orb's microphone, `_Mic` in `lib/voice/voice_overlay.dart`: off → listening → transcribing → off (tapping the pill while listening goes straight to off). One enum, so it cannot be listening and transcribing at once.
- `_Mood` (the orb's colours) is derived from the two above and never stored.
- Gateway dialog (yusal-api `internal/gateway/dialog.go`): the house brief gathers size, floors and bedrooms; `design.plan_house` and `design.create_house` are refused until they are known, the user said to decide, or `MaxQuestions` (4) questions were asked. State is the brief and the question count, derived by `missing()`.

### Other

- Editor tool, `EditorTool` in `lib/features/house_editor.dart`: the one thing a press on the plan does (browse, drawWall, selectWall, editWall, split, box, resize, placeOpening, placeFurniture, placeUtility, measure, and the advanced wall, opening, grid, room, stair). Browse is the rest state that Esc, the browse button, a tab or a floor change go back to; `browse` is derived from it, not stored. The voice context's `summary` says `tool: <name>` while any other tool is in hand.
- Editor save status, `_SaveStatus` in `lib/features/house_editor.dart`: saved | indexPending | unsaved | failed (retries every 5 s). An edit makes it unsaved.
- `HouseStage` (design → finding → building → done), derived from demands in `house_progress.dart`.
- `BackupState` (none, inSync, localNewer, cloudNewer, diverged), derived by comparing a design with its backup.
- `SendState` of a chat message: sending → sent | failed → (retry) sent.
- Posts (`published` ⇄ `hidden`), profiles (`active` ⇄ `hidden`), accounts (`active`, `blocked`, `deleted`): two- or three-state flags whose rules live in their services.

## Still implicit, on purpose

1. **Sign-in page** (`login_page.dart`, `codeSent`): two steps, one flag; an enum would add nothing.
2. **Demand edit page** (`publish_page.dart`): picks `saveDraft` for a draft and `revise` otherwise; the server's machine (`recheck`) already guards it.
3. **HTTP read retries** (`http_backend.dart`): an attempt counter over a backoff list.

Checked and left as they are: none of these has a state that can't be told apart or a combination that shouldn't exist.
