# Changelog

All notable changes to the keel marketplace. Versions are per plugin; the marketplace version
at the top of each entry is the one in `.claude-plugin/marketplace.json`. Each entry says what
changed and why.

## marketplace 0.92.0 - 2026-11-25

- **`keel-workflow` 0.84.0: a helper told to read only is checked for what it wrote.** An advisor
  and a plan reviewer were each told by their brief to edit nothing, and a plan reviewer could write
  a simulation of the change it was reading into the project folder anyway, with nothing in keel
  noticing: a brief is text, and no gate looked at what the helper then did.
  - **`keel-state.ps1`** gains `dispatch-open -Phase <phase> -Name <helper>` and `dispatch-close`
    with the same two arguments. Open stores a reading of the project folder (when `keel.json` has
    `git: true`), every git repo `keel.json` registers and the top level of the phase folder, read
    with the functions the verify fingerprint uses. Close re-takes it and, when it finds paths new,
    changed or removed since open, prints one `WARNING` line, a line `<tree>: <path> (<how>)` for
    each and a line of advice, and appends one friction entry of a new kind, `dispatch-write`,
    naming the dispatch and its window. A clean close prints and records nothing,
    and both exit 0 whatever they find: they detect, they do not block. The new suite checks that
    close names a new file, an edit (a second edit to a file already modified at open included), a
    deletion, a file committed while the helper was out, a file restored to its committed content,
    and a rename through git under both names.
    **Known limits, not a complete list.** These can go unnamed: a file git ignores in the project
    folder or a registered repo; a change git or keel treats as no change, such as one only to line
    endings or only to the letter case of a name; a file below the top level of the phase folder,
    or one there that Windows marks hidden; and a commit of changes already in the folder. In a project
    with no git tree only the phase folder is compared, and open says so. When more than 2000 paths
    in one tree differ from its last commit at open, close can report only that the tree changed,
    not which paths. The per-path list for the project folder leaves out `progress/`, which keel
    writes itself, and the verifier's own report in the phase folder is not compared. A tree says
    what changed while a helper was out, not who changed it, so a file the session writes in that
    window is named too. Close with no open dispatch of that name, open of a name already
    open, and either without `-Name` exit 90; an unknown phase exits 94. `status` prints
    `WARNING: <phase> dispatch '<name>' opened <time> was never closed` for each dispatch left open.
  - **`ADVISOR_BRIEF.md`**, **`PLAN_REVIEW_BRIEF.md`** and **`VERIFIER_BRIEF.md`** name one scratch
    folder, `%USERPROFILE%\.keel\projects\<slug>\phases\<phase>\scratch\`, as the place a helper's
    scratch file goes; the verifier's used to go to the top of the phase folder, which the close
    compares. All three tell the helper that the project folder, every repo it uses and the top
    level of the phase folder are compared before and after it runs, and that a file it writes
    there other than its report can be recorded against it by name.
  - **`keel-run-phase`** Gates 2, 3 and 5 run `dispatch-open` before a brief is handed over and
    `dispatch-close` when the helper returns; a close that names paths has them named in that gate's
    artifact, each file left in place until the operator says what to do with it. Gate 6 presents
    any `dispatch-write` entries with the change set.
  - **`scripts/test-dispatch-check.ps1`**, a new suite, checks the two commands against scratch
    projects, each case beside a control; `check-suite-docs.ps1 -Strict` runs it as section 23.

## marketplace 0.91.0 - 2026-11-24

- **`keel-workflow` 0.83.0: what the operator is handed is in the conversation, names each file by
  its full path, and keeps its recap short.** For a step only the operator could do, a session
  could write the steps to a file and hand over a link that did not open. And a question could meet
  every rule for how it is written and still go unanswered, because its recap was too long.
  - **`keel-run-phase`** Gate 4, for a `self` or `external` phase: the steps go in the conversation,
    and a file holding them is only the record. Each step is one action and says what the operator
    should see if it worked. The session gives steps up to the next point where it needs something
    back from the operator, then waits; actions with nothing to report between them go in one
    message. The test is that the operator can start without opening anything.
  - **`keel-orchestrator`** "Asking the human" gains a paragraph: a file named to the operator, in a
    question, a step, the presentation of a change set or a hand-back, is written as its full path in
    plain text and never as a link to a place outside the project folder, which can fail without
    saying so. `keel-run-phase` points at it from Gate 4's `self` and `external` block and from Gate 6.
  - **`keel-orchestrator`** obligation 5: the recap's three things, what the project is for, what was
    tried and what came back, take at most five short sentences, with no file names, version numbers,
    counts or process history; a measurement goes in the option it supports, in section 5 of
    `DECISION_BRIEF.md`.
  - **`DECISION_BRIEF.md`** section 3: what the project is for takes one sentence, what was tried and
    what came back one or two each, and the last names section 5 as where its measurement goes. Its
    comment says that obligation 5 bounds the three.

## marketplace 0.90.0 - 2026-11-24

- **`keel-workflow` 0.82.0: a planning phase's checks have a point where a fresh reader stops,
  and a reviewing subagent may read the state.** Two of the eight fixed checks a planning phase
  copies asked a fresh verifier to confirm that every factual premise in a spec's first section
  carried its command, and that every check stated how it could fail. Neither named a list to check
  against, so a verifier could always find one more sentence to fail, and planning phases ran
  verify round after round on wording while every measured figure agreed.
  - **`FIXED_CHECKS_PLAN.md`**: check C1 now grades the items listed under the spec's `Measured`
    heading, and fails one that names no command or result, re-takes differently or states an
    absence a reader finds present. Check C3 grades the checks in section 5, each numbered, saying what
    decides it and carrying a positive control, a broken-instrument output or the word unmeasured
    with a reason. Anything a reader finds beyond
    those lists, such as an unbacked phrase inside a listed item or a form judged weak, is noted in the verify
    report and answered in the delivery record, and does not decide the verdict.
  - **`keel-run-phase`** Gate 8 says the delivery record answers each such noted item in one line,
    and that an answer editing what the verifier read is a repair, followed by another verify round.
  - **`SPEC_TEMPLATE.md`** says each premise is listed under `Measured`, one item each, because that
    list is what C1 reads.
  - **The verifier and plan-review briefs** forbade running `keel-state.ps1` at all, while a
    planning phase's checks ask for figures that come from the wrapper's reads. Both now forbid only
    the verbs that write, and name the forms that write nothing: `status` with no arguments, `tree`,
    `order` with no arguments, `signals` and `goal-coverage`. `status -Phase` and `status -Json`
    stay out, because they print the working session's own notes, which a fresh reader is kept
    from.

## marketplace 0.89.0 - 2026-11-24

- **`keel-workflow` 0.81.0 and `keel-surfaces` 0.4.0: text that leaves a project names no one, and a
  draft marks the lines its session proposed.** Before this, keel had no general rule against
  naming people, or saying who decided or wanted what, in text it publishes; its narrower rules
  covered a project with quarantine on and what a signal push checks for. A drafted outbound text
  could mix the session's own proposals with sourced facts
  while its preview called all of it sourced.
  - **`keel-orchestrator`** has a new section, "Text that leaves the project names no one, and marks what the session proposed". It names what is published (a
    signal's title, detail and evidence, a sighting's detail and evidence, and a resolution's text;
    tracker cards; a phase's outbound drafts; pull request text) and what is not (the project's own
    records, and commit messages). Published text names no one and attributes no decision, wish,
    proposal, agreement or statement to anyone, by name or by a role, the operator included; a
    decision is stated as the decision and a quotation carries no speaker; fields that exist to
    hold a person are untouched; the operator may direct otherwise for one text, which is recorded
    in the phase's `enact-record.md` or, where there is no enact record, in the hand-back; and
    published text already written is not rewritten. A draft carries a `Proposed lines:` list
    beside it, quoting each line the session wrote with no source behind it, or
    `Proposed lines: none`, and no preview calls a text sourced, checked or traceable as a whole
    unless that list is empty and a fresh reader has checked the draft. The rule is skill prose; no
    exit code enforces it. The "Who decided is part of the record" paragraph now says its label is
    for the project's own records, and the signals section points at the new section.
  - **`keel-run-phase`** points at it at Gate 4, for a draft; at Gate 6, whose preview gains a fifth
    item quoting the proposed lines word for word; and at Gate 7, which names `enact-record.md` as
    where a direction for one text is recorded. Its plan-review brief has an eighth question, on a
    line naming or crediting a person and an unsourced line missing from the proposed list, each a
    defect, and its verifier brief tells the verifier to report both under "Anything else I
    noticed".
  - **`keel-close-workstream`** Step 4 points at it: a signal's title, detail and evidence are
    published as written.
  - **`keel-tracker`** points at it, its preview example's wait reads `waiting on the accountant`,
    and a card projects a stored wait's "who" as a role or leaves it out, never as a person's name,
    unless the card has a field that exists to hold a person, where the name goes in that field and
    never in the card's text.

## marketplace 0.88.0 - 2026-11-23

- **`keel-workflow` 0.80.0: a goal's wording can be changed, and the wording it replaces is kept.**
  Before this, a goal's text was fixed once `add-goal` registered it. When a project decision
  reworded a goal, the new wording went into the charter by hand, the state kept the old text, and
  `tree`, the one command that prints a goal's wording, went on printing the superseded goal.
  - **`revise-goal -Id G<n> -Text "<new wording>" -Detail "<why>"`** sets the goal's text and
    appends `{ text, reason, at }` (the wording it replaced, the reason and the time) to a
    `revisions` list on the goal. The goal's status and every workstream's link to it are
    unchanged. It refuses a missing `-Id` or `-Text`, an id that is not `G<n>`, and a `-Text`
    equal to the current wording at exit 90, a missing `-Detail` at exit 95, and a goal that does
    not exist at exit 98, and writes nothing when it refuses.
  - **`tree`** prints the current wording and, for a goal with at least one revision, appends
    `  (reworded <yyyy-MM-dd>)`, the date of the last one. A goal never reworded prints exactly what
    it printed before, and its stored record gains no key. `status -Json` shows the whole list.
    `goal-coverage` and `status` print goal ids, not wording, and are unchanged.
  - **Shared progress.** In a project that shares its progress, a goal file carries `revisions`
    only when the goal holds it, so an unrevised goal's file keeps its bytes. When a keel older than
    this one rewrites a reworded goal's file and drops the list, `status`, and only `status`,
    warns: `<path> held revisions at an earlier commit and no longer does - a keel older than this
    one rewrote it. The earlier wordings are in: git log -p -- <path>`. No command restores the
    list; its history is in git.
  - **The planning skills.** `keel-plan-project` Step 5, the goals comment in its charter template
    and `keel-plan-workstream`'s amend mode each say that when a goal's wording changes, the
    charter's row and `keel-state.ps1 revise-goal` change in the same act, with the reason.
  - **Tests.** `scripts/test-ordered-plan.ps1` gains group GOAL and `-GoalOldRef` (default
    `v0.87.0`), the older keel its controls compare with, refused at exit 90 if it already knows
    `revise-goal`. `scripts/test-shared-progress.ps1`'s layout check allows a goal's `revisions`,
    each element exactly `text`, `reason` and `at` with a UTC offset, and its two-person fixture
    rewords a goal.

## marketplace 0.87.0 - 2026-11-22

- **`keel-workflow` 0.79.0: planning a workstream, re-planning one and closing one are work `status`
  can name.** Before this, `status` could only name a phase of delivery work. Planning a workstream
  happened in a session no gate read, a re-plan was a session that `status` did not know about,
  so it named the next phase of a workstream whose plan was being changed, and a handoff file had to
  carry what came next. This release also carries the order between workstreams from 0.78.0, which
  no release named.
  - **A phase has a kind.** `add-phase -Kind plan` or `-Kind replan` registers a planning phase;
    `deliver` is the default, and a phase registered without `-Kind` stores no kind, so every existing phase is what it was. The kind
    selects what a phase's artifacts hold and which fixed checks apply, never which gates run: a
    planning phase runs the same eight. In a delivery workstream, kind `plan` is `W<n>.0`, the
    phase that plans it. `status` prints `next: <id>  [plan]  (<scope>)` or `[re-plan]`, and the
    phase table marks such a phase `plan` or `re-plan`; `tree` prints `kind:plan` or
    `kind:replan`.
  - **The re-plan hold, in any project.** While a workstream has an open re-plan, every other
    unfinished phase of it is held where it is: nothing is written to it, so it keeps its gates, its
    iteration count and its verify fingerprint, and it is not named as next. The phase table marks
    it `held by re-plan <id>`, and a started one gets the line `<id> is held at <stage> by re-plan
    <id>; it resumes there once <id> is delivered.` Once the re-plan is delivered, the held phases
    are named again at the stages they were at. A workstream has one open re-plan at a time
    (`add-phase` refuses a second at exit 90).
  - **`add-workstream` creates the planning phase.** In a project that has placed its workstreams,
    a new workstream is placed and created with `W<n>.0` (kind plan, run order 0), which `status`
    names until it is delivered. A project holding no workstream at all is ordered from its first
    one, whether or not it holds an epic: that workstream is placed at 1 and gets its `W<n>.0`. A
    project that already holds workstreams and no order sees none of this until it adopts an order
    with `order -Set`. `-Express` creates no `W<n>.0`, because the express phase's own plan gate
    carries the plan.
  - **Planning workstreams.** `add-workstream -Kind planning` makes a workstream whose phases plan
    work above one workstream: decomposing an epic, or re-planning an epic or the project's order. It
    declares no goal (`-Goals` with it exits 98), is never counted as covering one, holds only
    planning phases (a phase of kind deliver in it exits 93), gets no `W<n>.0`, and is placed like
    any workstream. `tree` prints it `[workstream, planning]`. A delivery workstream with no
    `-Goals` is still refused at exit 98.
  - **The walk.** For each workstream in the order, `status` names the first of its open re-plan,
    its planning phase `W<n>.0`, its first runnable phase by run order and `close W<n>`. In a
    project that shares its progress, a `close W<n>` belongs to the owner of `W<n>.0`, so it is on
    their `next:` and on everyone else's `others:`; with no `W<n>.0` it belongs to nobody and is
    on `unowned:`.
  - **Shared progress.** A node file carries `kind` for a planning workstream, and a planning
    phase's `phase.json` carries `kind`, only when set. A planning phase is owned like any phase.
    After a merge, two open re-plans of one workstream print a warning naming both, and the later is
    not named as next. When an older keel rewrites a file and drops its kind, `status` warns and
    names the command that restores it: `revise-phase -Kind` or `revise-workstream -Kind`, which
    set an unfinished item's kind under the rules `add-phase` and `add-workstream` apply; set back to the default, a kind keeps its key, so this keel's own change is never read as an older keel's drop.
  - **Fixed-check templates.** The checks of a planning phase ship as templates nobody writes:
    `keel-plan-workstream/templates/FIXED_CHECKS_PLAN.md` (eight, for `W<n>.0`),
    `FIXED_CHECKS_REPLAN.md` (seven, for a re-plan) and
    `keel-plan-epic/templates/FIXED_CHECKS_PLANNING_WORKSTREAM.md` (four, for a planning
    workstream's phase). `keel-run-phase` names which one each kind copies into its plan and its
    verifier brief.
  - **The skills.** `keel-orchestrator`: "Step 3.5" registers a re-plan as a phase, dispatched to
    `keel-run-phase` with `keel-plan-workstream`'s amend mode as its procedure, and documents the
    `order` verb; "Step 0.4" routes a workstream-level or epic-level ask in an ordered project
    through `W<n>.0` or a planning workstream; "Step 1" registers a spec's rows at the planning
    phase's enact step; the handoff table owes no handoff for `close W<n>`; the `status` table
    has a row for every new line. `keel-plan-workstream`: amend mode is the procedure of a re-plan
    phase, and Step 5's registration is the planning phase's enact step. `keel-plan-epic`: order
    and blocked-by go into the state when an area is registered, and in an ordered project `status`,
    not the ledger, names the next decomposition session. `keel-plan-project`: Step 6 registers
    the first planning work so that `status` names the next session, and owes a handoff only when
    nothing is registered. `keel-run-phase`: a phase's kind, the templates, the enact act of a
    planning phase, and a re-plan's delivery record naming where each held phase resumes.
    `keel-close-workstream`: a planning workstream closes the way an express one does.
  - **The charter.** P2 gains the kind beside the actor; P17 gives a workstream a kind, which is
    not a role; P22 exempts a planning workstream from claiming a goal; P10 makes the state the
    authority for the plan's order, its planning work and its dependencies.
  - **What does not change.** A project that holds workstreams, places nothing, declares no
    workstream need and registers no re-plan prints exactly what it printed. No verb gains a
    required parameter.
  - **`scripts/test-ordered-plan.ps1`** gains a group for the kinds, each case beside a control; it
    and `scripts/test-shared-progress.ps1` make a fixture's first workstream with a keel that
    predates the order, so that a project with no order still exists to test.

## marketplace 0.86.0 - 2026-11-22

- **`keel-workflow` 0.78.0: the state can hold the order between workstreams, and `status` walks
  it.** Until now `status` named next only from phases' run orders, which are unique within one
  workstream: two workstreams each holding a phase at the same run order made it decline to choose,
  and a workstream with no phases, or one whose phases were all finished, was work it could not name
  at all. The order lived only in a project's own prose. No release carries this yet; it reaches an
  installed copy with the next one.
  - **Order on workstreams and phases.** A workstream may carry an `order`, and so may a single
    phase, which is then placed in the sequence on its own instead of running inside its workstream.
    The project's sequence is its unfinished workstreams and placed phases by order; `tree` and
    `order` print each one's position (`#1`, `#2`), and an epic's line in `tree` shows the
    position of its first unfinished workstream (`order: from #1`). Epics store no order.
  - **The `order` verb.** With no arguments it prints the sequence: a header with the counts, then
    one line per position with the id, title, parent and the item the walk would name for it; with
    nothing placed it says so and writes nothing. `order -Id <id> -Before <id>` (or `-After <id>`,
    `-First`, `-Last`) moves one workstream or phase between its neighbours and rewrites no other
    record; an epic's id moves all its unfinished workstreams as one block, keeping their order among
    themselves, while a placed phase keeps its own position. `order -Set <ids in order>` places many
    at once, which is how a project adopts an order; it must list every unfinished item already
    placed, and refuses at exit 90 otherwise. No input names a number: each one is computed between
    two neighbours, so one writer cannot make two items share a place. Order belongs to no one, so
    in a project that shares its progress anyone may place work, while a phase keeps its owner.
  - **The walk.** Once anything is placed, `status` walks the sequence: a placed phase is named if
    it can run; a workstream gives its first runnable phase by run order, `next: plan W<n>  (<title>
    - no phases yet)` when it has no phases, and `next: close W<n>  (<title> - every phase
    finished)` when all are finished; a workstream or phase that cannot run is passed over. The order
    decides, so there is no ambiguity warning. An open workstream with no place prints `WARNING: <n>
    open workstream(s) have no place in the order: <ids>. Place each with: order -Id <id> -After
    <id>` and is never named; a pending phase under a closed workstream gets a line of its own.
    `add-workstream` in an ordered project places the new workstream right after the last one under
    its parent epic, or last. In a project that shares its progress, `next:` is the first item of
    the walk you own, `others:` gives everyone else's by the same walk, and a `plan` or `close`
    item, which belongs to nobody, is printed to everyone on an `unowned:` line.
  - **Needs on whole workstreams.** `add-workstream -Needs <ids>` and `revise-workstream -Needs
    <ids|none>` declare the phases or workstreams a workstream needs delivered first, with the
    refusals a phase's needs have (itself or one of its own phases and a cycle at 90, an unknown id at
    94). Until a need is met none of the workstream's phases is named next, in any project, and
    `status` prints `<id> waits on ...` as it does for a phase. `-Needs` alone is accepted on a
    workstream that has delivered phases, and refused on a closed one. `tree` prints a workstream's
    needs.
  - **Shared progress.** A node file carries `order` and `needs`, and a placed phase's
    `phase.json` carries `order`, only when they are set. After a merge, `status` and `tree` warn
    when two unfinished items share an order (neither is named next), when a workstream's need names
    no file, and when needs form a cycle through a workstream. Because an older keel rewrites a file it
    changes with only the fields it knows, `status` also warns when an unfinished item's file held
    `order` or `needs` at an earlier commit and no longer does, and when a phase an older keel handed
    over lost its place.
  - **What does not change.** A project that places nothing and declares no workstream need prints
    exactly what it printed, line for line, and no verb gains a required parameter.
  - **`scripts/test-ordered-plan.ps1`**, a new suite that `check-suite-docs.ps1 -Strict` runs, checks
    the walk, the verb, the placement, workstream needs, the shared files and checks and the
    session-start hook, each case beside a control; `-AgainstWrapper <path>` runs it against another
    copy, and `-RealProjects` compares `status` and `tree` on this machine's projects, read only.

## marketplace 0.85.0 - 2026-11-21

- **`keel-workflow` 0.77.0: every approved write is committed locally and reported.** A session that
  wrote an approved re-plan ended with nothing committed and offered to show a commit's contents
  first, so its operator had to ask for the commit; and the skill that creates a project left even
  its first commit to the operator.
  - **The rule.** `keel-orchestrator`'s section "Whether to ask, or to act and report" now says that
    in every project whose `keel.json` has `"git": true`, a session commits locally, in the project
    folder's own repo, each write it makes there that the operator approved (a spec, prompt, epic
    ledger, charter, goals or decision row) or that a passed gate or a close-out requires (a
    delivery record, spec append, next prompt, handoff, line-ending repair, index rebuild, close-out
    stamp and sections, `reference/` notes). Each step's writes are committed together once the step
    is complete, and each commit is reported by its short hash, subject and files. The section says
    this is the operator's standing request.
  - **How the commit is made.** By path, only the files the session wrote, never `git add -A`, `.`
    or `-u`; a path that already held uncommitted changes is left uncommitted and named; never
    `--no-verify`, never an amend or a rewrite; a commit a hook refuses is fixed at its cause and
    made again, or reported as not made.
  - **What does not change.** Such a commit is not pushed. A project that shares its progress still
    commits and pushes an approved plan at once, a phase's own change in a declared repo stays its
    enact step, and `"confirmEveryAct": true` does not reach these commits. No wrapper verb, state field,
    `keel.json` key or hook changes.
  - **The skills that point at it.** `keel-plan-project` makes a new project's first commit once the
    operator has approved its charter and goals, and the orchestrator's "Ending a session" no longer
    has a project-creation exception. `keel-plan-workstream` (registering the phases, the prompt,
    amend mode), `keel-plan-epic`, `keel-run-phase` (the record gate, its Must not and its
    description) and `keel-close-workstream` (its hand-back and its Must not) point at the rule,
    and the orchestrator's Must NOT list and `PHASE_PROMPT_TEMPLATE.md`'s "Do not" list no longer
    forbid such a commit.
  - **The charter.** P6 carries a dated amendment saying the same.

## marketplace 0.84.0 - 2026-11-21

- **`keel-workflow` 0.76.0: signal records are easy to read and repair.** A report's issue title was
  the whole detail cut at 240 characters, the version it showed was the plugin's rather than the
  release, a push could leave its payload files behind in `TEMP`, an issue whose number a push failed
  to record could not be attached to its record, and an open signal seen again had nowhere to go but a
  second signal.
  - **Short titles.** `signal` and `adopt-signal` take an optional `-Title`, stored on the record
    as `title`: one line of at most 100 characters, refused at exit 90 otherwise. An issue's title is
    `[signal:<kind>] <title>`; with no title it is the detail's first sentence, kept whole when it
    fits in 80 characters and otherwise cut to the whole words that fit, followed by `...`. The whole
    detail stays in the body, and the preview says when a title was taken from the detail.
    `adopt-signal -Title` prints the title the record carries. Titles already published are not
    changed.
  - **The published title is kept.** A push stores the title it sent as `issueTitle`. `signals-relink`
    compares an issue's title with that, else with the title an adopted record was adopted with, else
    with the title the old 240-character builder makes, so records pushed before this release still
    match their issues. An adopted record is now compared with its issue's own title, which before
    could never match.
  - **The release beside the plugin version.** A record filed or adopted from now on stores the keel
    release as `release`, read from the marketplace manifest that lists this keel-workflow at the
    version running: two levels above the plugin in a clone or a directory source, or the
    marketplace's own copy under `~/.claude/plugins/marketplaces/<marketplace>` for an installed
    copy; otherwise `unknown`. An installed copy whose marketplace was updated without its plugins,
    past a release that left keel-workflow unchanged, reads that later release. A report's body shows
    `keel release` and `keel-workflow plugin` in two rows; a record from before shows its stored
    number as the plugin's and the release as `not recorded`. What `keel.json` stores and `status`
    compares is unchanged.
  - **No temp files.** `signals-push -Apply`, `resolve-signal -CloseIssue` and the new sighting
    comment send their JSON to `gh api --input -` on standard input, so nothing is written to `TEMP`.
  - **Attaching a known issue.** `signals-relink -Id <id> -Issue <n> [-Repo <owner/name>]` reads the
    issue, compares its title with the record's (either builder's for a record with no stored title)
    and previews `MATCH` or `MISMATCH`; `-Apply` writes `issue`, `issueUrl` and `issueTitle`. It
    refuses at exit 90, writing nothing, a record that already has a link, an issue another record
    holds on that repo, a record that is not OPEN, `-From` given as well, and a mismatch without
    `-Detail "<why>"`; with it the mismatch is attached and `attachReason` records the reason. It
    reads the issue through the same one call the re-point form uses.
  - **Sightings.** `signal -Id <open signal>` with `-Phase`, `-Detail` and `-Evidence` appends a
    dated sighting to that signal's `sightings` instead of filing a new signal, under the same
    evidence and quarantine rules; it refuses an unknown id at 94, a signal not OPEN at 90, a
    different `-Kind` at 90 and `-Title` at 90. `signals` lists each as a `SEEN` line under its
    signal, marked `POSTED` once sent. `signals-push` previews each unsent sighting as a comment
    below its signal, checks it for findings with the report, holds it the same way, and with
    `-Apply` posts it to the signal's issue on the repo the record names, after creating the issue
    first when the signal has none; each sighting records `commentedAt` and `commentUrl`, and a
    `-Clearance` used on it is recorded as `clearance`. `signals-push -Id` now accepts a pushed
    signal that has a sighting waiting. Comments are never read back.
  - **Skills.** `keel-close-workstream`'s signal command passes `-Title`, and it records a sighting
    with `signal -Id` for an open signal seen again. `keel-orchestrator`'s signals section describes
    sightings and the attach form.
- **`keel-project` 0.4.9: the index rebuild no longer needs `Get-FileHash`.** A Windows PowerShell
  child that inherits PowerShell 7's module path cannot load that cmdlet, and `keel-index.ps1` failed
  outright there. It now hashes with .NET's SHA-256 and keeps the same first 12 lowercase hex
  characters, so every stored index still compares.
- **Suites.** `test-signal-judgement.ps1` gains group RECORD (`-RecordOnly`) for short titles, the
  stored published title, the release, temp files, the attach form and sightings; group LINK's
  expected comment calls now read `--input -`, and group PUBLISH's fake reads the body from standard
  input. `test-outward-guard.ps1` counts eight outward calls, the sighting comment added, and its
  Group 9 runs the comment and the attach read under the guard.

## marketplace 0.83.0 - 2026-11-20

- **`keel-workflow` 0.75.0: a report is checked before it is published, and names its machine by a
  code.** `signals-push` sent each record's title and body as written, and `resolve-signal
  -CloseIssue` posted its comment the same way; nothing read the text in between. A record filed on
  a machine carries that machine's name in the body's Machine row, and its detail and evidence can
  carry a user folder path or a name the operator keeps private, so a push could publish any of them.
  - **What is checked.** The exact title and body a push would send, and the comment a close would
    post, for three things: an entry of `%USERPROFILE%\.keel\private-names.txt`, matched as the
    product's own private-names check matches it (anywhere and in any case, or a `word:` entry as a
    whole word with case); this machine's name, as a whole word in any case; and a user folder path,
    a drive letter and `Users` in any slash form, the JSON-escaped double backslash and the
    `/c/Users` form included. With no list, the output says the list was not checked and the other
    two checks still run. A list entry that check cannot read (empty, holding a non-ASCII character or
    a double quote) is a finding until its line is rewritten, as that check refuses it too.
  - **What a finding shows.** Its category, its list line for a list entry, and where it is: the
    title, or a numbered line of the body or comment. Never the matched text, because command output
    gets pasted into the places this protects. The preview prints each signal's findings after its
    body.
  - **Whether the destination is public.** Both routes print `Destination visibility: public`,
    `private` or `could not tell`, read with `gh repo view <slug> --json visibility` before
    anything is sent. It informs and never decides: a finding holds on a private repo too. The read
    honours `KEEL_OUTWARD` and fails open: blocked, failed or unclear, it says `could not tell`
    and the verb goes on. The preview now makes this one read.
  - **The hold, a tightening.** `signals-push -Apply` now sends nothing while any signal it would
    push holds a finding, and exits 95 naming them, so a push that succeeded before can now be
    refused. To send one anyway: `signals-push -Apply -Id <id> -Clearance "<why it may be
    published>"`. A clearance covers that one signal, needs `-Id` (exit 90 without it) and a reason
    (exit 95 with none), and is written to the record as `pushClearance`, with its time, reason and
    number of findings. `resolve-signal -CloseIssue` with a finding in its comment records the
    resolution, posts nothing, leaves the issue open and exits 0; re-running the same command with
    `-Clearance "<why>"` posts the comment and closes the issue, recording `commentClearance`.
    `-Clearance` on `resolve-signal` without `-CloseIssue` exits 90.
  - **The machine code.** A published issue's Machine row now shows this machine's code, `m-` and
    eight hexadecimal characters: random, made on first need and kept in `machine-code.txt` in the
    state home, and the same on every report from that state home. A preview may create that file. The
    record's own `machine` field still holds the name, locally. A `machine-code.txt` that holds no
    code is refused at exit 96; delete it and a new code is made.
  - **What a machine owes after updating.** Nothing until a push is held. Then preview that signal,
    read each finding against the body above it, and either leave it unsent or clear that one signal
    with the operator's reason.
  - The outward-call suite now counts seven calls that leave the machine, the visibility read being
    the seventh. The signal suite gains a group for these checks, one row of which runs the product's
    private-names check and this one over the same list and text and compares the list lines each
    flags.

## marketplace 0.82.0 - 2026-11-20

- **`keel-workflow` 0.74.0: a signal's GitHub issue is its repo and its number, and a new verb
  re-points records whose issues moved.** A record used to be matched by its issue number alone, so
  the same number on two repos read as one issue. Two things went wrong: `adopt-signal` refused a
  report filed on another repo because a record here held the same number on this machine's own,
  and `resolve-signal -CloseIssue` commented on and closed that number on this machine's
  destination, whatever repo the record's issue was on, which could be an unrelated issue.
  - **Where the repo comes from.** The link a record already stores, `issueUrl`
    (`https://github.com/<owner>/<name>/issues/<n>`). No field is added. A record with an issue
    and no link of that shape is read as on the destination the call uses (`-Repo` for that call,
    else the one chosen with `signals-target`), which is how every record was read before, so it
    behaves exactly as it did.
  - **`adopt-signal`** refuses only an issue held here on the same repo and number; the same number
    from another repo is adopted. The refusal now names the repo.
  - **`resolve-signal -CloseIssue`** comments on and closes the issue on the repo the record's link
    names. A destination must still be chosen before anything is sent. **A `-Repo` that names a
    different repo from the record's link is now refused at exit 90**, before the resolution is
    written, so nothing is written and nothing is sent; the message names the `signals-relink`
    command to run if the issue really moved. A `-Repo` that agrees with the link, or one given for
    a record with no link, works as before. Without `-CloseIssue`, `-Repo` is not checked.
  - **`signals-relink -From <owner/name> [-Repo <owner/name>] [-Id <ids>] [-Apply]`**, new. For
    every record linked to an issue on the `-From` repo it reads the issue with the same number on
    the new repo (`-Repo`, else the chosen destination) with `gh issue view`, and lists the old
    link, the new link and MATCH, MISMATCH or NOT READ, comparing the issue's title with the title
    `signals-push` builds for the record, whitespace collapsed. Without `-Apply` it writes
    nothing. With `-Apply` it rewrites `issueUrl` alone on each MATCH record, and on a MISMATCH
    record only when it is named with `-Id` (comma-separated ids); a NOT READ record is never
    rewritten. It takes the signal store's write lock on every run, the preview included, so a
    signal written meanwhile waits and may stop at exit 89. It honours `KEEL_OUTWARD` like the other
    signal verbs, refuses at 90 with no repo to point at, and exits 99 if any issue could not be read.
  - **What a machine owes after updating.** If this machine's reports were moved from one GitHub
    repo to another keeping their numbers, its records still link to the old repo, and the old
    repo's numbers now mean whatever that repo holds. Run
    `keel-state.ps1 signals-relink -From <old owner/name> -Repo <new owner/name>`, read the
    preview, run it again with `-Apply`, and for each MISMATCH you have checked by hand run it
    with `-Id <that id> -Apply`. A machine whose reports never moved has nothing to do: the
    preview says no record links to the old repo.
  - The wrapper's help text, `keel-orchestrator`'s section on signals crossing machines,
    `GETTING-STARTED.md`'s list of what leaves your machine and the README's requirements row
    say so.
- **`scripts/test-signal-judgement.ps1`** gains group LINK: seven pairs of a case, a control and a
  row asserting they differ, for adopting, closing and re-pointing, run against a fake `gh` that
  answers, plus a harness row. It now runs 117 cases. `-AgainstWrapper <path>` runs it against
  another copy of the wrapper, and `-LinkOnly` runs the new group alone.
- **`scripts/test-outward-guard.ps1`** covers six outward calls, with a group for
  `signals-relink`, and now parses the wrapper on every run and fails if its count of outward
  calls differs from the six it lists. It runs 36 cases and takes `-AgainstWrapper <path>`.
- **`scripts/test-shared-progress.ps1`**: the row comparing the state a project kept on one machine
  gets from this wrapper and from the committed one no longer fails on every uncommitted change to
  the wrapper. Whether `revisedAt` should differ is now read from the committed wrapper's own
  output, not from whether the two wrappers are the same file.

## marketplace 0.81.0 - 2026-11-12

- **`keel-workflow` 0.73.0: a phase can declare the work it needs delivered first, and `status`
  holds it back until then.** Without this, a phase that cannot start before another person's work
  lands was named as next anyway, and nothing said what it was waiting for. It works in every
  project, shared or kept on one machine. Keel records a need someone declared and never guesses
  one from a scope or a run order.
  - **Declaring needs.** `add-phase -Needs <ids>` and `revise-phase -Needs <ids>` take phase ids
    (`W4.2`) and whole workstream ids (`W4`), comma-separated; `revise-phase -Needs none` clears
    them. Each need is stored with the instant it was declared, and `revise-phase -Needs` replaces
    the list whole, dating each need afresh. Refused, writing nothing: an id that names no phase or
    workstream on this copy (exit 94; in a shared project the message says to pull first), an id
    of neither form, a phase needing itself or its own workstream, and a need that would close a
    cycle, whose path the message prints (each exit 90). `-Needs` cannot be combined with
    `-Correction`.
  - **When a need is met.** A phase need is met once that phase is delivered, or, if it was handed
    over, once the last phase of its hand-over chain is; a workstream need once the workstream is
    `DELIVERED`. An abandoned phase, an `ABANDONED` workstream or a chain ending in an abandoned
    successor never meets it.
  - **`status`.** A phase with a need not met is never named as next, for this person or on
    `others:`. For each such need it prints `<phase> waits on <id> (<stage>)`, with the owner in a
    shared project, or for a workstream its open phases. Two lines start `WARNING:` and so reach a
    resuming session: needed work that was abandoned (the need can never be met; the line says how
    to re-declare without it), and needed work revised after the need was declared (check the need
    still holds, then re-declare it). When nothing is runnable because of a need, the `next:` line
    says so.
  - **What counts as a revision.** A phase is revised when `revise-phase` changes its scope, actor,
    repos, due date, run order, owner or needs, and a workstream when `revise-workstream` changes
    its title or goals or a phase is added to it, not counting a hand-over's successor. Registering
    a prompt path, adding a correction, or setting a field to the value it already holds is not a
    revision: every phase after a workstream's first has its prompt registered when its predecessor
    delivers, and counting that would raise the warning on routine bookkeeping. Each real change is
    stamped `revisedAt`.
  - **What is stored.** A project kept on one machine gains `needs` on a phase only where one is
    declared, and `revisedAt` on a phase or workstream only when a revise changes one of the fields
    above. A shared project's `phase.json` and node files gain a `revisedAt` field, null until such
    a change; a file is not rewritten just because the field is new. `share-progress` carries both.
    **An older keel ignores both fields**: measured on such a state, the 0.80.0 wrapper names the
    held phase as next and prints no `waits on` line.
  - **`tree`** ends the line of a phase with needs with `needs: <ids>`, in declared order, before
    any `owner:`.
  - **Two more checks after a merge**, printed by `status`, `tree` and every write in a shared
    project: a need on an id with no file under `progress/`, and needs that form a cycle out of two
    writes each valid alone, naming every phase in it.
  - Skills: `keel-plan-workstream` and `keel-plan-epic`, while grounding, list the workstreams
    still open, those serving the same goal first and whose they are in a shared project, and ask
    whether the new work needs any; each need goes on the first phase that needs it, and an epic's
    "blocked by" becomes that need when the blocked workstream's phases are planned.
    `keel-orchestrator` says what a `waits on` line, the revised warning, the abandoned warning and
    the two new merge checks mean, and what to do about each.
- **`scripts/test-shared-progress.ps1`** gains a group for dependencies, on a project kept on one
  machine and on its own bare remote and two clones. It now runs 156 cases and took about nineteen
  minutes in one run, so `check-suite-docs.ps1 -Strict` and a push take that much longer.

## marketplace 0.80.0 - 2026-11-12

- **`keel-workflow` 0.72.0: in a project that shares its progress, each phase has one owner, and
  only the owner works on it.** Without this, two people could both run one phase and nothing
  would say so; the previous release recorded each phase's owner but enforced nothing. A project
  that keeps its progress on one machine has no owners and behaves exactly as before.
  - **Ownership.** `add-phase -Owner <person id>` sets a phase's owner, the person running it when
    left out; `revise-phase -Owner` changes it while the phase is still `planned`, and is refused
    once work has started. A person id that no person file holds is refused (exit 90), and `-Owner`
    in a project that keeps its progress on one machine is refused too.
  - **Exit 88, new: not the owner.** Anyone but the owner is refused, writing nothing, on
    `set-stage`, `set-waiting`, `clear-waiting`, `record-verdict`, `new-iteration` and `lift-cap`
    at any stage, and on `revise-phase` and `abandon -Phase` once the phase has left `planned`. The
    message names the owner by name and person id, and how to hand the phase over. `note-friction`
    and `open-question` stay open to anyone, and while a phase is `planned` anyone may revise it,
    change its owner or abandon it.
  - **`hand-over -Phase <X> -To <person id> -Detail "<why>"`, a new verb**, for a started phase whose
    owner cannot finish it. Anyone may run it. It ends X as `handed-over`, recording the successor
    and the reason, and creates the successor, X's id with the next free letter (W5.2b, then
    W5.2c), carrying X's scope, actor, repos, due date, prompt path, needs and run order, owned by
    the person named, continuing X, and `planned`. It is refused, writing nothing (exit 90), on a
    phase that is `planned` (change its owner instead), `delivered`, `abandoned` or already
    handed over, when the person names no person file, and in a project that keeps its progress
    on one machine.
  - **A handed-over phase is finished.** Every verb the owner check covers refuses it (exit 90),
    naming its successor, `abandon -Phase` included, so it can never also read as abandoned;
    `note-friction`, `open-question` and `revise-phase -Correction` still accept entries on it, from
    anyone. `close` counts it as done and the workstream's folded file records the hand-over;
    `abandon -Ws` refuses a workstream with one, as it refuses one with a delivered phase; the run
    order check of `add-phase` and `revise-phase` sets it aside, so its successor takes its order;
    and `status` no longer lists it as overdue or warns about its verify fingerprint.
  - **`status` and `tree`** print a handed-over phase as `handed-over -> <successor>`, and end the
    line of each phase not yet finished with `owner: <name> (<person id>)`.
  - **One more check after a merge**: a gate entry written by someone other than the phase's owner,
    which only a merge can produce (one person changed a planned phase's owner while another,
    offline, started it). `status`, `tree` and every write name the entry and both people.
  - **`revise-phase -Correction`** now also refuses to be combined with `-Owner`, and a non-owner
    using it on a started phase gets exit 88 rather than advice to use `-Scope`.
  - Skills: `keel-orchestrator` says what a phase's owner means, what exit 88 means, and when and
    how to hand a phase over; `keel-run-phase` says a phase is run only by its owner, who gives the
    human verdict, and that a successor grounds against its predecessor's artifacts, re-measured,
    never inherited; `keel-plan-workstream` says each phase is planned with an owner, work two
    people would share is planned as two phases, and a successor is pushed at once.
- **`scripts/test-shared-progress.ps1`** gains a group for ownership and hand-over, on its own bare
  remote and two clones. It now runs 118 cases and took about twenty minutes in one run, so
  `check-suite-docs.ps1 -Strict` and a push take that much longer.

## marketplace 0.79.0 - 2026-11-11

**The first release that carries shared progress.** 0.78.0, which added it, was never released on
its own: it waited for the warnings below, so that no installed copy could share a project's
progress without them. Updating to this release brings both.

- **`keel-workflow` 0.71.0: in a project that shares its progress, `status`, `tree` and handoffs
  say what this copy can and cannot see.** Several people now write one project's progress, so a
  copy can lack someone's pushed work, a merge can join two writes into a whole the wrapper would
  have refused from one writer, and two people's handoffs can collide. A project that keeps its
  progress on one machine prints exactly what it did.
  - **The behind reading.** Before anything else, `status` prints `WARNING: the remote 'origin'
    holds work this copy has not pulled` when the remote's commit is not in this clone, and
    `WARNING: this copy is <n> commit(s) behind 'origin'` once it is fetched and not merged, each
    saying to pull before acting on what follows. Both come from the `git ls-remote` reading
    `status` already took, so there is no new network call. When that reading cannot be taken (the
    remote cannot be reached, outward acts are blocked, the copy is on a detached HEAD, or git is
    missing) it says so rather than staying silent.
  - **The uncommitted count:** `WARNING: <n> progress file(s) written here are not committed, so
    nobody else can see them`. It counts files, so a new folder counts every file in it. It leaves
    out files in a subfolder of a phase's artifacts folder, where only scratch belongs, and that
    scratch should be kept in the per-machine phase folder instead: nothing stops a commit from
    taking it.
  - **The check after a merge.** `status`, `tree` and every write print one `WARNING: after a merge,
    ...` line per broken rule: two phases of one workstream at one run order (neither is then named
    as next, and another phase at that order is still refused, exit 92); a phase still open under a
    closed or abandoned workstream; a phase's workstream, a node's parent, a workstream's goal, a
    phase's owner or the phase it continues naming no file; and one machine listed by two person
    files. Other writes go on, so a clash in one workstream does not stop work in another.
  - **`next:` is this person's**: the lowest-order runnable phase owned by the person this machine is
    registered as. A new `others:` line names each other person's next, by name. A machine no
    person file lists, or two do, is shown the whole project's next and told so.
  - **Authored handoffs.** `handoff` names its file `<person id>-<slug>.md` and adds `Author:` and
    `Machine:` lines, so two people ending with the same words no longer overwrite each other. Like
    every other write in a shared project it is refused, writing nothing, from a machine no person
    file lists (exit 95, naming `join`) or two do (exit 90). `status` names the newest handoff by
    time compared as an instant, not as text, so one written in a time zone behind this one is not
    passed over, with its author; and names your own newest too, as `your last handoff:`, when it
    is a different file. Each is marked STALE once the project's progress has moved past it.
  - **Until a later release, a shared project records each phase's owner without enforcing it:**
    `next:` reads the owner, but nothing yet refuses one person's gates on another person's phase.
  - Skills: `keel-orchestrator` says that resuming a shared project starts with the behind reading
    (pull first), that `next:` is this person's, and what each warning after a merge means and how
    to repair it; `using-keel` says a fresh clone of a shared project needs no `init-project`, that
    each machine runs `join`, and that `status` says when the copy is behind.
- **`scripts/test-shared-progress.ps1`** gains a group for all of this, on its own bare remote and
  two clones, with controls that must behave differently. It now takes about nine minutes, so
  `check-suite-docs.ps1 -Strict` and a push take that much longer.

## marketplace 0.78.0 - 2026-11-11

**Not yet released.** This is on `main` only: no installed copy gets it until the release that also
adds the warnings a shared project needs (a copy that has not pulled a colleague's work, a merge
that breaks a rule, whose handoff is newest). A keel clone used as a directory source has it now,
and it changes nothing for a project until that project runs `share-progress`.

- **`keel-workflow` 0.70.0: a project can keep its progress in its own repo, so several people can
  work on it.** Until now a project's progress (its goals, workstreams, phases, gate verdicts,
  friction and questions) lived in one `state.json` on one machine, so a second person had no way
  to see it. A project can now keep it under `progress/` in the project repo instead, one small
  JSON file per item and per entry, each naming who wrote it by a person id, the machine, and the
  time with its UTC offset. Two people writing different things write different files, so git
  merges them; one id taken by both is a conflict on that item's file at the second pull. The
  layout can be read without keel.
  - **`share-progress`**, a new verb, makes the switch once. It writes `progress/` from
    `state.json`, marking every file as exported and naming the person who ran it; folds each
    closed or abandoned workstream into one file; copies each phase's gate artifacts into
    `progress/phases/<id>/artifacts/`; writes `"progress": "repo"` into `keel.json`; and renames
    `state.json` to `state.json.shared-<date>`, so an older keel refuses the project (exit 91)
    rather than writing to a copy nobody reads. It commits nothing. It refuses a project with
    quarantine on, one with `git: false`, a repo with uncommitted changes and a project already
    shared (exit 90), and a repo with no `git config user.name` (exit 95).
  - **`join`**, a new verb, registers a machine as a person: a new one, named once from `git config
    user.name`, or with `-As <person id>` one already listed. `join -As <id> -Clear` takes the
    machine off that person. A write from a machine no person lists is refused (exit 95, naming
    `join`), and so is one from a machine two people list after a merge (exit 90), until one drops
    it.
  - A workstream that is closed or abandoned folds its phases into `progress/closed/<id>.json`, so
    a long project does not grow thousands of small files. Its gate artifacts stay where they are.
  - In a shared project the phase directory, where gate artifacts go, is
    `progress/phases/<id>/artifacts/`; the per-machine phase folder stays as that machine's scratch.
    The verify fingerprint does not warn about files under `progress/`, which the gates themselves
    write. `list` shows a shared project as `shared`, with its root.
  - A project that does not choose this is unchanged: nothing it stores, prints or writes moves.
  - Not in this version: each phase records an `owner` (whoever planned it) that nothing enforces
    yet, and a `needs` list that nothing reads yet.
  - Skills: `keel-run-phase` and its verifier brief say where artifacts and scratch go;
    `keel-close-workstream` routes everyone's friction, each entry naming its author;
    `keel-plan-project` describes the choice and that quarantine excludes it; `keel-plan-workstream`
    and `keel-plan-epic` name the person in a "Decided by the operator" label and commit and push an
    approved plan at once, since a number is taken by whoever pushes it first.
- **`keel-project` 0.4.8:** `keel-project-context` reads a shared project's gate artifacts from
  `progress/`.
- **`DESIGN-CHARTER.md`:** P15 lets a project that shares its progress keep it in its repo, while
  sensitive material still never leaves the quarantine; P26 is retitled "A signal crosses machines
  only as a report", since signals are no longer the only thing that crosses.
- **`scripts/test-shared-progress.ps1`**, a new suite, checks the layout, two clones merging, the
  people refusals, the fold, the export and its refusals, and that a project that has not chosen
  this is unchanged. `check-suite-docs.ps1 -Strict` runs it; it takes about five minutes.
  `scripts/test-concurrent-writes.ps1 -Shared` runs the write-lock suite on shared projects, with a
  case in which two writers rewrite one file.

## marketplace 0.77.0 - 2026-11-10

- **`keel-workflow` 0.69.0: two keel commands writing at once no longer lose a write.** Two
  sessions on one machine writing the same project at overlapping moments, for example one
  recording a gate while another adds a phase, each read the whole state file, changed their own
  copy and wrote it back, so one of the two writes vanished while both commands reported success.
  `keel-state.ps1` now takes a lock before it reads anything it will rewrite and lets go after
  writing, so the second command waits and then works on the first one's result. The lock covers
  three stores: a project's `state.json`, its `keel.json`, and the signal store, where a new
  signal also takes its number in a way two filings cannot share. A command that cannot get the
  lock within 10 seconds stops with a new exit code, **89**, and writes nothing; the answer is to
  run it again. A command also checks, immediately before writing, that the file has not changed
  since it read it, and stops with 89 if it has; that is how it notices a writer that takes no
  lock, such as an older copy of keel. The exception is the record of a GitHub call just made (a
  pushed issue's number, a closing comment, a closed issue), which is merged into the file as it
  then stands rather than refused, so the call is never left unrecorded. An older copy writing at
  the same moment can still lose a write, its own or this command's, so run one version of keel
  at a time. A signal push holds the signal store across its GitHub calls, so a judgement or resolution
  started during a long push can also stop with 89. Nothing else changes: no
  verb, argument, state field or existing exit code.
- **`scripts/test-concurrent-writes.ps1`** runs overlapping writes against all three stores and
  checks that none is lost, plus a held lock, a file changed under a waiting command and a command
  killed while holding the lock. `check-suite-docs.ps1 -Strict` runs it; it takes about a minute.
- **`ARCHITECTURE.html`'s exit-code table** lists 89, and now 99 as well, which it had left out.

## marketplace 0.76.0 - 2026-11-05

- **`keel-workflow` 0.68.7: creating a project.** `keel-plan-project` now has the session make the
  project folder before it runs `init-project`. The steps were the other way round, and
  `init-project` refuses a folder that does not exist, so following them in the order written
  failed. The skill also now says to write the handoff note before handing back, and not to commit
  it, and `keel-orchestrator`'s "Ending a session" names project creation as the one boundary whose
  handoff and rebuilt index are left uncommitted. The two skills had given that session opposite
  instructions: one said never to commit, the other to commit the handoff.
- **Worded for a public repository.** The README, `GETTING-STARTED.md` and the marketplace manifest
  no longer say the repository is private or that installing needs read access to it, and the
  three plugins' marketplace category is `productivity` in place of `internal`.
- **The README gives keel's token cost**, as Claude Code estimates it, so a reader can see what
  keel adds to every session before installing it.
- **`scripts/gen-suite-docs.ps1` keeps each file's byte-order mark as it finds it.** Under Windows
  PowerShell 5.1 it wrote `README.md` back with a mark the file did not have, so rebuilding the
  inventory changed the file's first line. `ARCHITECTURE.html` keeps its mark, because it declares
  no character set and the mark is what tells a browser it is UTF-8.
- **`GETTING-STARTED.md` matches what a first session does.** keel was installed in a fresh, separate
  Claude Code setup and the guide's first project was walked through step by step. Step 4 said keel
  asks where the project goes even when you are already in the folder; a request that says "here",
  as the guide's example does, already answers that, so the session goes straight to the preview.
  Step 6 now says the session may also ask a few facts for the charter. The guide also says how to
  keep `KEEL_OUTWARD=block` on permanently, through the `env` key of Claude Code's settings file,
  which in that setup blocked the remote read as the variable does, and did not once the key was
  removed.

## marketplace 0.75.0 - 2026-11-03

The first entry in this file. It describes keel as it stands at this version; the development
history before it is not part of this repository.

Keel is three plugins:

- **`keel-workflow` 0.68.6.** `using-keel` is the entry point and `keel-orchestrator` the one skill
  that dispatches the others. `keel-plan-project`, `keel-plan-epic` and `keel-plan-workstream` plan
  at each level, `keel-run-phase` runs one phase through its eight gates, and
  `keel-close-workstream` closes a workstream. Its wrapper, `keel-state.ps1`, is the only writer of
  each project's state, which is kept under `%USERPROFILE%\.keel\` and never in a git repo.
- **`keel-project` 0.4.7.** `keel-project-context` answers what a project already knows from its
  files, through a generated document index that it checks against disk before use.
- **`keel-surfaces` 0.3.2.** `keel-tracker` projects a project's plan onto Trello, Jira or GitHub
  Projects and never reads the tracker back as truth. `keel-documents` reads documents a project
  does not own, such as Drive files and PDFs, and never writes to them.

Keel runs on Windows. It installs from this repository's `release` branch: the commands are in
`README.md` under "Install", and `GETTING-STARTED.md` walks through a first project.
