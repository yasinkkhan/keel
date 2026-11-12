# Changelog

All notable changes to the keel marketplace. Versions are per plugin; the marketplace version
at the top of each entry is the one in `.claude-plugin/marketplace.json`. Each entry says what
changed and why.

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
