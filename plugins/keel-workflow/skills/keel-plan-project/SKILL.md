---
name: keel-plan-project
description: Creates a NEW keel project - its folder, its keel.json, its CHARTER.md and its goals. The ONLY keel skill permitted to run outside a project folder, because it is the one that creates the folder. Dispatched by keel-orchestrator only; never a session entry point. Use when an ask has no project to belong to yet - "I want to sort out my tax returns", "let's plan the crypto apps", "I need to handle the house sale". Settles the three per-project choices that every later session reads before anything else - git, tracker, quarantine - and writes the goals that all future work must claim. It does NOT decompose into epics or workstreams and never plans a phase; a project that ends its first session with goals and a scope boundary is complete work.
---

# Plan a new project

A project is a folder with a `keel.json` at its root, and everything in it. This skill creates one
and stops.

**What "done" looks like for this skill:** a folder, a `keel.json`, a `CHARTER.md` with goals and a
scope boundary, and registered goals in state. **No epics, no workstreams, no phases.** Decomposing
is `keel-plan-epic`'s job, in a later step or a later session.

## Step 1 — is this actually a new project?

Check first. Two failure modes, opposite directions:

```
keel-state.ps1 list
```

- **It already exists** → this is work *in* that project. Hand back to `keel-orchestrator` with the
  path, and let it resolve normally.
- **It is a piece of an existing project** → *"add a wallet recovery screen"* is not a project when
  a crypto project already exists. A second project means a second `keel.json`, a second set of
  goals, and a boundary that has to be maintained. Recommend against it (charter P12), and put the
  choice to the operator with what a second project would cost and what it would buy: the default is
  the recommendation, not the answer - see "An earlier decision is a tradeoff to show, not a rule to
  enforce" in `keel-orchestrator/SKILL.md`.

**A project is warranted when it has its own goals** — its own definition of done that the existing
projects do not share.

## Step 2 — the three choices, asked once

These go into `keel.json` and every later session reads them before anything else. Ask in plain
text, with a recommendation, not an open question.

Write the question under **"Asking the human — the question must be answerable without keel's
vocabulary"** in `keel-orchestrator/SKILL.md`, which is already loaded in this session.

### `git` — is this folder a repo?

| Choose git when | Choose no git when |
|---|---|
| The project produces code, documents, or anything whose history matters | The project is mostly errands and third-party correspondence |
| You want the plan's own evolution auditable | The folder would only ever hold pointers to material that lives elsewhere |

**Recommend git.** The self-improvement loop reads what changed; without history it reads nothing.

### `tracker` — `none` / `trello` / `jira` / `github`

The files are always the authority (charter P10). A tracker is a **projection** you can triage from
a phone, never read back as truth.

| | Fits |
|---|---|
| `none` | Anything sensitive, or a project small enough to hold in the plan tree. **The safe default.** |
| `trello` | You want at-a-glance status on a phone. Flat model, so deep trees flatten on projection. |
| `jira` | Genuinely many items. Heavy field model. |
| `github` | The project's repos are on GitHub and you want one place. |

**Recommend `none` for a first project, and add a tracker when you notice you want one.** An unused
board is a second authority that rots.

### `quarantine` — does this project carry sensitive material?

Financial documents, government identifiers, health information, keys, seed phrases, anything about
a named third party.

**If in doubt, yes.** It creates `%USERPROFILE%\.keel\quarantine\<project>\`, outside every repo,
and commits the project to redaction **at extraction** (charter P23) — an unredacted fact never
reaches a downstream artifact, redacted or not.

## Step 3 — create it

**Where does it go? Derive it, then ask.** If a project resolves from the working directory, its
parent is the projects root — new projects are siblings of it, never nested inside it. If nothing
resolves, **ask**: do not guess, and do not name a default. There is no configured root and there
should not be one; the folder a project lives in is a fact about the filesystem, not a setting.

Preview the exact folder path and the exact `keel.json` before writing (charter P6) — creating a
project is not inside any change set the human has already approved, so the carve-out in "Whether to
ask, or to act and report — reversibility decides" (`keel-orchestrator/SKILL.md`) does not reach it.

Then make the project folder itself, if it is not there yet. `init-project` writes `keel.json` into
a folder that already exists and refuses one that does not (exit 90); a folder the human made first
and opened the session in is already there.

```
New-Item -ItemType Directory -Path "<parent>\<slug>"
```

Then:

```
keel-state.ps1 init-project -Path "<parent>\<slug>" -Title "<Title>" -Tracker <kind> [-NoGit] [-Quarantine]
```

The slug is the folder name, lowercase and hyphenated. It becomes the project's identity in state,
in signals and in every record — choose it once and do not rename it.

The wrapper refuses (exit 93) if the folder would nest inside an existing project. Projects are
siblings; nesting would make the upward walk for the active project ambiguous (charter P20).

Then create the rest of the folder structure inside it:

```
<project>\
  keel.json                written by the wrapper
  CHARTER.md               from templates/PROJECT_CHARTER_TEMPLATE.md
  plan\epics\              decomposition ledgers
  plan\workstreams\        specs
  plan\prompts\            one per phase, written for a fresh session
  record\                  delivery records
  reference\               slow project knowledge, and the generated INDEX.md
  repos\                   only if this project produces code
  private\                 gitignored scratch; only if git is on
```

If `git` is on, `git init` and write a `.gitignore` that excludes `private/`. **Do not commit** —
that is the human's call, always. That includes the handoff and the rebuilt index this session
leaves behind at Step 6.

## Step 3b — declare the repos, if there are any

**A project may span several repos, and they do not all have to live inside its folder.** Declare
each one by a logical name; the name becomes part of `changes-<name>.patch`, so a phase's evidence
is unambiguous across repos.

```
keel-state.ps1 add-repo -Name wallet-app -RepoPath repos/wallet-app -Branch main
keel-state.ps1 add-repo -Name legacy-api -RepoPath "<absolute path to a repo that lives elsewhere>" -Branch master -Detail "external - another estate's; tracks master, not main"
```

| Path form | Means | Use for |
|---|---|---|
| **relative, staying inside** (`repos/wallet-app`) | inside the project folder | repos this project creates and owns |
| **absolute** (`C:\...\legacy-api`), or **relative and leaving the folder** (`../legacy-api`) | **external**: referenced, never moved | repos that already exist elsewhere, or are shared between projects |

**Never move or copy an existing repo into the project folder to satisfy the layout.** It has its
own remote, its own CI and its own history; keel references it where it is and does not own it.
Nothing is written to an external repo without a preview, same as anything else outward-facing.

**Declare the branch.** Per-repo branch differences are a real source of the multi-repo trap — one
estate on this machine has repos tracking `master` while the rest track `main`. `repos` reports a
mismatch, a detached HEAD, a missing path, or a directory that is not a repo at all:

```
keel-state.ps1 repos
```

That is measured live, every time. A repo declared but gone is a phase that cannot produce its
patch, and it is better to learn that now than at the implement gate.

**A phase may only declare a registered repo** — the wrapper refuses an unknown name with exit 94.
That is what stops `walletapp` quietly becoming a repo whose patch never arrives.

**Then build the document index**, so the project is findable from its first session. Run the
command under "Rebuilding the index" in `keel-project-context`, loading that skill first if this
session has not; only that skill can give the path to `keel-index.ps1` for the copy of keel on this
machine.

This is what makes the project's own documentation accumulate into something a session six months
from now can search rather than re-read. It indexes `CHARTER.md`, every plan and record document,
and everything close-out routes into `reference/` — by **heading**, never by line number.
`repos/` and `private/` are deliberately excluded, and the quarantine is never touched.

## Step 4 — the charter: what "done" means, why it is worth doing, and what it excludes

Fill `CHARTER.md` from the template. Three sections carry the weight:

**What done means.** Concrete and falsifiable. *"Sort out my taxes"* is not done-able; *"all five
outstanding returns filed and accepted, and a monthly routine that stops this recurring"* is.

**It is the operator's standard, so say whose words it is in**, and when new work collides with it,
put the collision to them rather than refusing the work on its strength - see "An earlier decision is
a tradeoff to show, not a rule to enforce" in `keel-orchestrator/SKILL.md`.

**Why this is worth doing — the value statement.** Keel will plan, gate, verify and ship whatever it
is asked for, to a high standard, and without this section there would be no moment at which the
ask itself was examined. Ask for **all three parts, by name**, and
write each into the charter:

1. **Who benefits** — and how, concretely. A named person or role, and the difference it makes to
   them. Not "users", and not "me, later".
2. **How the benefit is recognised** — what would be observably different if this worked. Something
   you could check without re-reading the plan.
3. **What would make abandoning this the right call** — the abandonment condition.

**The third part is the one that does the work, and it is the one that gets dropped.** A project
with no stated abandonment condition cannot be abandoned on evidence, only on exhaustion — it runs
until whoever is running it is tired of it, which is a worse reason and arrives much later. Do not
accept two of the three. If the honest answer is *"nothing would make abandoning this right"*, that
is an answer — write it down with its reason, because a project someone would finish regardless is a
different thing from one nobody has thought about stopping.

**Ask; do not draft it for them.** These are three questions the human answers, not a process keel
runs. Keel does no research and validates no premise — `DESIGN-CHARTER.md`'s practice table rejects
the apparatus around this in rows 2, 4, 5 and 6, and P12 is why nothing heavier is here. It is
answered **once**, at intake: a project's charter records that its value goal is deliberately not a
per-phase gate, and a value question asked eight times per workstream is the ceremony P13 predicts
will be routed around. Close-out reads it back after delivery.

**"No research" above means these three answers only:** whether to research the project's own
subject, and how far, is the operator's call like any other, and a plan that would rule research out
asks them first - see "An earlier decision is a tradeoff to show, not a rule to enforce" in
`keel-orchestrator/SKILL.md`.

**The scope boundary.** What this project does **not** cover, argued. At project scale this is the
most valuable section in the document — the boundary is what stops a project growing a new area
every month. Point excluded work at another project or at "not doing", never leave it implied.

**An exclusion the operator could plausibly want back is theirs to make, not yours:** ask before you
write it, and record a preference they want every workstream to respect once, in the charter's
Decisions, labelled as theirs - see "An earlier decision is a tradeoff to show, not a rule to enforce"
in `keel-orchestrator/SKILL.md`.

## Step 5 — goals

Goals are **flat and cross-cutting** (charter P22), not a level of the tree. Any workstream can
claim several; that is the point.

```
keel-state.ps1 add-goal -Id G1 -Text "<what is true when this is done>"
```

Write each goal as a **state of the world**, not an activity. *"Rebuild the 2023 ledger"* is work;
*"every return filed and accepted"* is a goal. If a goal reads like a task, it is a workstream that
has not found its goal yet.

**Three to five goals is usually right.** One goal means the project is a workstream. Ten means the
boundary in Step 4 is not doing its job.

Then check coverage is at least *askable*:

```
keel-state.ps1 goal-coverage
```

Every goal will report `UNCLAIMED` at this point, which is correct — nothing is decomposed yet.

**A goal that is deliberately not being worked yet gets said so, rather than left to nag.** Once
decomposition starts, a goal whose workstream has not been planned is still `UNCLAIMED`, and
`status` warns about it every session. Declare it instead:

```
keel-state.ps1 set-goal-status -Id G3 -Status UNADDRESSED -Detail "<why nothing claims it yet>"
```

The reason is required (exit 95). `-Status OPEN` puts it back when a workstream is ready to claim
it, and the wrapper refuses `UNADDRESSED` on a goal a workstream already points at. What this is
*not* for is a goal you have simply forgotten — the warning is doing its job in that case.

## Step 6 — stop

Say plainly what exists and what does not:

> *Created `tax-returns` with four goals, a value statement and a scope boundary. Nothing is
> decomposed yet — no epics, no workstreams, no phases. Next session: `keel-plan-epic` to break G1
> and G2 into areas.*

**A first session that ends here is complete work** (charter P16). The temptation is to keep going
into decomposition while the context is warm. Resist it: decomposition done in the same breath as
goal-setting tends to reproduce the goals as epics, one for one, which is a tree that carries no
information.

**Before you hand back, write the handoff, and do not commit it.** This is the boundary "A project
planned, nothing decomposed yet" in the "Ending a session" section of `keel-orchestrator/SKILL.md`,
and that section names it as its one exception: write, repair and rebuild in its order, and stop
before the commit, which stays the human's.

## Must not

- **Create a project to be helpful.** A `keel.json` is written once and the slug is permanent.
  Ambiguity defaults to asking.
- **Decompose.** No epics, no workstreams, no phases here.
- **Write goals that are tasks.** A goal is a state of the world.
- **Guess the three choices.** Especially `quarantine` — the cost of a wrong `no` is unrecoverable,
  and the cost of a wrong `yes` is an unused directory.
- **Accept a value statement missing its abandonment condition.** Two of the three parts is not the
  section — it is the two comfortable parts of it.
- **Commit anything**, the handoff and the rebuilt index included. `git init` yes; `git commit` is
  the human's.
- **Put sensitive material in the project folder** while deciding whether it is sensitive.
