<!--
PHASE PROMPT TEMPLATE - fill and write to <project>/plan/prompts/W{{N}}.{{p}}-prompt.md

This is written for a FRESH session that has never seen the planning conversation. It must be
complete on its own: paths, commands, checks, and what is out of scope.

It must NEVER say "as we discussed", "the approach we agreed", or reference anything that exists
only in a conversation that will not exist when this runs.

Delete these comments as you fill in.
-->

# W{{N}}.{{p}} — {{short name}}

**Project:** {{slug}} · **Workstream:** W{{N}} — {{title}} · **Actor:** {{agent / self / external}}
**Spec:** `plan/workstreams/W{{N}}_{{name}}.md` section 5, phase W{{N}}.{{p}}
**Run order position:** {{n}} of {{total}} · **Due:** {{date or —}}

---

## Start here

Do not start work from this file. Start from:

```
keel-state.ps1 status
```

If this phase is already past a stage, **do not re-run that stage** — its verdict is recorded and
the state file outranks anything written here.

## What this phase changes

<!--
The concrete change. Name files by symbol, heading, or unique string - NEVER by line number, which
rots (charter P8). For a non-code phase, name the document, the portal, the form, the person.
-->

## What is already true

<!--
What the planning session MEASURED, with its date. This is a snapshot, not a guarantee: the ground
gate exists because this may have moved. Re-measure anything you are about to depend on.
-->

**Measured {{YYYY-MM-DD}} during planning:**

**Explicitly not checked then:**

## Checks this phase must pass

<!--
Copied verbatim from the spec so the verifier does not have to go and find them. If they disagree
with the spec, the SPEC is right and this file is stale - say so rather than resolving it silently.
-->

- **W{{N}}.{{p}}-C1** — {{assertion, and the observable that decides it}}
  - Positive control: {{the query proving the instrument works, if this proves an absence, AND what
    it actually printed}}
  - Broken-instrument output: {{what that same query prints when the thing is absent or the pattern
    is wrong - or `not established`. See "A control varies the one thing that could make the claim
    wrong" in `keel-orchestrator/SKILL.md`.}}
  - Run by: {{agent / human — decided at planning time, not at verify time}}
- **W{{N}}.{{p}}-C2** — {{...}}

## Out of scope for this phase

<!--
What a reader might reasonably assume is included and is not. Where it went instead.
-->

## The enact step

<!--
The irreversible outward act, if any. Filing, signing, sending, publishing, broadcasting, deploying.

If there is none, say "none" - and the enact gate is recorded N/A.
-->

**What happens:** {{or "none"}}
**Reversible:** {{none / partial / full}}
**Observable:** {{yes / no}} — {{how you will see that it landed}}

<!--
If reversible=none AND observable=no, the wrapper REFUSES a DONE verdict (exit 95). Record DEFERRED
and hold until it can be observed. That is the gate working, not an obstacle.
-->

## The delivery record

<!--
Gate 8. Left as fixed text in every generated prompt - it is the same question for every phase, so
there is nothing here to fill in. Delete it only if you have a reason, and say the reason.
-->

`delivery-record.md` must answer **`Docs impact`**, and every phase in every project answers it. The
answer is either the files under the project's docs root that this phase changed, or the single word
`none`:

```
Docs impact: none
```

Write it as those two words — `Docs impact`, not `Docs-impact`. A `## Docs impact` heading with the
answer under it counts, and so does the bold form.

**`none` is valid and is the common case.** What is required is the statement, not an edit — most
phases legitimately change no document, and demanding an edit would refuse correct work.

**A project with no docs root still owes the line, and writes `none`.** A docs root is declared by a
`docs` key in the project's `keel.json`; most projects declare none, so there is nothing under one to
have changed. The wrapper refuses a missing answer at exit 96 only where that key is declared, so
without it the line is owed by this rule rather than by an exit code. Write it regardless.

## If this phase waits

<!--
Only for `self` and `external` phases that depend on someone else.
-->

**Waiting on:** {{who or what — a name and a role, never "them"}}
**Expected turnaround:** {{how long, and on what basis}}
**Review on:** {{YYYY-MM-DD}}

```
keel-state.ps1 set-waiting -Phase W{{N}}.{{p}} -WaitingOn "{{who}}" -ReviewOn {{YYYY-MM-DD}}
```

## Do not

- Start implementing before the plan gate is APPROVED — which now means the fresh-subagent review
  has returned its findings and they have been resolved, not that the operator has ratified the plan.
- Verify your own change in your own context — the verify gate needs a fresh subagent (charter P5).
- Commit, push, enact, or write to a tracker without an exact preview and explicit confirmation —
  beyond what "Whether to ask, or to act and report — reversibility decides" in
  `keel-orchestrator/SKILL.md` permits you to perform and report. Anything irreversible is always
  previewed and always confirmed.
- Expand scope. If this phase turns out to need more, that is a finding: stop and hand back for
  re-planning rather than absorbing it.
- Record a check as passed without naming the file or command that decided it.
