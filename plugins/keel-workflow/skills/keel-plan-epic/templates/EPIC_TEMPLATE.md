<!--
EPIC TEMPLATE - fill and write to <project>/plan/epics/E{{N}}_name.md

An epic is a DECOMPOSITION RECORD and a MANIFEST. It is not a spec: it carries no phases and no
checks, because those belong to the child workstreams.

The ledger in section 4 is the load-bearing part. A later planning session resumes from it.
Keep the tokens exact: NOT-DECOMPOSED / W<n> / E<n> / EXCLUDED.

Delete these comments as you fill in.
-->

# E{{N}} — {{Title}}

**Status: PLANNING — {{x}} of {{y}} areas decomposed.** · **Created:** {{YYYY-MM-DD}} · **Last updated:** {{YYYY-MM-DD}}

**Groups:** {{ONE line: what this epic groups. Not its title restated. The wrapper refuses a groups line equal to the title.}}
**Parent:** {{E<n>, or "project root"}}
**Goals served:** {{G1, G2}}
**Source:** {{the conversation, tracker card, or charter section that started it}}

---

## 1. What "done" means for this epic

<!--
Concrete and falsifiable. Name what is explicitly NOT part of done - section 2 argues it, but the
shape belongs here so a reader gets it in one paragraph.
-->

## 2. Scope boundary

<!--
What this epic does NOT include, argued. At epic scale this is what stops a decomposition growing a
new area every session. Point excluded work at a workstream, a later epic, or "not doing".

An exclusion the operator could plausibly want is put to them before it is written here, and says who
decided it. See "An earlier decision is a tradeoff to show, not a rule to enforce" in
keel-orchestrator/SKILL.md.
-->

## 3. Inventory — what exists that this must account for

<!--
MEASURED, with the date and the source. For anything phrased as "all X", go and look; do not recall.

State what was NOT enumerated. An inventory whose gaps are unstated reads as complete, and an area
missing here is an area that silently never gets built (charter P7).
-->

**Measured {{YYYY-MM-DD}}, by {{how}}:**

**Not enumerated:**

## 4. Decomposition ledger

<!--
THE RESUME POINT. One row per area. Exactly one status token per row:

  NOT-DECOMPOSED   identified, not yet a workstream
  W<n>             decomposed; that workstream owns it
  E<n>             grew into a sub-epic
  EXCLUDED         deliberately out; reason and who decided it in Notes, asked first if they could want it

A later session continues from the first NOT-DECOMPOSED row.
-->

| Area | Status | Goals | Blocked by | Notes |
|---|---|---|---|---|
| {{2023 bank ledger}} | `W{{n}}` | G1 | — | {{one line}} |
| {{2024 bank ledger}} | `NOT-DECOMPOSED` | G1 | {{2023 ledger}} | {{one line}} |
| {{Corporate return}} | `EXCLUDED` | — | — | {{why it is out, where it went instead, and who decided it}} |

**Decomposed {{x}} of {{y}}.** {{What the next session should pick up, and why this one stopped here.}}

## 5. Workstream manifest

<!--
Only rows that have a number. Declared order is the sequence you intend; "blocked by" is a REAL
dependency. Do not conflate them: a preference recorded as a dependency freezes a sequence that
could have flexed, and a dependency recorded as a preference produces a workstream that cannot
start when its turn comes.

Do NOT list phases here. Phases are planned per workstream, when that workstream is picked up,
against the world as it is then.
-->

| Order | Workstream | Goals | Finishes independently? | Blocked by | Mostly which actor? |
|---|---|---|---|---|---|
| 1 | **W{{n}}** {{name}} | G1 | yes | — | agent |
| 2 | **W{{n}}** {{name}} | G1, G2 | no — needs {{x}} | W{{n}} | external |

<!--
The actor column is a planning hint, not a contract - the actor is declared per phase. But an epic
whose workstreams are mostly `external` will spend most of its life WAITING, and that changes how
you sequence it: start the long-turnaround ones first.
-->

## 6. Decisions

<!--
E1..En, epic-level only - decisions that bind several workstreams. A decision inside one workstream
belongs in that workstream's spec. Amendments are APPENDED as dated rows, never edits.

WHO DECIDED. Open each Reasoning cell with one of two labels: **Decided by the operator** (they chose it
on this specific point - in their own words, or by approving text put to them on that point; say which,
and date it) or **Proposed by the planning session** (approved with the epic as a whole). A row that
would rule out an option they could plausibly want is put to them before it is written. Rows written
before this label existed stay valid. See "An earlier decision is a tradeoff to show, not a rule to
enforce" in keel-orchestrator/SKILL.md.
-->

| ID | Date | Decision | Reasoning |
|---|---|---|---|
| **E1** | {{YYYY-MM-DD}} | {{decision}} | {{Decided by the operator / Proposed by the planning session}} {{why, including what was rejected}} |

## 7. Open questions

<!-- Strike through and date as answered, rather than deleting. -->

## 8. Session log

<!--
What each planning session covered, and WHY it stopped where it did. This is what makes an epic
resumable across months.
-->

| Date | Covered | Left open |
|---|---|---|
| {{YYYY-MM-DD}} | Inventory: {{n}} areas identified | Nothing decomposed yet |
