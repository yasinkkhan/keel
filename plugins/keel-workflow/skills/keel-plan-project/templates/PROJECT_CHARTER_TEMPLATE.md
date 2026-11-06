<!--
PROJECT CHARTER TEMPLATE - fill and write to <project>/CHARTER.md

This is the project's own charter, not keel's. It answers: what is this, when is it done, what is
deliberately outside it, and what am I aiming at.

It carries NO epics, workstreams or phases. Those live in the plan tree and in state.

Delete these comments as you fill in.
-->

# {{Project Title}}

**Created:** {{YYYY-MM-DD}} · **Last updated:** {{YYYY-MM-DD}}
**Folder:** `{{absolute path to the project folder}}`
**Config:** `keel.json` — git: {{yes/no}} · tracker: {{none/trello/jira/github}} · quarantine: {{yes/no}}

---

## 1. What this is

<!--
Two or three sentences a stranger could read. What is the situation, and why does it need a project
rather than an afternoon.
-->

## 2. What "done" means

<!--
Concrete and falsifiable. Someone else should be able to look at the world and say yes or no.

  BAD   "get my taxes sorted"
  GOOD  "all five outstanding returns filed and accepted by the tax authority, any assessed balance paid or on a
         payment plan, and a monthly bookkeeping routine that has survived three months"

If you cannot write this section, the project is not ready to plan - it is ready to investigate.

Write it in the operator's words, or say that the planning session drafted it and they approved it.
When later work collides with it, it is put to them as a tradeoff and changed by an appended Decision
in section 9. See "An earlier decision is a tradeoff to show, not a rule to enforce" in
keel-orchestrator/SKILL.md.
-->

## 3. Why this is worth doing

<!--
The value statement. Keel will plan, gate, verify and ship whatever it is asked for, to a high
standard - this is the one section where the ask itself is examined.

ALL THREE PARTS. Two of three is not this section.

It is answered ONCE, here, at intake. It is deliberately not re-tested every phase: a value question
asked eight times per workstream is ceremony, and DESIGN-CHARTER.md P13 records what happens to
ceremony at 11pm before a deadline. Close-out reads it back after delivery.

Keel does not research or validate these three answers: they are yours. Whether to research the
project's own subject is a separate question, and yours too.
-->

**Who benefits, and how:**

<!--
A named person or role, and the concrete difference it makes to them. Not "users". Not "me, later".

  BAD   "it will make things easier"
  GOOD  "me, in April: the accountant currently bills 6 hours reconstructing what I could hand over
         in a spreadsheet"
-->

**How the benefit is recognised:**

<!--
What would be observably different if this worked. Something you could check without re-reading the
plan.

  BAD   "the finances will be in better shape"
  GOOD  "I can answer 'what did I earn in 2023' in under a minute, from one place, without opening
         a bank statement"
-->

**What would make abandoning this the right call:**

<!--
The abandonment condition - a fact you could discover, or a date you could reach, after which
continuing is the wrong choice. THIS IS THE PART THAT DOES THE WORK, AND THE PART THAT GETS DROPPED.

A project with no abandonment condition cannot be abandoned on evidence, only on exhaustion. It runs
until whoever is running it is tired of it, which is a worse reason and arrives much later.

  BAD   "if it stops being useful"
  GOOD  "if the accountant quotes under 800 to do all five years, this is worse than paying them,
         and I stop"

If the honest answer is "nothing would make abandoning this right", write THAT down, with its
reason. A project you would finish regardless is a different thing from one nobody has thought
about stopping.
-->

## 4. Scope boundary — what this project does NOT cover

<!--
Argued, not listed. This is the most valuable section in the document at project scale: the boundary
is what stops a project growing a new area every month.

For each exclusion say where it went instead - another project, a later one, or "not doing".

An exclusion the operator could plausibly want is put to them before it is written here, and says who
decided it. See "An earlier decision is a tradeoff to show, not a rule to enforce" in
keel-orchestrator/SKILL.md.

  "Incorporation and the corporate return: OUT. This project is personal filings only. If the
   business needs restructuring that is its own project, because it has its own deadlines, its own
   counterparties and its own definition of done."
-->

## 5. Goals

<!--
Flat, cross-cutting, and stated as STATES OF THE WORLD rather than activities. Any workstream may
claim several - that is why they are links rather than a level of the tree.

Three to five is usually right. One means this is a workstream. Ten means section 4 is not working.

These must match what is registered with `keel-state.ps1 add-goal`; state is the authority for
which are claimed, this file is the authority for what they MEAN.
-->

| ID | True when this project is done |
|---|---|
| **G1** | {{a state of the world}} |
| **G2** | {{a state of the world}} |
| **G3** | {{a state of the world}} |

## 6. What is already true

<!--
MEASURED, with the date and how. The starting position: what exists, what has been done, what the
current mess actually is.

State what you did NOT check. An inventory whose gaps are unstated reads as complete, and a gap here
is work that silently never gets planned (charter P7).
-->

**Measured {{YYYY-MM-DD}}:**

**Not checked:**

## 7. Constraints and deadlines

<!--
Hard dates, statutory or contractual, and who imposes them. Distinguish:

  DEADLINE     externally imposed, with a consequence for missing it
  TARGET       self-imposed, moveable

Recording a target as a deadline burns urgency you will need later. Recording a deadline as a
target is how a penalty arrives.

Phase-level dates go on the phase (-Due). This section is for the ones that shape the whole project.
-->

| Date | What | Deadline or target | Consequence of missing |
|---|---|---|---|
| {{YYYY-MM-DD}} | {{what}} | {{deadline/target}} | {{what actually happens}} |

## 8. Counterparties

<!--
Everyone outside this machine whose action the project depends on, and what they owe. These become
`external` actors on phases and the reason `waiting` exists. Whether to engage and pay one - an
accountant, counsel, an auditor - is the operator's call, not a planning default: ask them, with what
each route costs, before writing them here, and say who decided it. See "An earlier decision is a
tradeoff to show, not a rule to enforce" in keel-orchestrator/SKILL.md.

Do not record identifying detail here if this project has quarantine on - a role and a first name is
enough (charter P23).
-->

| Who | Role | What this project needs from them | Typical turnaround |
|---|---|---|---|

## 9. Decisions

<!--
P1..Pn, project-level only - decisions that bind more than one workstream. A decision inside one
workstream belongs in that workstream's spec.

AMENDMENTS ARE APPENDED as new dated rows, never edits: the superseded reasoning is the record of
why the project went the way it did.

WHO DECIDED. Open each Reasoning cell with one of two labels: **Decided by the operator** (they chose it
on this specific point - in their own words, or by approving text put to them on that point; say which,
and date it) or **Proposed by the planning session** (approved with the charter as a whole). A row
that would rule out an option they could plausibly want is put to them before it is written. A
preference they want every workstream to respect - no paid professionals, no software built - belongs
here once, labelled as theirs, so planners cite it instead of asking again. Rows written before this
label existed stay valid. See "An earlier decision is a tradeoff to show, not a rule to enforce" in
keel-orchestrator/SKILL.md.
-->

| ID | Date | Decision | Reasoning |
|---|---|---|---|
| **P1** | {{YYYY-MM-DD}} | {{decision}} | {{Decided by the operator / Proposed by the planning session}} {{why, including what was rejected}} |

## 10. Open questions

<!-- Strike through and date as answered, rather than deleting. A struck question records that it was considered. -->

## 11. Session log

<!--
What each planning session covered. This is what makes a project resumable across months: it tells
the next session where the last one stopped and, more usefully, WHY it stopped there.
-->

| Date | Covered | Left open |
|---|---|---|
| {{YYYY-MM-DD}} | Charter, scope boundary, {{n}} goals registered | Nothing decomposed yet |
