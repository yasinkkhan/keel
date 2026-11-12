---
name: keel-close-workstream
description: Closes a keel workstream - routes real, citable friction from the work just done into exactly ONE home, stamps the spec, and updates the tracker projection if the project has one. Dispatched by keel-orchestrator at workstream close; never a session entry point. Reads the friction log the wrapper recorded DURING the work rather than the conversation, which has usually compacted by now. Silence is the correct output: most closes should propose nothing, and a finding with no citable moment from this workstream is dropped without mentioning it. The one route that leaves the project is a SIGNAL - a defect in keel itself, filed with project, phase and evidence, and triaged later in keel; this skill never edits plugins/** and never files a signal without a citable moment. The two outward acts - the signals push and the tracker projection - are previewed and waited on; local writes inside the project folder are made and reported.
---

# Close a workstream

**Most closes should propose nothing.** That is the expected outcome, not a failure (charter P16).

A close-out that always finds five things trains you to skim, which is how the one real finding gets
missed.

## Step 1 — is it actually closeable?

```
keel-state.ps1 close -Ws W<n>
```

The wrapper refuses (exit 90) while any phase is neither delivered nor abandoned, and names them.
If it refuses, the workstream is not finished — say which phases remain and hand back.

A workstream that never ran takes `abandon -Ws W<n> -Detail "<reason>"` instead, because `close` can
only record `DELIVERED`.

## Step 2 — read the friction log, not the conversation

```
keel-state.ps1 status -Phase W<n>.<p>
```

Run it for **every phase in the workstream you are closing**. The ledger is per phase, and this
prints each item with its kind, its timestamp and its detail.

Plain `status` carries a friction **count** for the next runnable phase — that is what a resuming
session sees, and it is a pointer, not the evidence. By close-out the workstream's phases are
delivered and none of them is the next runnable one, so `-Phase` is the form that reaches the
entries.

The friction entries were recorded **during** the work, with timestamps, by `note-friction`. That is
your evidence base. **Do not reconstruct friction from the conversation** — by close-out it has
usually compacted, and what survives is the parts that felt significant, which is not the same as
the parts that were.

If the friction log is empty, that is a finding in itself, and usually means the work went smoothly.
It can also mean nobody recorded anything. Say which you think it was; do not invent entries.

**In a project that shares its progress through its repo** (`"progress": "repo"` in `keel.json`),
the ledger is everyone's: each entry is a file under `progress/` naming its author by a person id,
and `progress/people/<id>.json` gives that person's name. Pull before you read it, or the entries a
colleague pushed are not there. Route every person's friction, not only your own, and say whose an
item was where it matters to the route. A signal you file still stays on this machine until it is
pushed, whoever's friction it came from.

**The phase's gate artifacts and the two ledgers are keel-produced records** — `grounding.md`,
`investigation.md`, `plan.md`, `act-log.md`, `enact-record.md`, the friction ledger and the
open-question ledger — governed by **"Material keel produced is re-measured before you act on it"**
in `keel-orchestrator/SKILL.md`.

## Step 3 — route each item to exactly ONE home

Every friction item goes to **one** destination. Not two. A fact with two homes is a fact that will
disagree with itself (charter P10).

| Destination | When | Where it lands |
|---|---|---|
| **The workstream spec** | A lesson about how *this* work went | §8 Process lessons |
| **The project charter** | It changes what "done" means, or the scope boundary | `CHARTER.md`, as an appended dated Decision saying who decided it (see "An earlier decision is a tradeoff to show, not a rule to enforce" in `keel-orchestrator/SKILL.md`) |
| **The project's docs page** | How a component, subsystem or recurring process **this project owns** actually works, and why it is shaped that way — if it changed tomorrow, someone here would owe the page an edit. Never the behaviour of keel itself, the tooling this work is being run through | the owning page under the declared docs root, rewritten in place |
| **The project's `reference/`** | Slow knowledge about something this project *deals with* rather than owns — a portal's quirk, a counterparty's actual turnaround, a format gotcha. If it changed tomorrow nobody here would owe an edit; you write a new dated note and the old one was never wrong. Never the behaviour of keel itself, the tooling this work is being run through | a file in `reference/` |
| **A signal** | A defect or gap in **keel itself** | the queue, via the wrapper |
| **Dropped** | No citable moment from this workstream | nowhere, silently |

**The last row is the most common.** A finding with no citable moment is dropped **without
mentioning it**. Do not list what you considered and rejected; that is the padding this skill exists
to avoid.

**Prose a phase shipped into the repository beside its change** — a CHANGELOG entry, a script
comment, a row in the repo's working rules — is keel-produced material carrying figures that phase
measured, and a friction item about one routes here like any other. It is governed by **"Material
keel produced is re-measured before you act on it"** in `keel-orchestrator/SKILL.md`.

**A project that has declared no docs root has nowhere to land row three yet, and that is a finding
rather than a re-route.** Most projects declare none. Name the item, say the project has no docs
root, and leave declaring one to the human — quietly sending it to `reference/` instead would file a
page-shaped fact where nothing obliges anyone to keep it true, which is the confusion the passage
below exists to stop.

**If this workstream is express, it has no spec, and row one lands somewhere else.**
`keel-orchestrator`'s "Step 0.5 — express or full workstream?" sets the spec file to `none` and names
`plan.md` as the plan artifact, so a process lesson routes to the **delivered phase's `plan.md`**
instead of §8 — appended at the end, under its own heading, rewriting nothing above it. The other
five rows do not depend on a spec and are unaffected: the charter, a docs page, `reference/`, a
signal and dropped all work exactly as above.

### Choosing between "reference" and a docs page

Both are project truth and both are slow, so the two names do not separate them. The line is: **if
this became false tomorrow, would someone here owe an edit?**

- *"The archive is rebuilt from scratch every run, because incremental updates silently skipped
  renamed files"* → a **docs page**. The shape is this project's own, so the day someone fixes the
  incremental path, somebody here owes that sentence a rewrite — and until they make it, the page is
  wrong.
- *"The registrar's confirmation email arrives from a no-reply address that bounces replies"* →
  project `reference/`. Nobody here decides that. When the registrar changes it you write a new note;
  the old one was never wrong.

A `reference/` file makes a dated promise and keeps it. A page promises to be true *today*, which is
the whole reason it carries a freshness obligation and a `reference/` file does not.
`keel-project-context`'s "What a current-state page may say" is the authority for what may go on a
page — including the question that runs **before** this one, whether a lookup already answers the
fact, in which case it belongs on neither.

### Choosing between "reference" and "signal"

The line is: **is this true about this project, or about keel?**

- *"The tax office's portal logs you out after 15 minutes"* → project `reference/`.
- *"The wrapper would not let me record a wait because the accountant gave no date"* → **signal**,
  kind `refusal`.

If it is about a project, keel must not change. If it is about keel, the project must not change it.

## Step 4 — signals: the only route that leaves the project

A project session **never** edits `plugins/**` (charter P25). The charter gate blocks it, and the
queue is the sanctioned path.

```
keel-state.ps1 signal -Phase W<n>.<p> -Kind <unsafe|refusal|wrong-doc|gap|friction> -Detail "<what>" -Evidence "<the command and its actual output, or a path>"
```

**Both `-Phase` and `-Evidence` are mandatory (exit 97), and that is the whole point.** A signal
cites the moment it came from. Wishes are not signals, and a queue of wishes is a queue nobody
reads.

| Kind | Means | Acts at |
|---|---|---|
| `unsafe` | Something outward-facing nearly happened without a preview, or a quarantine rule nearly leaked | **n=1** |
| `refusal` | The wrapper refused something legitimate | **n=1** — a false refusal teaches you to route around the gate |
| `wrong-doc` | A keel skill or reference asserted something false | n=1 if reproduced |
| `gap` | No gate, verb or recipe existed for something real that happened | n=2 |
| `friction` | It worked, but cost far more turns than it should have | n=2 |

**Evidence must be reproducible, not a paraphrase.** "The wrapper was annoying" is not evidence.
`exit 95 from set-waiting, message pasted` is.

### If this project has `quarantine` on, evidence is BY REFERENCE ONLY

A signal leaves this machine (charter P26). From a quarantined project it may carry only **a local
path plus a short description, on one line** — never pasted content. The wrapper refuses content
from such a project with exit 97, and that refusal is the point: an issue body containing a
statement line, an identifier or key material cannot be unsent.

> **Refused** — `-Evidence "PS> Get-Content statement.csv <8 lines of transactions>"`
> **Accepted** — `-Evidence "see quarantine/tax-returns/2023-03.pdf line 14; wrapper help lists no quarantine verb"`

Check `keel.json` before you compose the evidence, not after the wrapper rejects it.

### Filing is local; pushing is a separate, deliberate act

```
keel-state.ps1 signals-push            # PREVIEW - prints the exact issue title and body
keel-state.ps1 signals-push -Apply     # creates them on this machine's chosen destination
```

**With no destination chosen (`keel-state.ps1 signals-target` says none), `signals-push` refuses at
exit 90 and the signal stays on this machine.** That is a complete outcome: say so in the hand-back,
and do not choose a destination for the operator.

**Read the preview.** It is the last point at which something that should not leave the machine can
be stopped. Show it to the human and wait (charter P6); never run `-Apply` unprompted.

**Filing a signal does not change keel and must not be described as if it did.** Say: *"filed S0007
locally; previewed and pushed as issue #12; it will be triaged in a keel session."*

## Step 5 — stamp the spec

Set the workstream's status line to delivered, with the date. **Do not rewrite any phase's plan
text or delivery record** — the plan as written is the record of what was intended, and the
difference from what happened is the useful part.

Append process lessons to §8, if there are any with a citable moment.

**An express workstream has no spec, so this step is a no-op** — there is nothing to stamp and
nothing to say, the same shape as Step 6 below when a project's tracker is `none`. The delivered
status the stamp would have carried is already in the state file, which `tree` prints and which
outranks any document (charter P3), and Step 3 has already routed any process lesson to the delivered
phase's `plan.md`. Do not create a spec file here in order to have somewhere to write.

## Step 6 — the tracker projection

If `keel.json` names a tracker, update the projection to reflect the close. If it says `none`, there
is nothing to do and nothing to say.

**Preview the exact final text and the exact destination, and wait for confirmation** (charter P6).
Uncertainty defaults to SKIP, never to writing.

The tracker is a projection. Nothing about the close is *decided* there, and nothing is read back
from it.

## Step 7 — rebuild the document index

Anything that landed in `reference/` this close-out — and every delivery record written during the
workstream — has to become findable, or it is knowledge the project has and cannot retrieve. Run
the command under "Rebuilding the index" in `keel-project-context`, loading that skill first if this
session has not; only that skill can give the path to `keel-index.ps1` for the copy of keel on this
machine.

**This is the step that makes documentation compound.** A portal quirk, a counterparty's real
turnaround, a format gotcha that cost an hour: routed to `reference/` here, indexed here, and found
by the session that would otherwise rediscover it. Skipping it does not lose the document — it loses
the ability to find it.

## Step 8 — check goal coverage before you finish

```
keel-state.ps1 goal-coverage
```

A goal reporting `UNCLAIMED` after a workstream closes is worth one sentence: is it the next
workstream's job, or has it quietly gone unaddressed for the life of the project? Do not fix it
here — just make it visible (charter P22).

## Step 9 — Was it worth it, and is the order still right

Every step above reports on **how the work went**. This one asks whether it was **worth doing**. It
is asked once per workstream, here, and never per phase — a value question asked eight times per
workstream is the ceremony charter P13 says gets routed around, and the project's `CHARTER.md`
records that as a decision already made.

**The spec's section 1, and every delivery record appended to its section 5, are dated keel-produced
documents** — governed by **"Material keel produced is re-measured before you act on it"** in
`keel-orchestrator/SKILL.md`. Judging worth against a figure quoted from them is judging against the
snapshot rather than against the outcome.

**1. Did this achieve what it was for?**

Judge against a standard **written before the work**, and **say which one you used**. Do not invent a
fresh criterion at close, and do not lower the bar to whatever was in fact delivered.

**Find the standard by this ladder, in order, and stop at the first rung that is present.** Cite the
headings, never the section numbers — a project created before the value statement existed numbers
its sections differently from one created after, so a number is wrong for one of them whichever you
pick (charter P8).

1. **`CHARTER.md` section *Why this is worth doing*** — and within it, specifically **How the
   benefit is recognised**: what would be observably different if this worked. This is the intended
   standard, written at intake before anyone knew how the work would go.
2. **`CHARTER.md` section *What "done" means*, together with the goals this workstream claims** —
   the goal text from the charter's *Goals* section, for the goals `goal-coverage` has just printed
   against this workstream in Step 8. This rung turns on *What "done" means*; if the charter has no
   *Goals* section, the rung still holds and you say you judged against *What "done" means* alone.
   Both were recorded at intake as well, so neither is a criterion invented at close; but they are a
   **broader** standard than rung 1, and judging against them is a weaker test, which is worth saying
   out loud when you use them.
3. **Neither rung above is available** — the charter has no value statement *and* no
   *What "done" means* section. Record that the project has no pre-work standard to judge against,
   and answer this question **not judgeable**. Do not construct one now. A close that reaches this
   rung is telling the operator something worth knowing about the project's intake.

**State the rung you used, and why the one above it was unavailable, in the text you write at the end
of this step.** One sentence. This is not bookkeeping: without it the next close substitutes a
different standard, or a lower one, and nothing in the record shows that the bar moved.

**Why there is a ladder at all.** Rung 1 arrived with `PROJECT_CHARTER_TEMPLATE.md` and was
deliberately not applied to charters already written, so every project created before it reaches this
step and finds the section absent. A widening at intake is a **tightening here** — charter P24 — and
the ladder is that tightening's migration.

**"No" is an acceptable answer here, and it is not a failure of the pipeline.** A workstream can be
planned well, gated properly, verified honestly, delivered on time — and still not have moved the
thing it was for. Eight green gates are not evidence that it did; no keel gate measures this, which
is the whole reason this step exists. Record the no, with what was expected and what was observed.
A close-out that has never once returned a no is not a review.

**2. Is the declared order still right?**

Step 8 has just run `goal-coverage`. With that output in front of you and this workstream closed:

- **What changed** since the order was declared — what is known now that was not known then.
- **What is the highest-value next thing.** It may not be what the plan says is next.
- **What should be dropped.** The half most often skipped. A plan nothing is ever removed from is a
  plan nobody has re-judged.

**This step decides nothing by itself.** If the order should change, that is a **re-planning
event**, and it runs through the mechanism that already exists — `keel-orchestrator`'s "Step 3.5 —
the plan changed", in a fresh session. Do not reorder anything from here.

**Write both answers into the workstream spec's `## 9. Was it worth it`**, appending the section if
the spec predates it. That append is a local, reversible write inside the project's own folder, so
**make it and say what you wrote** — the Must not list below is the rule. Two or three sentences per
question is the size — a dated judgement, not a report.

**If the workstream is express there is no spec, and both answers go to the delivered phase's
`plan.md`** — the plan artifact `keel-orchestrator`'s "Step 0.5 — express or full workstream?"
already names — appended at the end under a `## 9. Was it worth it` heading, with nothing above it
rewritten. Make it and say what you wrote, exactly as above. **This branch matters more than the other two.**
Express is the cheap path small work is actively steered onto, so a Step 9 that silently had nowhere
to write was skipping the only judgement in the pipeline precisely where the ratio of ceremony to
value is worst and an unjustified piece of work is likeliest to hide.

**No estimate, no score, no number.** The gap this step fills is the absence of a moment where the
plan is re-judged, not the absence of numbers.

## Step 10 — render the whole shape before you hand back

The workstream is closed. **Show the human where it sits** — a picture, not a list of what was
routed.

Step 8 already ran `goal-coverage`; reuse that output rather than dispatching it twice. Add the
other half:

```
keel-state.ps1 tree
```

**Both are needed, and where they disagree, say so.** `tree` prints the label **stored** on each
goal — `[UNADDRESSED]`, or nothing once it is claimed. `goal-coverage` **computes** the same
judgement from live workstream links — `CLAIMED by 2: W3, W7`, or `UNADDRESSED (declared)`. A goal
carrying a stored `[UNADDRESSED]` label that a workstream in fact claims is drift, not a fact. Print **both** readings and name the
disagreement; do not resolve it in favour of whichever was read last (charter P10, one authority
per fact).

**Format it.** An indented hierarchy — goals, then workstreams, then phases — with a status marker
on every line, and **the workstream you just closed marked** in place. Expand every identifier
where it first appears: a goal id with the goal's text, a phase id with its scope. The reader did
not watch the work and does not hold the vocabulary.

**The whole shape, every time — not the delta.** Every goal, every workstream, every phase,
including the ones this close-out did not touch. Charter P16 — silence is a success, and output is
not evidence of value — makes this a deliberate exception: a close-out that reports only what it
changed leaves a reader who did not watch unable to place it.

### And say how much you dropped

**Report three numbers, every close, in one line: items considered, items routed, items dropped.**
A close-out that hands back without them is incomplete, not merely terse.

- **Considered** — every friction entry you read from the per-phase ledgers in Step 2. That set and
  no other; anyone can re-derive it by running `keel-state.ps1 status -Phase W<n>.<p>` for each phase
  in the workstream.
- **Routed** — the items that landed in one of the five destinations in Step 3's table.
- **Dropped** — the rest. **The three must add up**, and a line where they do not is itself the
  finding.

> Friction: 28 considered, 4 routed, 24 dropped.

**Do not list the dropped ones.** Step 3's rule stands unchanged and this does not soften it: a
count is one line and cannot become padding, where an enumeration is exactly the padding charter P16
forbids. Satisfying this by listing everything you considered would break both rules at once.

**Why a number is owed at all.** Without it the only observable is what was routed — so an item you
read and judged not worth routing, and an item nobody ever read, look identical in the record,
including to the person being asked to trust the close. Three numbers separate them without naming
anything. They measure what was **recorded**, not what occurred: a workstream nobody logged friction
in reports `0 considered`, which Step 2 has already told you to read as a finding rather than as a
clean run.

**Before you hand back, write the handoff** — see "Ending a session — write the handoff before you hand back" in `keel-orchestrator/SKILL.md`.

## Must not

- **Propose something with no citable moment.** Drop it silently.
- **Route one item to two homes.**
- **Edit `plugins/**`.** File a signal.
- **File a signal without a phase and reproducible evidence.**
- **Auto-apply any write that leaves this machine.** The **signals push** in Step 4 and the
  **tracker** projection in Step 6 are previewed in their exact final form and waited on, every
  time — they put local content on GitHub and on a third-party board, and charter P6's unamended
  half governs both. A **local, reversible, observable write inside the project's own folder** —
  stamping the spec, appending §8 or §9, writing a `reference/` note — is **performed and reported**
  instead, under "Whether to ask, or to act and report — reversibility decides" in
  `keel-orchestrator/SKILL.md`.
- **Rewrite a delivered phase's record.**
- **Pad.** A close that says "6 considered, 0 routed, 6 dropped; W4 stamped delivered" is complete
  work.
- **Judge "did this achieve what it was for" against a standard invented at close**, or reorder the
  plan from Step 9. Read the intake statement back; route a change of order to re-planning.
- **File anything containing identifying personal information** if the project has quarantine on —
  signals leave the project and are read in a different context.
