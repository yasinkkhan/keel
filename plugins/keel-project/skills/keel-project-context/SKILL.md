---
name: keel-project-context
description: Grounding router for the ACTIVE keel project, resolved from the working directory and never stored. The read-only way to answer "what does this project already know" - which goals exist, what the charter decided, which workstream covers an area, what a delivery record says, what a reference file established. Use as the mandatory grounding step before planning or running a phase, and for read-only questions about a project that need no work done. Three tiers of progressive disclosure: a small always-read core, then a generated heading index for targeted reads, then live measurement. VERIFIES the index against disk before answering and refuses to quote a stale one - a grounding router that answers from a rotted index is the failure it exists to prevent. Never plans, never edits, never enacts, and never answers a live-state question from a document.
---

# Project context

**This skill answers "what does this project already know". It does not do work.**

A keel project accumulates documentation as it runs: the charter, epic ledgers, workstream specs,
delivery records, and whatever close-out routed into `reference/`. This is how a future session
finds the relevant part without reading all of it.

## The one rule that makes this trustworthy

**A document says what was TRUE WHEN WRITTEN. It never says what is true now.**

| Question | Answer from |
|---|---|
| *What are the goals? What did we decide? Why is X out of scope?* | **documents** |
| *What phase is next? What is waiting, and on whom? What is overdue? Is W4 delivered?* | **`keel-state.ps1 status`** — never a document |
| *Does that file still say that? Is the balance still X?* | **measure it now** |

A spec's phase table is the *plan*. `status` is the *record*. When they disagree, that disagreement
is the finding, and you surface it rather than resolving it in favour of whichever you read last
(charter P10).

## Tier 0 — always read, every time

Two things, both small:

1. **`keel.json`** — git, tracker, quarantine. These change how every other skill behaves, and
   `quarantine: true` changes what you are allowed to repeat back.
2. **`CHARTER.md`** — the sections headed *What this is*, *What "done" means*, *Scope boundary* and
   *Goals*. Cited by heading and not by number, because charters written at different times number
   them differently and a range would silently exclude one (P8).

That is the whole always-on cost. Everything else is fetched on demand.

## Tier 1 — the index, verified before use

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "${CLAUDE_PLUGIN_ROOT}/skills/keel-project-context/wrappers/keel-index.ps1"
```

| Exit | Means | Do |
|---|---|---|
| `0` | `reference/INDEX.md` matches disk | Use it |
| `1` | **stale or missing** | Rebuild with `-Write`, then use it |
| `91` | no project here | You are outside a project folder |

**Run this before quoting the index, every session.** A grounding router that answers from a rotted
index would be the tool built to prevent stale assertions becoming the estate's newest and
most-trusted source of them (charter P11). The check costs one command.

The index lists every document with its **headings** — anchors, never line numbers, so they survive
edits above them (P8). Grep it to find the right document and the right section, then read **only
that section**.

> *"Which workstream covered the bank ledger?"* → grep `INDEX.md` for `ledger` → it names
> `plan/workstreams/W1_ledger.md` and its headings → read `## 1. The finding` from that file alone.

## Rebuilding the index

Run this from the project folder whenever documents change, and always at close-out:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "${CLAUDE_PLUGIN_ROOT}/skills/keel-project-context/wrappers/keel-index.ps1" -Write
```

**This is the one place keel writes the rebuild command with its path, and every other skill points
here.** Keel's plugins can be installed as separate copies, each in a folder of its own, and a
skill's text can carry the path of its own plugin and of no other. `keel-index.ps1` ships in this
plugin, so only this skill can give its path for the copy of keel on this machine. A session sent
here by another skill that has not loaded this one loads it to get the command. Never build the path
by hand from another skill's location: in an installed copy that path does not exist.

## Tier 2 — live measurement

When the question is about **now**, not about what was written:

```
keel-state.ps1 status          what is delivered, in flight, waiting, overdue
keel-state.ps1 tree            the shape: goals, epics, workstreams, phases
keel-state.ps1 goal-coverage   which goals nothing is pointing at
```

`keel-state.ps1` is the state wrapper in the keel-workflow plugin. Its full path is the one
`using-keel` and `keel-orchestrator` give; a session that has loaded neither loads `using-keel` to
get it.

And for anything outside keel's own bookkeeping — a file's contents, a balance, a deployed version —
go and look. Every claim of **absence** carries a positive control: a second query proving the
instrument would have found the thing had it been there (charter P7).

## How the documentation accumulates

You do not write documentation as a separate task. The pipeline produces it:

| Written by | Lands in | Contains |
|---|---|---|
| `keel-plan-project` | `CHARTER.md` | goals, done, scope boundary, counterparties, decisions |
| `keel-plan-epic` | `plan/epics/E<n>_*.md` | the decomposition ledger |
| `keel-plan-workstream` | `plan/workstreams/W<n>_*.md` | the finding, decisions, phase table, checks |
| the phase session, **by hand** | `record/W<n>.<p>-*.md` | phase output documents — a delivery write-up, a coverage matrix, a source register |
| the operator, **by hand** | a declared docs root — see below | what the project currently IS |
| **`keel-close-workstream`** | **`reference/*.md`** | **slow project knowledge worth keeping** |

**Two of those rows have no verb behind them, and that is deliberate.** No keel verb writes
anywhere under `record/` - measured by searching every writer in `plugins/`, with the same search for
`handoffs` as the positive control, where it does find the real writer lines in `keel-state.ps1`. A
phase session writes those files itself, following this table, and that is real practice in more
than one project rather than an aspiration. A table that named a verb would make a session wait for
something that is never coming, so it names the writer that exists.

**Do not confuse `record/W<n>.<p>-delivery.md` with the `record` gate's own artifact.** The gate
artifact is `delivery-record.md`, it lives outside the project entirely at
`%USERPROFILE%\.keel\projects\<slug>\phases\<id>\delivery-record.md`, and its contents are appended
to the workstream spec under `plan/` at close. The `record/` file is the project-folder write-up.
Two different files, both legitimate.

**In a project that shares its progress through its repo** (`"progress": "repo"` in `keel.json`),
every gate artifact, `delivery-record.md` included, is read from
`progress/phases/<id>/artifacts/` inside the project folder instead, committed with the project and
pulled with it. The other files under `progress/` are the project's state, one JSON file per item
and per entry; read them through `keel-state.ps1 status` and `tree`, never by opening them, as for a
`state.json`. `progress/` is outside the roots the document index covers, so it is never in
`reference/INDEX.md`.

**The docs root is optional and declared, never assumed.** A project that wants one sets a path
relative to its root in `keel.json`:

```
"docs": "docs"
```

Absent means the project has no doc set, and absent is the default — a project that declares nothing
indexes exactly what it always did (charter P24). Files under the declared root classify as kind
`docs`. The root is **resolved to a real directory and checked as a canonical path**, never trusted
as the string it was written as. Refused at exit 90: a path that does not exist; one naming a file;
one that is a junction or symlink; one that is absolute, escapes the project, or resolves to the
project root; one that resolves to or inside an already-indexed root, which would index every file
under it twice; and one that resolves to or inside a never-indexed folder such as `private` or
`repos`, which would index nothing. String comparison alone is not enough and neither is
canonicalising it — `"./plan"` and `"plan."` both look unlike `plan` and resolve to it, and a
*junction* named anything at all resolves wherever it points while reporting its own path.
**A project with `quarantine` on may not declare one at all:** indexing
writes every page title and every H2/H3 heading into `reference/INDEX.md`, which is inside the repo,
and redaction is owed at extraction (charter P23).

The last row is the one that compounds. A portal's session timeout, a counterparty's real
turnaround, a format gotcha that cost an hour — routed into `reference/` at close-out, indexed, and
found by the session six months later that would otherwise rediscover it.

**Rebuild the index whenever documents change**, and always at close-out, with the command under
"Rebuilding the index" above.

## What a current-state page may say

A declared docs root holds **standing description**: how a component, a subsystem or a recurring
process actually works, and why it is shaped that way. Knowledge that is expensive to re-derive, that
changes slowly, and that no command can produce. When the thing it describes changes, the page is
**rewritten in place** — that is what makes it current-state, and it is the whole of what separates
it from every other document a project accumulates.

**This does not exempt a page from the rule at the top of this file.** A page is still a document and
still says only what was true when it was written. What a docs root adds is not a document that
somehow reports the present — it is an **obligation on someone here** to rewrite the page when it
stops being true. A reader still never treats a page as the answer to a live question. The difference
is only that a stale page is somebody's outstanding work, where a stale `reference/` file is a
correctly-aged record.

**The rule, stated as a test rather than as an intention: a page may not assert anything a lookup
answers. Where a keel command answers it, the page names that command instead of the answer; where
the answer comes from opening the thing itself, the page says where to look.**

Apply it as a yes/no question, never as a matter of degree. Before a sentence goes on a page, ask:
*is this the current value of something — obtainable by running or opening something, right now?* If
it is, the sentence is forbidden, however slowly it looks like it changes and however convenient it
is to have it to hand. What survives is mechanism and rationale: how the thing works and why it is
shaped that way, which no lookup returns.

| A sentence answering... | is answered by |
|---|---|
| what is next, what is delivered, what is waiting and on whom, what is overdue | `keel-state.ps1 status` |
| the shape of the project — goals, epics, workstreams, phases | `keel-state.ps1 tree` |
| how many goals there are and which are claimed | `keel-state.ps1 goal-coverage` |
| what a file, a balance or a deployed version currently holds | going and looking |

**A violation looks like this.** A page describing reconciliation opens:

> *The reconciliation workstream is W7, and it is delivered. Its output feeds the year-end pack.*

The second sentence is exactly what a page is for. The first is forbidden **twice over**, and it is
worth seeing both: `status` answers whether W7 is delivered, and `tree` answers that reconciliation
is W7 at all. The page has taken custody of two facts that will change without it. What the rule
requires instead:

> *Reconciliation output feeds the year-end pack. Whether it is planned as its own workstream, and
> where that work stands, are `keel-state.ps1 tree` and `keel-state.ps1 status`.*

**Note what the repair does not do: it does not soften the claim, it removes it.** "Reconciliation is
planned as its own workstream" would still be forbidden, however vague — it asserts the project's
shape, and the table above gives shape to `tree`. Vaguer is not the same as compliant, and a rule
applied as a matter of degree is the rule not being applied.

**The near miss is the one worth learning.** *"The ledger reconciles against the bank's year-end
total by summing debits"* is a mechanism: no command returns it, re-deriving it costs an hour, and it
belongs on a page. *"The ledger currently reconciles to within four pounds"* is a measurement: it
belongs nowhere but in the act of measuring it. Both sentences are about the same ledger; only one of
them ages.

**A page and a `reference/` file are different artifacts, and the axis that separates them is how
each one ages.** What each holds, and which writer puts it there, is in the "How the documentation
accumulates" table above and is not repeated here. What that table does not say is this. A
`reference/` file makes a dated promise and keeps it — it says what was true when it was written, and
because that is the whole of what it claims, it stays correct for as long as it exists. A page makes
the opposite promise. **A page that is only true as of the day it was written is not an old page; it
is a wrong one** — and nothing in the index, and nothing in the file itself, tells the reader which
kind they are holding. That asymmetry is why the two live under different roots, and it is the entire
reason a page carries a freshness obligation and a `reference/` file does not.

**The axis becomes a test with one question: if this became false tomorrow, would someone here owe an
edit?** A page describes what the project itself is or does, so when the project changes, somebody
owes the page a rewrite, and until they make it the page is wrong. A `reference/` file records
something found out about the world outside the project's control, so nobody owes it anything: what
was found is still what was found, and when it changes you write a new note rather than correcting
the old one. *"Expenses are categorised before import, because the importer cannot infer a category
from the description"* is a page — move to an importer that can, and this project owes that sentence
an edit. *"The bank's upload form rejects a CSV carrying a byte-order mark"* is a `reference/` note —
nobody here decides that, and nobody here owes it an edit on the day the bank changes it.

**The two questions do different work, and they run in that order — so there are three destinations,
not two.** The first decides whether a fact may be written down **at all**: if a lookup answers it,
it may not, and nothing further is decided about it. Only what survives reaches the second question,
which chooses between the two homes. *"The ledger currently reconciles to within four pounds"* never
reaches the second question, because opening the ledger answers it; asking who owes it an edit is
already the wrong question. Both of the two sentences above, by contrast, survive the first question —
no lookup returns either — and are separated only by the second.

## What good grounding looks like

Write what you actually read and, just as importantly, what you did not:

```
Measured: read CHARTER.md under "Scope boundary" and "Goals", and
          plan/workstreams/W1_ledger.md section 1; keel-state.ps1 status shows
          W1.2 waiting on Priya since 2026-08-24.
Not read: the 2022 epic ledger and every delivery record before W1 - out of scope
          for this phase, and nothing under "Scope boundary" suggests they bear on it.
```

An inventory whose gaps are unstated reads as complete. Say what you skipped and why.

## Must not

- **Quote the index without verifying it.** One command. Exit 1 means rebuild first.
- **Answer a live-state question from a document.** Phase status, waiting, overdue and delivery all
  come from `status`.
- **Read everything.** The tiers exist so a session spends its context on the work.
- **Plan, edit, or enact.** This skill is read-only. Hand back to `keel-orchestrator`.
- **Repeat identifying detail out of a quarantined project.** Describe what a document establishes
  without reproducing the identifiers in it (charter P23).
- **Cite a line number.** Headings and unique strings only (P8).
- **Resolve a spec-vs-state disagreement silently.** Surface it; it is a finding.
- **Assert on a docs page anything a lookup answers.** Name the command, or say where to look — a
  page that caches live state is a second authority that rots silently (P9, P10).
