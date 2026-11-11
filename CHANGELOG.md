# Changelog

All notable changes to the keel marketplace. Versions are per plugin; the marketplace version
at the top of each entry is the one in `.claude-plugin/marketplace.json`. Each entry says what
changed and why.

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
