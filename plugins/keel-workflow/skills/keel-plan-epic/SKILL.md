---
name: keel-plan-epic
description: Decomposes work too large for one workstream into several - the EPIC level. Dispatched by keel-orchestrator only; never a session entry point. Use when an ask spans independently deliverable areas that could ship on different days, in a different order, each a reasonable workstream alone - "reconstruct five years of books", "ship a self-custody wallet", "migrate off X". Planning an epic SPANS SESSIONS by design - it writes plan/epics/E<n>_name.md carrying a decomposition ledger, so a later session sees which areas became workstreams and which are still NOT-DECOMPOSED and resumes there instead of starting over. Epics nest inside epics at any depth, and each one must state in one line what it groups. Produces the ledger, the workstream manifest and their declared order; it does NOT plan any child workstream's phases, which is keel-plan-workstream's job, and it never implements.
---

# Plan an epic

An epic is a **container**, and in keel containers nest as deep as the project needs (charter P17):

```
project
  E1  epic          a decomposition record + a manifest
   +- E2  epic      an epic may contain epics, at any depth
       +- W4  workstream   a spec + phases, independently deliverable
           +- W4.2 phase   one sitting, eight gates
```

**Every epic must state in one line what it GROUPS** — not what it is called. That line is the whole
defence against unbounded depth: it forces each rung to justify itself, and an epic whose "groups"
line restates its title is refused by the wrapper (exit 93).

## Is this actually an epic?

**Yes** when the work contains **independently deliverable areas** — pieces that could be finished
on different days, in a different order, each a reasonable workstream on its own.

**No** when it is one thing with many steps. A twelve-phase workstream is fine. Splitting it into
epics because the number is large adds a rung carrying no information.

The test is not size. It is: **would a reasonable person plan these separately?**

## Session 1 — inventory, not decomposition

**You cannot decompose something nobody has enumerated.** For *"reconstruct five years of books"*,
the first job is establishing what "five years" actually contains: which years, which accounts,
which are already partly done, what evidence survives.

Ground before you decompose. Measure rather than recall (charter P7): read the project's
`CHARTER.md` under *What is already true*, then go and *look* — at the folder, the statements, the
repos, whatever the project is made of.

Write the inventory into the epic doc **as a ledger of areas**, every one marked
`NOT-DECOMPOSED`. That list, complete and unsplit, is a legitimate end to session 1. It is also the
most valuable artifact in the whole epic: everything later is derived from it, and an area missing
here is an area that silently never gets built.

**Say what you did not enumerate.** An inventory whose gaps are unstated reads as complete.
And an inventory read twice by one vocabulary has been read once — see "A control varies the one
thing that could make the claim wrong" in `keel-orchestrator/SKILL.md`, whose third sentence governs
a claim that a set is complete.

## The ledger is the resume mechanism

Each area carries exactly one status token, greppable on purpose:

| Token | Means |
|---|---|
| `NOT-DECOMPOSED` | identified, not yet turned into a workstream |
| `W<n>` | decomposed — that workstream owns it |
| `E<n>` | grew into a sub-epic of its own |
| `EXCLUDED` | deliberately out of scope, with the reason and who decided it beside it; an exclusion the operator could want back is put to them first (see "An earlier decision is a tradeoff to show, not a rule to enforce" in `keel-orchestrator/SKILL.md`) |

**A later session reads the ledger and continues from the first `NOT-DECOMPOSED` row.** That is the
whole mechanism. Keep it accurate — it is the only record of what is left.

## Decomposing an area

For each area you take on this session:

1. **State what "done" means** for that area, in one or two sentences, falsifiable.
2. **Name which goals it serves.** At least one, and be honest when it serves two — that linkage is
   what makes coverage a query rather than a feeling (charter P22).
3. **Say whether it can finish independently**, and what it is **blocked by**.
4. **Allocate the number**: highest on disk + 1 — **measure it**. Numbers get skipped historically,
   so "count + 1" is wrong.
5. **Register it**, human-confirmed:

```
keel-state.ps1 add-epic        -Id E<n> -Title "<title>" -Parent <E<n>|root> -Groups "<what it groups>" [-Goals G1,G2]
keel-state.ps1 add-workstream  -Id W<n> -Title "<title>" -Parent E<n> -Goals G1[,G2]
```

`-Goals` is **mandatory on a workstream** (exit 98). An epic may carry goals too, but the coverage
query reads workstreams — an epic's goals are documentation, a workstream's are the claim.

**In a project that shares its progress through its repo** (`"progress": "repo"` in `keel.json`), two
things change. A "Decided by the operator" label in the ledger or a Decision row names which person
answered: *Decided by the operator, Person A (p-1a2b)*, the display name and person id from
`progress/people/<id>.json`. And once the operator approves what you registered, **commit and push
it at once** - the ledger and the new nodes under `progress/` - and report the commit and the push
rather than previewing them: an epic or workstream number is taken by whoever pushes it first, and
one taken twice is a git conflict at the second pull. It is reversible in part, observable with
`git ls-remote`, and inside what the operator has just approved (`keel-orchestrator/SKILL.md`,
"Whether to ask, or to act and report"). The wrapper never pushes; this step does.

Then **stop**. Do not plan its phases. `keel-plan-workstream` writes the spec and the next runnable
phase's prompt — only that one — when that workstream is actually picked up, and it should run
*then*, against the world as it will be by then. Phases planned months ahead describe a situation
that will have moved.

## Order and dependencies

Record both, because they are different:

- **Declared order** — the sequence you intend to work in.
- **Blocked by** — a real dependency, where the second genuinely cannot start.

*"Everything needs the bank statements"* is a dependency. *"Do 2021 before 2022"* is a preference.
Marking a preference as a dependency freezes a sequence that could have flexed. Marking a dependency
as a preference produces a workstream that cannot start when its turn comes.

## Checking your work before you stop

```
keel-state.ps1 goal-coverage
keel-state.ps1 tree
```

`goal-coverage` is the one that matters. A goal still reporting `UNCLAIMED` after a decomposition
session is either an area you missed, or a goal that belongs to a different epic — say which. If it
is genuinely not being addressed yet, that is fine, but it should be *declared*, not silent:

```
keel-state.ps1 set-goal-status -Id G<n> -Status UNADDRESSED -Detail "<why nothing claims it yet>"
```

The reason is required. Leaving it `UNCLAIMED` instead puts a warning on every future session that
nobody can clear, and an uncleanable warning is one the reader learns to skip past.

**The ledger stales the document index — rebuild it in the same commit.** `plan/epics/` is inside a
root `keel-index.ps1` scans, so `reference/INDEX.md` is wrong until it is rebuilt — and in a project
whose commit gate checks the index, the commit is refused until you do (keel's own does, in
`scripts/check-suite-docs.ps1`). The order and the staging rule are stated once in
`keel-orchestrator`'s "Ending a session" section — follow it there. The command is under
"Rebuilding the index" in `keel-project-context`.

## What this skill does not do

- **Plan any phases.** That is `keel-plan-workstream`, later, per workstream.
- **Implement anything.**
- **Create a tracker card per unstarted area.** The epic doc is the record; cards for work nobody
  has started are noise on a board whose whole value is showing what is live.
- **Estimate.** If asked, give a workstream count and say what would change it. If they want a time
  or cost estimate anyway, say that keel's design charter declines estimation and why (its practice
  table, row 6), and ask whether they want a rough one regardless - see "An earlier decision is a
  tradeoff to show, not a rule to enforce" in `keel-orchestrator/SKILL.md`.

## Must not

- **Decompose before the inventory is grounded**, or carry a figure from a document unmeasured.
- **Mark an area decomposed without a number.**
- **Plan a child's phases here.**
- **Write a `-Groups` line that restates the title.** The wrapper refuses it, and correctly: an epic
  that cannot say what it groups is a rung that should not exist.
- **Nest deeper than the work is.** Depth is free, but each rung must earn its "groups" line. Three
  deep with three real groupings is fine; three deep to look organised is not.
- **Leave the ledger stale.** It is the only record of what is left.
- **Rewrite a delivered workstream's ledger row.** Append the amendment, same as a spec Decision.
