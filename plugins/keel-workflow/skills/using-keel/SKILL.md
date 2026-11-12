---
name: using-keel
description: Activates keel - the REQUIRED, ALWAYS-FIRST entry point for ANY work inside a keel project folder - any folder with a keel.json at or above it - however small. Invoke BEFORE reading files, asking questions, or calling any other keel-* skill whenever the request touches a project at all - a named workstream ("W4", "phase W4.2"), a tracker card, OR a bare request like "fix this", "what should I do next", "chase the accountant", "add a screen", "file the return", "start a new project". Small, obvious and one-line tasks route through here TOO; that is the point, not an exception. What must never happen is a bare verb reaching a stage skill directly - keel-plan-project, keel-plan-epic, keel-plan-workstream, keel-run-phase and keel-close-workstream are not entry points, because a stage reached directly is a stage reached without its gates. Only a pure question about how keel itself works, with no work requested, is answered read-only instead.
---

# Using keel

Keel runs planning and delivery for every keel project on this machine. A project is any folder with
a `keel.json`; they are siblings under whatever root you keep them in. This skill is how a session
enters one.

**You are not here to do the work.** You are here to establish where you are and hand off.

## Step 1 — where am I?

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "${CLAUDE_PLUGIN_ROOT}/skills/keel-orchestrator/wrappers/keel-state.ps1" resolve
```

The active project is **derived from the working directory** (charter P20) — the wrapper walks up
to the nearest `keel.json`. Never ask the user which project this is when a command can answer it,
and never carry a project name forward from earlier in the conversation.

| Result | What it means | Do |
|---|---|---|
| Exit 0, a project | You are inside a project | Step 2 |
| **Exit 91**, no project | Not in a project folder | Step 3 |

## Step 2 — read `keel.json` before anything else

It carries the three per-project choices, and a fourth once a project shares its progress, and
skills behave differently under each:

- **`git`** — whether this project's folder is a repo. Decides whether "commit" is even a step.
- **`tracker`** — `none` / `trello` / `jira` / `github`. Decides whether there is a projection to
  update. The tracker is *never* read back as truth (charter P10) — the files are the authority.
- **`quarantine`** — whether this project has sensitive material under
  `%USERPROFILE%\.keel\quarantine\<project>\`. If true, treat every document as potentially
  identifying until proven otherwise, and redact **at extraction** (charter P23).
- **`progress`**: if `"repo"`, the project shares its progress through its own repo, under
  `progress/`, so several people can work on it (charter P15). A fresh clone of it needs no
  `init-project`: its state came with the clone. Run `join` once on each machine, so its writes name
  a person (a write from a machine no person lists is refused at exit 95, naming `join`), and pull
  before starting: `status` says when this copy is behind the remote.

Then **dispatch `keel-orchestrator`**. It owns everything from here: classification, the plan tree,
dispatching stages, and refusing to advance when a gate is not satisfied.

## Step 3 — no project here

**The resolve walk goes UP, never down.** Sitting in the projects root itself finds nothing, even
though every project is a folder directly beneath it. That is correct and deliberate — a projects
root with its own `keel.json` would make every project nest inside it — but it means "exit 91" does
**not** mean "no projects exist".

So before deciding anything, ask keel what it knows:

```
keel-state.ps1 list
```

Three cases:

- **The user is starting something new** — *"I want to sort out my tax returns"*, *"let's plan the
  crypto apps"*, and `list` shows nothing matching. Dispatch `keel-orchestrator`, which routes to
  `keel-plan-project`. That is the one skill allowed to run outside a project folder, because it is
  the one that creates the folder.

- **The user means a project that already exists** — they name it, or `list` shows an obvious match.
  **Say which folder it is and ask them to reopen the session there.** Do not silently drive it with
  `-Path` from the parent: every verb accepts `-Path`, so it would appear to work, and then a
  session that forgets it writes nothing and reports 91 with no explanation. The folder is the
  selection (charter P20).

  > *"`crypto-apps` exists at the path `list` printed. Open a session in that folder
  > and I will pick it up — from here I would be guessing which project you mean on every command."*

  If they explicitly want to continue from the parent anyway, that is their call: pass `-Path` on
  every wrapper call and say once that you are doing so.

  **Before you hand back, write the handoff** — see "Ending a session — write the handoff before you hand back" in `keel-orchestrator/SKILL.md`. This is the one boundary where the project is not the working directory, so the verb needs `-Path`.

- **The user is just asking a question**, or is in an unrelated directory. Say where you are, say no
  project resolved, and ask rather than guessing. Do **not** create a project to be helpful — a
  project folder is a commitment and `keel.json` is written once.

## What routes here

**Everything that touches a project.** Including, and especially, the small things:

> "fix the importer" · "what should I work on" · "the accountant replied" · "add a recovery screen"
> · "W4.2 is done" · "file it" · "start phase 2" · "this is blocked" · "close out W4"

Size never decides *whether* keel runs — only how much artifact it produces. A one-line change still
gets grounding, a positive control, an independent verify, and a delivery record. Small changes are
exactly where unmeasured assumptions ship, because nobody thought they were worth checking.

## What does NOT route here

A pure question about how keel itself works — *"what are the gate names"*, *"what does exit 93
mean"* — is answered read-only from `CLAUDE.md`, `DESIGN-CHARTER.md` and the wrapper's own help.
No dispatch, no state written.

## Must not

- **Dispatch a stage skill directly.** `keel-run-phase`, `keel-plan-*` and `keel-close-workstream`
  are reached only through `keel-orchestrator`, even when the user's words match one exactly
  ("plan this", "implement phase 3", "close it out"). A stage reached directly is a stage reached
  without its gates and without the project's state (charter P1).
- **Start work here.** Not one file read for the task itself, not one edit. Resolve, read
  `keel.json`, dispatch.
- **Edit `plugins/**` from a project session.** If keel itself is wrong, that is a *signal*
  (charter P25), filed through the wrapper and triaged in keel. Say so and carry on.
- **Assume the project from the conversation.** Two windows can be open on two projects. The
  working directory is the answer.
