<!--
SPEC TEMPLATE - fill and write to <project>/plan/workstreams/W{{N}}_name.md

Section numbering and order match every other spec. Do not rearrange: readers navigate by number,
and phase prompts cite "section 5, phase W4.2".

Delete these comments as you fill each section. Keep the keel:phases line - it is machine-read.
-->

# W{{N}} — {{Title}}

**Status: PLANNED — no phase delivered yet.** · **Created:** {{YYYY-MM-DD}} · **Last updated:** {{YYYY-MM-DD}}

**Parent:** {{E<n>, or "project root"}}
**Goals:** {{G1, G2}}
**Repos:** {{repos/<name>, or "none - this workstream produces no code"}}
**Source:** {{tracker card, epic ledger row, or the conversation that started it}}
**Related:** {{W<n> — one line on how}}

<!-- keel:phases {{W4.1,W4.2,W4.3}} run={{W4.2,W4.1,W4.3}} -->
<!--
   Machine-readable, invisible when rendered, greppable. `phases` lists every declared phase;
   `run` is the ORDER THEY ACTUALLY RUN IN, which is often not numeric order. This must agree
   with the -RunOrder values registered in state; `status` reports disagreement as a warning.
-->

---

## 1. The finding

<!--
What is actually wrong or actually wanted, stated so someone who was not in the planning session can
evaluate it. MEASURED, not recalled - include the measurement and the date.

If a premise came from a tracker card, a document, or the user's own description, say that you
re-measured it and what you got. Every absence claim needs its positive control here.

  "Measured 2026-08-17: the 2023 statements folder holds 9 of 12 months; March, April and August
   are absent. Positive control: the same listing shows all 12 months for 2022, so the query does
   find files when they exist."
-->

**Measured {{YYYY-MM-DD}}:**

**Not read:**

## 2. Scope decision — what this workstream does not repair

<!--
The boundary, argued. Naming what is deliberately excluded is what stops phase 4 quietly growing
into a second workstream. Point excluded work at a tracker card, a later workstream, or "not doing"
rather than leaving it implied.

An exclusion the operator could plausibly want is put to them before it is written here, and says who
decided it. See "An earlier decision is a tradeoff to show, not a rule to enforce" in
keel-orchestrator/SKILL.md.

Anything you decided NOT to verify goes here too, explicitly.
-->

## 3. Decisions

<!--
D1..Dn. AMENDMENTS ARE APPENDED AS NEW DATED ROWS, never edits to an existing row: the superseded
reasoning is the record of why the workstream went the way it did. Only the human may change a
decision.

WHO DECIDED. Open each Reasoning cell with one of two labels: **Decided by the operator** (they chose it
on this specific point - in their own words, or by approving text put to them on that point; say which,
and date it) or **Proposed by the planning session** (approved with the spec as a whole). A row that
would rule out an option they could plausibly want is put to them before it is written. Rows written
before this label existed stay valid. See "An earlier decision is a tradeoff to show, not a rule to
enforce" in keel-orchestrator/SKILL.md.
-->

| ID | Date | Decision | Reasoning |
|---|---|---|---|
| **D1** | {{YYYY-MM-DD}} | {{decision}} | {{Decided by the operator / Proposed by the planning session}} {{why, including what was rejected and on what evidence}} |

## 4. Phase table

<!--
Each phase independently deliverable. The ACTOR column decides what evidence its checks accept; the
ANSWER LANDS column names the file or record the phase's output is written to, which is the artifact
its checks are written against; the ENACT column decides whether the phase ends in an irreversible
outward act, which is where the attention goes.

Mark delivered phases as they land. An incomplete cell here is a defect - this table is the index a
phase gets run from.
-->

| Phase | Scope | Actor | Repos | Due | Answer lands | Enact step |
|---|---|---|---|---|---|---|
| **W{{N}}.1** | {{scope}} | {{agent/self/external}} | {{repos/x, or —}} | {{date or —}} | {{the file or record this phase's output is written to}} | {{what irreversible thing happens, or "none"}} |
| **W{{N}}.2** | {{scope}} | {{...}} | {{...}} | {{...}} | {{...}} | {{...}} |

**Run order: {{W4.2, W4.1, W4.3 — and why}}.**

<!--
Say WHY when it is not numeric. The commonest good reason: an `external` phase with a long
turnaround runs first so its waiting time overlaps everything else.
-->

## 5. Phases in detail

### Phase W{{N}}.{{p}} — {{short name}}

{{What happens and why. Name files by symbol, heading or unique string, never by line number (charter P8).}}

**The requirements this phase is asked to produce, enumerated:**

| # | Requirement | Covered by |
|---|---|---|
| R1 | {{one thing this phase's row demands the phase produce}} | W{{N}}.{{p}}-C1 |
| R2 | {{...}} | **uncovered** — {{why that is acceptable}} |

<!--
Taken from the row's own sentences - its line in the section 4 phase table together with this
block's opening description - and never from the shape of the deliverable you expect. See "The check
set covers what the row demands" in keel-plan-workstream Step 4, which is the rule this slot exists
for. A demand with no check is written in as `uncovered` with a reason, not deleted. A constraint on
HOW the phase works is not a requirement: leave it out of this table, and record the check that
enforces it as covering no requirement.
-->

**Actor:** {{agent / self / external}}{{ — and if external, who}}

**Checks — each must be able to fail:**

- **W{{N}}.{{p}}-C1** — {{a falsifiable assertion, with the observable that decides it. If it proves
  an absence, name the positive control.
  Run that control and write what it printed, or write `unmeasured` beside it — see "A control
  varies the one thing that could make the claim wrong" in `keel-orchestrator/SKILL.md`.
  If a human must run it, say so HERE rather than at verify
  time. If it was written from a recorded Decision, goal or scope exclusion, name it, as
  `(from D3)`, so an amendment to that decision finds the checks it carries.}}
- **W{{N}}.{{p}}-C2** — {{...}}

<!--
A check whose evidence only the ENACT act can produce — the issue number a filing returns, the remote
that answers only once the push has landed — stays in the list and is declared `post-enact`, with the
reason it cannot be decided earlier written inline after the assertion:

- **W{{N}}.{{p}}-C2** — {{the assertion}} `post-enact`: {{why its evidence cannot exist until the act
  has happened}}

It is then recorded INCONCLUSIVE by that declaration at verify, never PASS, and the delivery record
answers it. A phase carrying one comes back overall INCONCLUSIVE, so declare only the check that
genuinely cannot be moved earlier — and move the one that can.
-->

**Repos:** {{repos/<name>, or —}}
**Due:** {{date, or — . Only if the date is real; an invented one trains you to ignore OVERDUE.}}
**Enact:** {{what irreversible outward act ends this phase, or "none".}}
  **Reversible:** {{none / partial / full}} · **Observable:** {{yes / no — and if no, what would make it observable}}
**Waiting risk:** {{who could block this and for how long, or "none"}}
**Risk:** {{low / medium / high — and what specifically could go wrong}}
**Out of scope for this phase:** {{what a reader might reasonably assume is included and is not}}

<!--
When the phase ships, APPEND a delivery record below this line. Do not rewrite the plan above it -
the plan as written is the record of what was intended, and the difference is the useful part.

#### Delivered {{YYYY-MM-DD}} — {{one line}}

Everything above this heading is the plan as written; nothing in it was rewritten. What follows is
what happened.

| Check | Result | run-by | Evidence |
|---|---|---|---|
| **W{{N}}.{{p}}-C1** | PASS | agent | {{command and its actual output}} |
| **W{{N}}.{{p}}-C2** | INCONCLUSIVE | — | {{why it could not be run, and who will}} |
-->

## 6. Out of scope

<!-- Whole-workstream exclusions, each with where it went instead and who decided it. One the
operator could plausibly want is put to them first - see "An earlier decision is a tradeoff to show,
not a rule to enforce" in keel-orchestrator/SKILL.md. -->

## 7. Open questions

<!--
Unresolved at planning time. Strike through and date them as they are answered, rather than
deleting - a struck question records that it was considered.
-->

## 8. Process lessons

<!--
Usually empty at planning time; filled during the work and at close-out. Lessons about HOW the work
went, not what it produced. A lesson with no citable moment from THIS workstream does not belong
here (charter P16).
-->

## 9. Was it worth it

<!--
Empty at planning time. Written ONCE at close-out, by keel-close-workstream Step 9. Two questions,
two or three sentences each, dated.

  1. Did this achieve what it was for? Judged against the project CHARTER.md's "How the benefit is
     recognised", written at intake. NO is an acceptable answer and is not a failure of the
     pipeline - record what was expected and what was observed.
  2. Is the declared order still right? What changed, what is now the highest-value next thing, and
     what should be dropped.

No estimate, no score, no number. If the order should change, that is a re-planning event in a
fresh session (keel-orchestrator "Step 3.5 - the plan changed"), not an edit here.
-->
