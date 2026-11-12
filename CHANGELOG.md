# Changelog

All notable changes to the keel marketplace. Versions are per plugin; the marketplace version
at the top of each entry is the one in `.claude-plugin/marketplace.json`. Each entry says what
changed and why.

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
