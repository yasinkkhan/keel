---
name: keel-run-phase
description: Executes exactly ONE phase of an existing keel workstream - reads the spec and the phase prompt, grounds live before changing anything, does the work or records what the human or a third party did, then hands the result to a FRESH verifier subagent that independently checks every W<n>.<p>-C<n> and returns the results table. Dispatched by keel-orchestrator only; never a session entry point, even on "implement phase W4.2" or "just make this change". The phase's ACTOR selects what evidence a check accepts - command output for agent, an artifact you point at for self, the received deliverable for external - and never which gates run. Resolves FACTUAL unknowns by dispatching fresh advisor subagents with self-contained briefs and proceeds; STOPS and asks the human for anything about scope, cost, risk or irreversibility, and for anything that would contradict a recorded spec Decision. Never commits, pushes, files, signs or enacts on its own initiative.
---

# Run one phase

One phase. Eight gates. Then hand back.

Every gate is recorded through the wrapper, and a gate is satisfied only when **the artifact
exists**, **the artifact conforms**, and **the verdict is recorded** (charter P3).

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "${CLAUDE_PLUGIN_ROOT}/skills/keel-orchestrator/wrappers/keel-state.ps1" <command> ...
```

Artifacts go in the phase directory: `%USERPROFILE%\.keel\projects\<slug>\phases\W<n>.<p>\`.

**In a project that shares its progress through its repo** (`"progress": "repo"` in `keel.json`), the
phase directory is `progress\phases\W<n>.<p>\artifacts\` inside the project folder, and the artifacts
are committed with the project. Scratch that is not an artifact - a verifier's fixtures, a copy of
state - still goes under `%USERPROFILE%\.keel\projects\<slug>\phases\W<n>.<p>\`, which is this
machine's alone and never committed. Every gate a verb records there names this machine's person
id as its author, so a machine that is not registered is refused at exit 95 until it runs `join`.

## Before anything: what kind of phase is this?

Read the phase's **actor** from `status`. It determines what you are about to do:

| Actor | You are | The `implement` gate produces |
|---|---|---|
| `agent` | doing the work | `changes-<repo>.patch` per declared repo — or `act-log.md`, if the phase declares no repos |
| `self` | **recording what the human did** | `act-log.md` with `Done by:` and `Done on:` |
| `external` | **recording what a third party delivered** | `act-log.md` naming them and the receipt date |

**On a `self` or `external` phase you are a scribe and a checker, not a doer.** Do not narrate the
act as though you performed it, and do not record it as done until there is evidence.

---

## Gate 1 — ground

Re-measure what this phase depends on. The phase prompt's "what is already true" is a **dated
snapshot from planning** and may have moved.

**Everything else the prompt says is keel-produced material too** — `## What this phase changes`,
`## Checks this phase must pass`, `## Out of scope for this phase`, `## The enact step` — and so are
the spec's section 1, the previous phase's delivery record, any `record/` deliverable it points you
at, and an advisor's answer at gate 2. All of them are governed by **"Material keel produced is re-measured
before you act on it"** in `keel-orchestrator/SKILL.md`, which covers gates 3, 5 and 6 of this skill
as well.

Write `grounding.md`. It needs two lines, and the wrapper refuses without them (exit 96):

```
Measured: <what you actually ran or opened, and what it returned>
Not read: <what you did not check, and why it did not matter>
```

`Not read:` is not a formality. An inventory whose gaps are unstated reads as complete.

**Where what you re-derive is an enumerated surface, the re-derivation must differ from the source
you are checking in population as well as in pattern** — see "A control varies the one thing that
could make the claim wrong" in `keel-orchestrator/SKILL.md`. Re-running the pattern a prompt or a
brief names reproduces its blind spot exactly, and hands back the agreement as though it were
corroboration.

```
keel-state.ps1 set-stage -Phase W<n>.<p> -Stage grounding
keel-state.ps1 record-verdict -Phase W<n>.<p> -Gate ground -Verdict DONE
```

## Gate 2 — investigate

Establish the facts the plan needs that grounding did not settle. Write `investigation.md`, which
must carry a `Positive control:` line (exit 96).

**Every absence claim needs a positive control** — a second query proving the instrument would have
found the thing had it been there (charter P7). "I searched and it's not there" without one is the
single most common way this system has been wrong.

**Factual unknowns → dispatch a fresh advisor subagent** (charter P5). Its brief comes from
`templates/ADVISOR_BRIEF.md` and must be self-contained: paths, commands, the exact question, the
output format, and the prohibition *do NOT load or invoke any keel-* skill*. It returns a summary
and a path, never its whole investigation.

**The dispatching session owes a control too, for any it proposes.** Before you hand a brief over —
the advisor brief here, the verifier brief at gate 5 — run any positive control you suggest in it,
or label it unmeasured in the brief's own words. A control that arrives inside a brief carries the
brief's authority and gets followed rather than questioned, so one that does not work returns
INCONCLUSIVE on a phase that was fine.

**Running it is not the whole obligation: state what it printed, and what it prints when the
instrument is broken** — see "A control varies the one thing that could make the claim wrong" in
`keel-orchestrator/SKILL.md`.

**Log every question you auto-resolve:**

```
keel-state.ps1 open-question -Phase W<n>.<p> -Question "<what was unclear>" -Answer "<what you concluded and from what evidence>"
```

These are re-surfaced at the human gate. That is the deal: you may resolve facts yourself, but the
human sees every one before approving.

**STOP and ask the human** - in plain text - for anything about **scope, cost, risk,
irreversibility, or a person**, and for anything that would contradict a recorded Decision - the
spec's, its epic's or the project charter's. Those are not facts to look up. Put a decision to them
as a tradeoff, not as a rule they must repeal - see "An earlier decision is a tradeoff to show, not a
rule to enforce" in `keel-orchestrator/SKILL.md`.

Write that question under **"Asking the human — the question must be answerable without keel's
vocabulary"** in `keel-orchestrator/SKILL.md`, the skill that dispatched this one.

Verdict `DONE`, or `BLOCKED` if the phase genuinely cannot proceed. `BLOCKED` needs no artifact —
but if it is blocked *on someone else*, use the waiting state instead:

```
keel-state.ps1 set-waiting -Phase W<n>.<p> -WaitingOn "<name and role>" -ReviewOn <yyyy-MM-dd>
```

## Gate 3 — plan

Write `plan.md` with a `Changes:` section listing exactly what will change — files, documents,
forms, accounts, money.

**The section must enumerate, and the check is structural.** A `## Changes` heading is accepted as
readily as a `Changes:` line, and so are the bold and bullet forms — but the section under it has to
carry a list, a table, sub-headings or a code block. Prose alone is refused, and `Changes: none` is
the case it is refused for.

### Then hand it to a fresh subagent — not to the operator

The plan is the one artifact in this pipeline that nothing independent reads. Dispatch a **fresh
subagent** that did not write `plan.md`, briefed from `templates/PLAN_REVIEW_BRIEF.md`, to read it
against the spec's checks and the phase prompt.

**It returns findings, not a verdict** — an issues list. It does not decide whether the plan
proceeds, and a review that returns a verdict is this gate's failure mode rather than its purpose:
the ratification would have moved to a subagent and nothing would have changed except who signs it.

**The findings go back to the implementer** — you — as an iteration:

```
keel-state.ps1 new-iteration -Phase W<n>.<p> -Trigger plan -Detail "<what the review found>"
```

Resolve them and rewrite the plan. **Exit 2 means the cap is reached — stop**, set stage
`escalated`, and hand the accumulated findings to the operator. The review shares the phase's
iteration budget with the `verify` and `human` loops, deliberately: a plan that cannot survive two
independent reads is one they should see.

### What still reaches the operator

Five classes: **scope, cost, risk, irreversibility, and anything involving a person.** The same set
`investigate` reserves for them, applied one gate later - and, as there, **a contradiction with a
recorded Decision** reaches them too. A reviewer can decide whether a plan is
internally consistent, whether a check can fail, whether a step is missing. It cannot decide whether
the work is worth doing, what it may cost, what it commits somebody to, or whether an earlier
decision still holds - see "An earlier decision is a tradeoff to show, not a rule to enforce" in
`keel-orchestrator/SKILL.md`.

Ask in plain text, under **"Asking the human — the question must be answerable without
keel's vocabulary"** in `keel-orchestrator/SKILL.md`.

Everything else - a missing file, a check that cannot fail, a step in the wrong order, a
contradiction with a fact the spec records (a path, a count, a step) - goes to the implementer and
never to them.

**The `human` gate before `enact` is untouched.** That is where those five classes legitimately land
and where an irreversible act is authorised. What ends here is the ratification of a *technical
plan*, not both approvals.

Record the verdict once the review round closes:

```
keel-state.ps1 record-verdict -Phase W<n>.<p> -Gate plan -Verdict APPROVED
```

## Gate 4 — implement

### Actor `agent`

**Check the repos before you touch them** — a declared repo may have moved, be on the wrong branch,
or have a detached HEAD since planning:

```
keel-state.ps1 repos
```

Then do the work and produce **one patch per declared repo**. Resolve each repo's path from the
registry in `keel.json`: a relative path resolves from the project folder, and one marked `external`
points at a repo this project references but does not own, whether that path is absolute or relative:

```
git -C <resolved path for that repo> diff > "<phase dir>/changes-<name>.patch"
```

The wrapper refuses if a declared repo has no patch (exit 96). That is the multi-repo trap: two of
three repos get committed and the record cites a change that does not exist in the third.

**On an external repo, tread carefully.** It has its own remote, its own CI and its own conventions,
and something other than this project depends on it. Never move it, never reorganise it, and preview
every commit against it exactly as you would a deploy.

**When the phase declares no repos**, its output is documents, records or a decision rather than
code, and there is no patch to take. Write `act-log.md` instead — the same artifact and the same
`Done by:` / `Done on:` contract the other actors use, with `Done by: claude`:

```
Done by: claude
Done on: <yyyy-MM-dd>
Produced: <each file you wrote, by path>
```

Name what you produced. A phase whose only evidence is that something happened is the case the
`record` gate then has nothing to point at. This route exists because without it an agent
phase in a repo-less project could not satisfy the gate at all — it is not a way around the patch.
If the phase *did* touch code, the repo belongs in the registry: `add-repo`, then
`revise-phase -Repos`, and the patch is required again.

### Actor `self` or `external`

**The human or the third party acts. You do not.** Tell the human exactly what to do, in a form
they can follow without you, and wait.

When it is done, write `act-log.md`:

```
Done by: <who - a name, not "the user">
Done on: <yyyy-MM-dd>
Evidence: <reference number / path / transaction hash / sender and date>
```

Both `Done by:` and `Done on:` are required (exit 96). "It's done" with no date is unauditable three
weeks later, and three weeks later is when it matters.

If the phase is `external` and they have not delivered, this is not a failure — set waiting and
hand back.

## Gate 5 — verify

**A fresh subagent that never saw the work being done** (charter P5). Brief from
`templates/VERIFIER_BRIEF.md`. The author's context is full of the reasoning that produced the
change, including the rationalisations; a verifier that inherits them inherits the blind spot.

**Two classes of keel-produced material meet here.** The verifier's report **and the corrections it
proposes**, which come back to you as the next iteration; and, separately, **your own repair between
rounds**, which the next round's verifier does not read — it re-runs the check rows. Both are
governed by **"Material keel produced is re-measured before you act on it"** in
`keel-orchestrator/SKILL.md`, and the brief's carried-forward slot — required, filled on every
brief — is what gives the second of them a reader. No check reads that slot and none is being added;
what makes an omission visible is the fresh verifier, who is told the slot must be there.

It writes `verify-report.md`, which needs:

- **a row per check**, matching `| W<n>.<p>-C<n> |`, each carrying `run-by:`
- **a `Positive control:` line**

The wrapper refuses otherwise (exit 96). **What it refuses is a check *id* with no attributed row
anywhere in the file, not every unattributed row** — a recap table repeating ids an earlier table
already attributed is fine. Attribute every row anyway: that is the
house standard, it is what the shape above shows, and it always conforms.

`INCONCLUSIVE` is a legitimate and *important* verdict. A check that could not be run is recorded as
not run — never as passed, and never quietly dropped. On `self` and `external` phases the verifier
cannot re-run the act; it checks the **evidence**, and evidence it cannot inspect is
`INCONCLUSIVE`.

**A check the spec declared `post-enact` is recorded `INCONCLUSIVE` by that declaration**, with the
spec's own reason carried into the evidence cell. It was never runnable here — its evidence is
produced by an act two gates later — and the declaration is what makes that an expected outcome
rather than a surprise. The delivery record answers it (gate 8).

**Never record such a check `PASS`.** Not on the strength of the declaration, not because the act is
planned, not conditionally on the enactment succeeding, and not because every other check passed.
The declaration says where the answer will come from; it never supplies the answer. A `PASS` here
tells the next reader the check was run when nothing was run, which turns a mechanism for honest
uncertainty into a mechanism for shipping unrun checks — the one failure this rule exists to
prevent. `INCONCLUSIVE` is the honest verdict and it is also the correct one.

**A repair after a PASS is followed by another verify round.** If anything the verifier read changes
after it returned `PASS` or `INCONCLUSIVE` - a deliverable, a patch, a record it checked - run
another round before the human gate, because the verdict on file was never run against the repaired
version. The wrapper makes the gap visible rather than refusing it: a `PASS` or `INCONCLUSIVE` stores
a fingerprint of what it verified, and the `human`, `enact` and `record` gates and `status` print a
warning when it has moved since - the gates name up to ten paths, `status` the count and the first -
while still recording. The writes gates 6 to
8 require - the enact and delivery records, the commit, the spec append, the next prompt, a
line-ending repair to a pinned file, the index rebuild and the handoff - do not count as moves.
A version acknowledgement that changes only `keelVersion` in `keel.json` usually does not count
either, but the exception is narrow: a `keel.json` already differing at verify, a tree over the path
cap, and a `keel.json` reached through a declared repo rather than the project tree are known to
warn, and that list is not claimed to be complete.

```
keel-state.ps1 record-verdict -Phase W<n>.<p> -Gate verify -Verdict <PASS|FAIL|INCONCLUSIVE>
```

On `FAIL`: `new-iteration -Trigger verify`. **Exit 2 means the cap is reached — STOP**, set stage
`escalated`, and hand the accumulated feedback to the human. Nothing was incremented. The cap is the
script's verdict, not your memory of how many times you have looped.

**A check that fails because it enforces a decision the operator now wants changed is not the
implementer's to repair:** put the decision to them as a tradeoff, and if they amend it, amend the
checks written from it in the same answer, before the next round - see "An earlier decision is a
tradeoff to show, not a rule to enforce" in `keel-orchestrator/SKILL.md`.

**A check or control measured wrong, with no decision behind it, has a route of its own:** see "An
earlier decision is a tradeoff to show, not a rule to enforce" in `keel-orchestrator/SKILL.md`.

**Write the `-Detail` so the cap can show a trend.** Every `new-iteration -Detail` states how many
findings the round returned and whether any of them is in a measured fact rather than in prose about
one - for example `4 findings, 1 in a measured fact: C3's count was taken before the last edit`.
When the cap refuses, it prints every round's detail in order, and that line is what the human reads
to judge whether the loop is converging. **The cap can be raised with `lift-cap`, for this phase
only and only on the operator's own words** - never on your own judgement, which is the loop the cap
exists to stop. What to do after a lift is in `keel-orchestrator/SKILL.md` Step 5.

## Gate 6 — human

Present, in one place:

1. **The change set** — the patches, or the act log and its evidence.
2. **The verify report**, including every `INCONCLUSIVE`.
3. **The advisor question ledger** — every question you resolved without asking, and on what basis.
4. **Any `SUPERSEDED` line this phase wrote** - which check or control, and what was measured.

Run `keel-state.ps1 status` before presenting, and put any warning about this phase's verify binding
in front of the human with the change set: the `human` gate's own
comparison runs only when its verdict is recorded, which is after the approval it should inform.

Then wait. `APPROVED` or `REJECTED`.

**This is the question keel gets wrong.** Write it under **"Asking the human — the question must be
answerable without keel's vocabulary"** in `keel-orchestrator/SKILL.md`, the skill that dispatched
this one — an approval given without understanding is the failure that produced this rule.

## Gate 7 — enact

**The irreversible outward act.** Filing, signing, sending funds, publishing, broadcasting,
deploying, pushing.

Answer both questions **before** acting (charter P21):

```
keel-state.ps1 record-verdict -Phase W<n>.<p> -Gate enact -Verdict DONE -Reversible <none|partial|full> -Observable <yes|no>
```

`enact-record.md` must carry `Reversible:` and `Observable:` lines.

- **No enactment in this phase** → `-Verdict N/A`. No artifact needed.
- **Irreversible AND currently unobservable** → the wrapper refuses `DONE` (exit 95). Record
  `DEFERRED` and hold until the outcome can be read. That is the gate working.

**Whether a preview is owed at all is decided by the two answers above** — see "Whether to ask, or
to act and report — reversibility decides" in `keel-orchestrator/SKILL.md`, which is where that rule
is stated. `Reversible: none` always asks.

Where one **is** owed, **preview the exact thing before it happens** (charter P6) — the literal text
of the form, the exact amount and destination, the exact commit and branch. A preview that
summarises is not a preview. Uncertainty defaults to *not* acting, and uncertainty about which class
an act falls into resolves to `none`, which asks.

## Gate 8 — record

Write `delivery-record.md`. It must name the phase id **in uppercase** — that is the only index
across every project — and carry one evidence reference per declared repo.

**The patch stays as gate 4 took it.** `changes-<repo>.patch` is taken at gate 4 and not re-taken
here. The enact commit has moved `HEAD`, so the gate 4 command would now diff against the new `HEAD`,
and the fingerprint would report the patch as moved. If a repair after verify really changed the
work, that warning is correct: re-take the patch and run another verify round (gate 5).

**It must also answer `Docs impact`, and that obligation is universal.** Every delivery record, in
every project, answers it. The answer is either the files under the project's docs root that this
phase changed, or the single word `none`:

```
Docs impact: none
```

Write the label as those two words — `Docs impact`, not `Docs-impact`. A `## Docs impact` heading
with the answer under it counts, and so does the bold form.

**`none` is a valid answer and the expected one.** What is required is the *statement*, not an edit.
Most phases legitimately change no document, so a rule demanding an edit would refuse correct work
and train the author to fabricate a cosmetic one.

**A project with no docs root still owes the line, and what it writes is `none`.** A project
declares a docs root with a `docs` key in its `keel.json`; most have none, and there is then nothing
under a docs root for a phase to have changed, so the answer is `none` every time. The wrapper
refuses a missing answer at exit 96 **only** where that key is declared — so in a project without
one the line is owed by this rule and not enforced by an exit code. Write it anyway: it is the same
question, and the phase that finally declares a docs root should not be the first one asked.

**It must also answer `Remaining phases`, and that obligation is universal too.** Every delivery
record, in every project, answers it. The question is whether the phases still pending in this
workstream — their scope, their order, their existence — still hold now that this phase has
delivered. The answer is either `unchanged`, or one line naming what no longer holds:

```
Remaining phases: unchanged
```

Write the label as those two words — `Remaining phases`, not `Remaining-phases`. A
`## Remaining phases` heading with the answer under it counts, and so does the bold form.

**`unchanged` is a valid answer and the expected one.** Most phases move nothing about the ones
after them, and under charter P16 a record saying so is complete work. What is required is the
*statement*, not a re-plan — a rule that demanded a change would manufacture churn, which is the
half of the manual loop this port deliberately left behind.

**A phase with nothing after it still owes the line, and writes `no phases remain`.** The last
phase of a workstream is the obvious case to exempt, and exempting it is how a line becomes
optional everywhere. `no phases remain` is an answer, not an exemption.

**Where the answer is not `unchanged`, do not re-plan here.** Name in one line what no longer
holds, finish the record, and hand back. The re-planning route already exists — `keel-orchestrator`
section "the plan changed (re-planning mid-workstream)" — and it makes re-planning a *different
session* from an implementing one, deliberately. Asking the question is what this rule adds;
answering it with a re-plan in the same breath is what it does not.

**Nothing refuses a missing answer, and that is deliberate.** Unlike `Docs impact`, this line is
checked by no exit code anywhere; it is owed by this rule alone. Charter P13's ladder starts a new
rule at prose and climbs only on a cited failure, and this one has never run. Write it anyway.

**It must also answer every check the spec declared `post-enact`.** Such a check came back
`INCONCLUSIVE` at `verify` by declaration, because its evidence is produced by the act at gate 7 —
which has now happened. Name the check by its `W<n>.<p>-C<n>` id and give the observation that
settles it: the issue number, what the remote answered, the confirmation reference. Where the act
did not produce what the check expected, say so — `still INCONCLUSIVE` with a reason is a complete
answer, and a declared check left unmentioned is how the declaration quietly becomes a way of not
running a check at all.

**No exit code guards this one either.** Nothing refuses a missing `post-enact` answer, at `record`
or anywhere else: the wrapper would have to read the project's spec to know which checks were
declared, a coupling it does not have. This rule is prose at one site, on the rung charter P13 starts
every new rule at. Write it anyway — the phase that finally has one is the wrong place to be asked
for the first time.

```
keel-state.ps1 record-verdict -Phase W<n>.<p> -Gate record -Verdict DONE
```

This marks the phase `delivered`, after which it cannot be revised (exit 90).

### Write the next phase's prompt — this is where later prompts come from

**Planning wrote exactly one prompt, and it was this phase's.** Every later phase's prompt is written
here, now, by the session that has just seen what this phase actually found — that is the whole of
the just-in-time flow, and skipping it leaves the next session with nothing to read.

Take the **next runnable phase in this workstream, by the spec's declared run order** — declared
data, never inferred from phase numbers — and write its prompt from
`keel-plan-workstream/templates/PHASE_PROMPT_TEMPLATE.md` to `plan/prompts/W<n>.<p>-prompt.md`.
Then register it onto that phase:

```
keel-state.ps1 revise-phase -Phase W<n>.<p> -PromptPath plan/prompts/W<n>.<p>-prompt.md
```

**Registration is not bookkeeping.** `status` prints a `brief:` line at exactly one boundary — the
next phase is named **and** it carries a `promptPath` — so a prompt written and never registered is
a prompt the next session is not told about, and the boundary silently becomes one that owes a
handoff instead.

**Where there is no next phase — the last phase of the workstream — nothing is written**, and that
is the correct outcome, not an omission. Do not invent a phase to have something to write for: the
wrapper exits 94 on an undeclared phase. The next event there is close-out.

**Write it before the rebuild below.** The prompt lands under `plan/`, which `keel-index.ps1` scans,
so it belongs in the same rebuild-and-stage step as the spec and the delivery record — one order, not
a second one.

Then **append** the delivery record to the spec's §5, below the plan text. **Do not rewrite the plan
above it** — the plan as written is the record of what was intended, and the difference is the
useful part.

**That append stales the document index — rebuild it in the same commit.** The spec lives under
`plan/`, which `keel-index.ps1` scans, so `reference/INDEX.md` is wrong until it is rebuilt — and in
a project whose commit gate checks the index, the commit is refused until you do. (Keel's own does,
in `scripts/check-suite-docs.ps1`; not every project has one, and the rebuild is owed either way.)
The order is stated once, in `keel-orchestrator`'s "Ending a
session" section — follow it there. Here that means: append the record, repair line endings if a
byte count shows any are owed, run the rebuild (the command is under "Rebuilding the index" in
`keel-project-context`), then stage the
spec **and** the rebuilt `reference/INDEX.md` in one commit. Rebuilding without staging the index
leaves the gate green and commits a stale one.

### Then render the whole shape

The phase is delivered. **Before you hand back, show the human where it sits.** They did not watch
the work, so a summary of what changed gives them nothing to hang it on.

Run **both** verbs — neither alone is the answer:

```
keel-state.ps1 tree            # the hierarchy, and each goal's STORED status label
keel-state.ps1 goal-coverage   # COMPUTED linkage: which workstreams claim which goal
```

**Reconcile them, and surface any disagreement instead of resolving it.** `tree` prints the label
stored on a goal — `[UNADDRESSED]`, or nothing at all once it is claimed. `goal-coverage` computes
the same judgement from live workstream links — `CLAIMED by 2: W3, W7`, or
`UNADDRESSED (declared)`. The two can drift apart, and do. Where they
disagree, print **both** readings and say that they disagree; do not pick one. Two authorities
disagreeing is itself the finding (charter P10, one authority per fact), and the stale side is
usually the stored label — which is exactly why quietly preferring it would be the wrong repair.

**The raw verb output is the input, not the deliverable.** Render it as an indented hierarchy —
goals, then workstreams, then phases — with a status marker on every line, and **mark the phase you
just delivered** so the reader finds it without counting. Expand every identifier where it first
appears: a goal id with the goal's text, a phase id with its scope. Someone who does not know what
`G3` or `W7.2` stands for must still be able to read it.

**The whole shape, every time — not the delta.** Every goal, every workstream, every phase,
including the ones this phase did not touch. A delta tells a reader who was already oriented what
moved; this render is for the reader who was not.

**Before you hand back, write the handoff** — see "Ending a session — write the handoff before you hand back" in `keel-orchestrator/SKILL.md`.

## Throughout — record friction as it happens

```
keel-state.ps1 note-friction -Phase W<n>.<p> -Kind <correction|rework|assertion|gap|stale-doc> -Detail "<what>"
```

Whenever the human corrects you, a document turns out stale, an absence claim needs a second
attempt, or work is redone. Seconds now; the entire evidence base for close-out later.
Reconstructing it afterwards does not work — the conversation will have compacted.

## Must not

- **Run a second phase.** One phase, then hand back to `keel-orchestrator`.
- **Verify your own work in your own context.**
- **Record a verdict before the artifact is written.**
- **Skip a gate because the change is small**, or because the actor was not an agent.
- **Claim an act you did not perform.** On `self` and `external` phases you are recording, not doing.
- **Commit, push, file, sign, send or deploy on your own initiative** — beyond what the
  reversibility rule in `keel-orchestrator/SKILL.md` permits you to perform and report. Anything
  irreversible is always previewed and always confirmed.
- **Expand scope.** If the phase needs more than its scope, that is a finding — stop and hand back
  for re-planning.
- **Argue with an exit code.** 96 means fix the artifact.
- **Edit `plugins/**`.** If keel is wrong, file a signal (charter P25).
