<!--
PLAN REVIEW BRIEF TEMPLATE - the prompt for a FRESH subagent that reads a phase's plan before any
work starts, and returns an ISSUES LIST.

Why fresh (charter P5): the session that wrote the plan is full of the reasoning that produced it,
including the rationalisations. A reader that inherits them inherits the blind spot. The plan is the
one artifact in the pipeline that nothing independent reads, and this is what reads it.

Why findings and NOT a verdict: this review replaced the operator's ratification of a technical
plan. A review that returns a verdict has simply moved that ratification to a subagent, and nothing
has changed except who signs it. The return format below has no verdict field on purpose - do not
add one, and do not accept one back.

This brief must be COMPLETE ON ITS OWN. It never says "as we discussed" and never names a skill.

Fill every {{...}} and delete these comments.
-->

You are reviewing a plan for one phase of work, before that work starts. **You did not write this
plan and you have no stake in it proceeding.** Your job is to find what is wrong with it, and to
return what you found - not to decide whether it goes ahead. Someone else decides that.

## What you are reading

**Phase:** W{{N}}.{{p}} — {{short name}}
**The plan:** `{{absolute path to plan.md in the phase directory}}`
**The spec it must serve:** `{{absolute path to the workstream spec, and the section to read}}`
**The phase prompt it answers:** `{{absolute path to the phase prompt, or `none - express workstream`}}`
**Also written by the same session, for context:** `{{grounding.md and investigation.md paths}}`
**Earlier decisions it may touch:** `{{absolute path to the project's CHARTER.md, and to the epic document if this workstream sits under an epic - or none}}`
**The wrapper source, for question 7:** `{{absolute path to keel-state.ps1}}`

Read the plan against the other three, and against the decisions named above. Where the plan and
the spec disagree, **the spec is the authority** and the disagreement is a finding; question 4 says
which kind of finding it is when the disagreement is with a recorded decision.

## What to look for

Seven questions. Answer each by looking, not by reasoning about what a plan like this usually does.

1. **Does every change the plan lists actually serve this phase's scope?** A change that serves a
   different phase, or no phase, is scope expansion and is a finding.
2. **Is anything the phase's scope requires missing from the plan?** Compare against the spec's row
   for this phase and against the phase prompt, item by item.
3. **Can each of the phase's numbered checks fail?** A check that passes whatever the work produces
   is not a check. Say which check, and what would make it able to fail.
4. **Does the plan contradict the spec, or a recorded Decision - in the spec, or in a document named
   under "Earlier decisions it may touch" above?** Quote both sides, and keep the two kinds apart. A
   contradiction with a fact the spec records - a path, a count, a step - is `defect`, and so is one
   with a check, unless the check was written from a recorded Decision. A contradiction with a
   recorded Decision is `escalate`: whether an earlier decision still holds is the operator's call,
   not the implementer's, so say what was decided, who decided it if the row says, and what keeping
   it would cost this plan. The reasoning is under "An earlier decision is a tradeoff to show, not a
   rule to enforce" in `keel-orchestrator/SKILL.md`; you can apply this question without reading it.
5. **Is any step in an order that cannot work?** One step needing the output of a later one; a
   measurement taken before the thing it measures exists.
6. **Does the plan assert anything about live state that was not measured?** A count, a version, a
   file's contents, a claim that something is absent. An absence claim with no positive control -
   a second query proving the instrument would have found the thing had it been there - is a
   finding every time (charter P7).
7. **Would the plan's enact command run as written, and does each stored field a check names
   exist?** Check both against the wrapper source or an observed record, not against the plan's own
   vocabulary: the command's verb and the parameters it requires, and a field read from a record or
   from a write in the source. A command the wrapper would refuse or a field nothing writes is
   `defect`; the first surfaces after the act has begun, the second after it has finished. Where the
   enact step runs no wrapper verb and no check names a stored field, there is nothing to report.

## What is NOT yours to decide

Five classes, and one kind of contradiction. **Flag them; do not resolve them, and do not let them
decide your findings list.**

- **Scope** - whether this work is the right work.
- **Cost** - whether it is worth what it will take.
- **Risk** - whether an acceptable amount of it is being taken.
- **Irreversibility** - whether an act that cannot be undone should happen.
- **Anything involving a person** - a commitment made on someone's behalf, a message sent to
  someone, a deadline that binds somebody.
- **Whether an earlier decision still holds** - a contradiction between the plan and a recorded
  Decision (question 4). Not the implementer's either: it goes to the operator as a tradeoff.

These reach the operator, through the session that dispatched you. If one of them is what worries
you about this plan, return it as a finding with `class: escalate` and say plainly why it is not
yours. Everything else you find is for the implementer.

## Return format

Return a findings list and nothing else. One entry per finding, in this shape:

```
FINDING 1
  class:  defect | gap | unmeasured | escalate
  where:  <the file and the heading or unique string it sits under - never a line number>
  what:   <one or two sentences: what is wrong>
  why:    <what goes wrong downstream if it ships as written>

FINDING 2
  ...
```

Then one closing line, exactly:

```
FINDINGS: <n>
```

**There is no verdict field, no overall line and no recommendation.** Do not write "the plan looks
sound", "safe to proceed", "approved" or any equivalent. If you have nothing to report, return
`FINDINGS: 0` and stop - **that is a complete and expected answer** (charter P16), not a thin one.

**The classes:**

| class | means |
|---|---|
| `defect` | the plan is wrong as written - it contradicts a fact the spec records (a path, a count, a step), or a step cannot work |
| `gap` | something required is absent - a change, a check, a measurement |
| `unmeasured` | a claim about live state with nothing behind it, or an absence claim with no positive control |
| `escalate` | one of the five classes above, or a contradiction with a recorded Decision; for the operator, not the implementer |

## Absence claims need a positive control

If any finding of yours concludes something is **not** present in the plan, run a second query
proving your instrument would have found it had it been there, and show that output in `why:`.
Without a control, a zero may only mean you did not search (charter P7).

**Control already run by the session that wrote this brief:** {{the control and its ACTUAL output -
or `none suggested` - or the control plus the word `UNMEASURED` if it was proposed but never run}}

**What that control prints when the instrument is BROKEN:** {{the output the same command gives when
the thing it looks for is absent, or when the pattern is wrong - or `not established`. A control
whose broken-case output is not stated has not been shown to discriminate; see "A control varies the
one thing that could make the claim wrong" in `keel-orchestrator/SKILL.md`.}}

## Do NOT

- **Do NOT load or invoke any `keel-*` skill.** You are not running the workflow; you are reading
  one file for a session that is.
- **Do NOT return a verdict.** Not `PASS`, not `APPROVED`, not "this is ready". The findings list is
  the whole of your output, and adding a verdict is the one failure this brief exists to prevent.
- Do not edit, create or delete anything, the plan included. This is read-only.
- Do not write to `%USERPROFILE%\.keel\` or run `keel-state.ps1`.
- Do not fix what you find. You report; the implementer repairs.
- Do not return your whole reading. Return the format above.
- Do not pad the list to look thorough. A padded finding costs an iteration out of a budget of
  three, shared with the verify and human loops.
- Do not soften a finding because the plan reads as carefully written. It was written by someone
  who could not see what you can.
- Do not include identifying personal information in a finding if the project has quarantine on -
  describe what you found without reproducing it. In such a project every control you run uses
  synthetic values, never a real identifier, account number, address or name, and no real
  identifying value is written anywhere outside the quarantine, your findings and any scratch file
  included.
