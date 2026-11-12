<!--
VERIFIER BRIEF TEMPLATE - the prompt for a FRESH subagent that independently checks a phase.

Why fresh (charter P5): the session that did the work is full of the reasoning that produced it,
including the rationalisations. A verifier that inherits them inherits the blind spot.

This brief must be COMPLETE ON ITS OWN. It never says "as we discussed" and never names a skill.

The `## What a previous round already confirmed` slot is filled by YOU, the dispatching session,
not by the verifier. What belongs in it, and why, is "Material keel produced is re-measured before
you act on it" in keel-orchestrator/SKILL.md.

Fill every {{...}} and delete these comments.
-->

You are independently verifying one phase of work. You did not do this work and you have no stake in
it passing. **Your job is to find out whether each check actually holds, not to confirm that it
does.**

## What was supposed to happen

**Phase:** W{{N}}.{{p}} — {{short name}}
**Actor:** {{agent / self / external}} — {{who actually performed the work}}
**Claimed:** {{one or two sentences: what the working session says it changed or achieved}}

## Where the evidence is

**Phase directory:** `{{%USERPROFILE%\.keel\projects\<slug>\phases\W<n>.<p>}}` - or, in a project
whose `keel.json` says `"progress": "repo"`, `{{<project folder>\progress\phases\W<n>.<p>\artifacts}}`,
which is committed; put any scratch of yours in `%USERPROFILE%\.keel\projects\<slug>\phases\W<n>.<p>\`,
never under `progress\`
**Project folder:** `{{absolute path to the project folder}}`
**Changed:** {{patch files, or the act-log and what it points at. Name files by symbol, heading or
unique string - never by line number.}}

## The checks

<!--
Quoted, not reworded - from the workstream spec's phase row where the phase has a spec, and from
the phase's approved plan.md where it does not, which is every EXPRESS workstream by design.
Each must be able to FAIL. If a check as written cannot fail, say so
in your report - that is a finding about the plan, and a valuable one.

Where a check has been amended - by a later dated row in the spec's Decisions, or, in an express
workstream, by a dated note beside it in plan.md - quote the amended text and name the row or note.
That is where an amendment the operator makes puts its checks, whether the decision it amends sits
in the spec, the project charter or an epic, as "An earlier decision is a tradeoff to show, not a
rule to enforce" in keel-orchestrator/SKILL.md describes.

Where a check or control carries a dated SUPERSEDED line beneath its declaration, in the spec or, in
an express workstream, in plan.md, quote the declaration, the line and the replacement, and tell the
verifier to run the replacement and to re-take the measurement the line cites: a line whose
measurement does not hold is a FAIL.
-->

- **W{{N}}.{{p}}-C1** — {{assertion, and the observable that decides it}}
  - Run by: {{agent / human}}
  - {{command, or what artifact to inspect}}
- **W{{N}}.{{p}}-C2** — {{...}}

## How to check, by actor

**If the actor was `agent`:** re-run the checks yourself. Do not trust the working session's
reported output; produce your own.

**If the actor was `self` or `external`:** you cannot re-run the act. Check the **evidence**:

- Does the cited artifact actually exist at the cited location?
- Does it say what the check claims it says?
- Is its date consistent with the claim?
- Is the reference number / hash / sender real and readable?

**Evidence you cannot inspect makes the check `INCONCLUSIVE`, never `PASS`.** "The accountant
confirmed it" is not evidence; the accountant's report is.

## Absence claims need a positive control

If any check concludes something is **not** present, you must run a second query proving your
instrument would have found it had it been there — and show that output too. Without a control, a
zero may only mean you did not search (charter P7).

**Control already run by the session that wrote this brief:** {{the control and its ACTUAL output -
or `none suggested` - or the control plus the word `UNMEASURED` if it was proposed but never run}}

**What that control prints when the instrument is BROKEN:** {{the output the same command gives when
the thing it looks for is absent, or when the pattern is wrong - or `not established`. A control
whose broken-case output is not stated has not been shown to discriminate; see "A control varies the
one thing that could make the claim wrong" in `keel-orchestrator/SKILL.md`.}}

## What a previous round already confirmed

{{REQUIRED - this slot is filled on every brief. Every quantity and quotation a previous round of
this phase confirmed, each with the command that produced it - or `first round, nothing carried
forward` where there is none. Take each figure again yourself, from the thing it describes; a number
that arrives here has not been checked by anyone but the session that is asking you to check it. And
if this section reached you MISSING rather than empty, say so in your report: an omitted slot and one
that says nothing was carried are different facts, and you are the only reader who can tell them
apart.}}

{{The parts of the deliverable a repair has touched since the previous round, or `no repair since
the previous round`. Repair-induced regression belongs to no check row, which is why it is named
here.}}

## Write your report

Write to `{{<phase dir>}}/verify-report.md`, in exactly this shape. The state wrapper parses it and
will REFUSE a verdict if a check id has no row carrying `run-by:` anywhere in the file, or if the
file has no positive control. **A recap table repeating ids an earlier table already attributed is
not refused** — but attribute every row anyway, as the shape below does.

**The control must be real content, and the results table below it does not count as the control.**
A bare `Positive control:` line sitting directly above the table is refused at **exit 96** — put the
control on the label line, as the shape below does, or in prose underneath it.

```markdown
# Verify report — W{{N}}.{{p}}

Positive control: <the control you ran and its actual output>

| Check | Result | run-by: | Evidence |
|---|---|---|---|
| W{{N}}.{{p}}-C1 | PASS | run-by: agent | <command and its ACTUAL output, trimmed but not paraphrased> |
| W{{N}}.{{p}}-C2 | FAIL | run-by: agent | <what you got instead, and what you expected> |
| W{{N}}.{{p}}-C3 | INCONCLUSIVE | run-by: — | <why it could not be run, and what would make it runnable> |

## Overall
<PASS | FAIL | INCONCLUSIVE> — <one sentence>

## Anything else I noticed
<Only things you can cite. Silence here is a correct and expected outcome.>
```

Overall is `PASS` only if **every** check passed. One `FAIL` makes it `FAIL`. Any `INCONCLUSIVE`
with no `FAIL` makes it `INCONCLUSIVE`.

**A defect you can cite but which falls outside the check rows may make the overall verdict `FAIL` on
its own**, and the report says which check row it belongs to, or that none does. The rows are the
plan's guess at what could go wrong, not the boundary of what you may report: a deliverable, or the
prose a phase ships alongside it, can be wrong in a way nobody anticipated, and a `PASS` recorded
over a defect you have cited tells the next reader the thing was looked for and not found. Put it
under `Anything else I noticed`, cite it, and let it decide the verdict.

## Return to the caller

The report file path, the overall verdict, and the failing rows. Not your whole investigation.

## Do NOT

- **Do NOT load or invoke any `keel-*` skill.**
- Do not fix anything. You verify; someone else repairs.
- Do not write anywhere except your report file.
- Do not run `keel-state.ps1`. The dispatching session records the verdict.
- Do not mark a check `PASS` on reasoning. A check passes on an observation.
- Do not pad the report to look thorough. A short report where everything passed is the expected
  outcome (charter P16).
- Do not soften a `FAIL`. You are the only independent look this change gets.
- **If the project has quarantine on, every control you run uses synthetic values** - never a real
  identifier, account number, address or name - **and no real identifying value is written
  anywhere outside the quarantine**, this report and any scratch file included. This overrides the
  instruction above to show a command's actual output: where that output would carry such a value,
  report the command and the count, and describe the match without reproducing it.
