---
name: keel-plan-workstream
description: Turns a prioritized intent or tracker card into a keel workstream spec plus the NEXT runnable phase's prompt - and only that one, because every later prompt is written just-in-time by keel-run-phase as its predecessor delivers - in the house format. Writes plan/workstreams/W<n>_name.md and plan/prompts/W<n>.<p>-prompt.md in the project folder. Dispatched by keel-orchestrator only - never a session entry point, even on "plan this", "write me a spec" or "break this into phases". Also runs in AMEND mode when a workstream already in flight turns out to be shaped wrong. Refuses to plan without a written grounding record and live re-measurement of every factual premise the ask asserts; a spec grounded in recall rather than measurement is the documented failure mode this whole system exists to prevent. Every phase gets a declared ACTOR (agent / self / external), numbered W<n>.<p>-C<n> checks that must each be able to fail, an optional due date, and a run order declared explicitly rather than inferred from phase numbers. Preview before every write; the human approves the spec before any phase prompt is generated.
---

# Plan a workstream

A workstream is **independently deliverable**: when its phases are done, something is finished and
could be handed over. It contains only phases, never other workstreams (charter P17).

## Step 1 — ground before you plan

**Refuse to plan from the ask alone.** Every factual premise gets re-measured, now:

- The ask says a file is broken → open it.
- The ask says "the 2023 statements are missing" → look in the folder, and prove the instrument
  would have found them: list a year you know *is* there (charter P7 — a positive control).
  That control varies the **source** and holds the **instrument**, which is the right shape for a
  claim about contents. Where the claim is about **reachability**, it is the instrument that must
  vary — see "A control varies the one thing that could make the claim wrong" in
  `keel-orchestrator/SKILL.md`.
- The ask cites a figure from a document → re-derive it.
- **The ask is a signal, and a signal's filed text is one of those documents** → re-measure it
  against the thing it describes before you quote it, and record what you got. A signal is written
  from one moment in one project by a session with a sample size of one, and it can be wrong about
  its own subject.

**Re-measurement does not stop at the ask's premises.** A factual claim about a primary source that
you write first — one that was nobody's premise and appears for the first time in §1 — is measured
against that source before the spec is written, and its measurement is recorded in §1 exactly as an
ask premise would be.

*Both obligations come from one spec, whose §1 carried two false claims about an earlier phase that
arrived by different routes. One appeared nowhere in the signal it was planned from - the spec wrote
it first - and the phase's preserved verify reports contradicted it. The other was in the signal
verbatim and was carried across unchecked: the signal was wrong about its own subject. Both survived
to close-out, where a step that exists for other reasons corrected them, and that step would not have
run at all had the workstream been express.*

**A prior phase's delivery record, and the spec section it was appended to, stand on the same footing
as a signal's filed text** — both governed by **"Material keel produced is re-measured before you act
on it"** in `keel-orchestrator/SKILL.md`.

Write what you measured, and **what you did not read**, into §1 of the spec. A premise you could not
check is recorded as unchecked, not quietly dropped.

**When a re-measurement refutes the filed premise, ask the person who filed it — before the
judgement document is written, not at the enact preview.** A refutation is the strongest evidence a
re-measurement can produce, and it is evidence about the *words*. It is not evidence about the
*defect* those words were reaching for. The filer holds what no instrument in the judging phase can
reach: how many times it has happened, which other project it happened in, and why they thought it
was worth filing at all. **Where the filer is reachable — every signal record names the project and
the machine it was filed from, so this is answerable rather than assumed — put the refutation to
them, and record their answer in the verdict as evidence, beside the measurement that refuted the
words.** Record it whether or not it moves the verdict: an answer that leaves the rejection standing
is what makes that rejection tested rather than merely unopposed. Where the filer is not reachable,
say so in the verdict — an unreachable filer is a stated limit on the judgement, not a silent one.
Ask in the form defined under **"Asking the human — the question must be answerable without keel's
vocabulary"** in `keel-orchestrator/SKILL.md`.

**Why the enact preview is the wrong place to find this out.** By then the judgement document is
written, independently verified and expensive to change, and the session holding it has just spent
several rounds establishing that it is right — which is the worst possible moment to hear the one
thing no instrument in the phase could have measured. *In one judging phase, four signals were put to
the operator for the first time at the enact preview, after the judgement document was written and
verified, and two of the four verdicts were overturned there, on evidence no instrument in that phase
could have reached.*

If grounding contradicts the ask, **stop and say so**. That is the most valuable output this skill
produces, and it is worth more than a spec built on the original premise.

## Step 2 — number it

```
keel-state.ps1 tree
```

Highest workstream number on disk + 1. **Measure it** — numbers get skipped, so "count + 1" is
wrong. Register it before writing the spec, so the number in the filename is the real one:

```
keel-state.ps1 add-workstream -Id W<n> -Title "<title>" -Parent <E<n>|root> -Goals G1[,G2]
```

`-Goals` is mandatory (exit 98). If you cannot name a goal this serves, you have found something
important: either the goal is missing from the charter, or this work should not be happening yet.

**Which of the two it is, is the operator's call, not yours:** put it to them with what the charter's
goals say and what this work would add - see "An earlier decision is a tradeoff to show, not a rule
to enforce" in `keel-orchestrator/SKILL.md`.

## Step 3 — write the spec

From `templates/SPEC_TEMPLATE.md`, to `plan/workstreams/W<n>_name.md`. Section numbering and order
are fixed — readers navigate by number, and prompts cite "§5 Phase W4.2".

The sections that carry the weight:

**§1 The finding.** What is actually wrong or wanted, measured, with the date. Every absence claim
carries its positive control.

**§2 Scope decision.** What this workstream deliberately does *not* repair, argued. This is what
stops phase 4 quietly becoming a second workstream.

**An exclusion the operator could plausibly want done is theirs to make, not yours** - put it to them as
a tradeoff before §2 records it, as "An earlier decision is a tradeoff to show, not a rule to
enforce" in `keel-orchestrator/SKILL.md` describes.

**§3 Decisions.** `D1..Dn`. Amendments are **appended as new dated rows, never edits** — the
superseded reasoning is the record of why the workstream went the way it did.

**Each row says who decided it**, with the label `SPEC_TEMPLATE.md`'s Decisions comment names, and a
row that would rule out an option the operator could plausibly want is put to them before it is
written - see "An earlier decision is a tradeoff to show, not a rule to enforce" in
`keel-orchestrator/SKILL.md`.

**§4 Phase table.** Each phase independently deliverable, each with an **actor**, and each naming
where its answer lands. The column and what belongs in it are defined in `SPEC_TEMPLATE.md` — a
check can only be written against a specified artifact, so a phase whose output has no named home
cannot be checked. **Specs written before this column existed remain valid and need no edit**; the
requirement applies to phases planned from here on.

**§5 Phases in detail.** Where the checks live.

## Step 4 — phases, actors, and checks

### The actor is a planning decision, not a detail

For each phase ask: **whose hands?**

| Actor | When | What it changes |
|---|---|---|
| `agent` | Claude can do it and verify it | Evidence is command output and patches |
| `self` | Only you can — a portal, a signature, a phone call, moving money | Evidence is an artifact you point at |
| `external` | Someone else does it — accountant, auditor, counsel, exchange | Evidence is the received deliverable; expect long `waiting` |

**Do not plan a project as though it were all `agent` work.** The commonest planning failure in a
non-software project is a phase table full of things Claude can do, with the real blockers —
the KYC submission, the audit, the signature — left as implicit background. Those are phases. Give
them numbers, actors and due dates, or they will not be tracked and they will be what actually
holds the workstream up.

**Whether to bring in a third party at all is the operator's call, not a planning default:** before
planning an `external` phase that would engage and pay someone, or a Decision that rules out doing
it themselves, ask them, or cite the charter row where they already said - see "An earlier decision is a
tradeoff to show, not a rule to enforce" in `keel-orchestrator/SKILL.md`.

**Sequence for turnaround, not for tidiness.** An `external` phase with a three-week turnaround
should usually run *first*, even if it feels like the last step, because its waiting time overlaps
everything else.

### Checks that can fail

Each phase gets numbered checks, `W<n>.<p>-C1`, `-C2`, ... Each must be **falsifiable** and name
**the observable that decides it**.

**A check written from a recorded Decision, goal or scope exclusion names it** - `(from D3)` beside
the check - so that when the operator amends that decision, the checks it carries are found in the
same answer; see "An earlier decision is a tradeoff to show, not a rule to enforce" in
`keel-orchestrator/SKILL.md`.

> **Bad** — `W4.2-C1` — the ledger is correct.
> **Good** — `W4.2-C1` — every transaction in the 2023 bank CSV appears exactly once in
> `ledger.xlsx`; checked by row count and by summing debits, both compared against the bank's own
> year-end total. Positive control: a deliberately duplicated row is detected by the same query.

Rules:

- **If it proves an absence, name the positive control.**
- **A check decided by a text search must match text that cannot be there unless the deliverable
  is.** A keyword can land in a heading, in the sentence explaining why the change was made, or in
  the rationale paragraph the change itself added — so a pattern that returns hits proves the file
  was edited, not that it says the right thing. And a control showing the pattern finds nothing at
  HEAD proves only that the text is **new**. The control that counts discriminates against a
  plausible *wrong* implementation, not against the empty one. *A check once asserted that a
  three-part convention existed and decided it by a keyword grep - zero at HEAD, one in the tree. The
  single hit was a word inside the new section's own rationale paragraph, so the check would have
  passed identically had none of the three obligations it claimed to verify ever been written.*
- **If a human must run it, say so here**, at planning time — not at verify time, where it becomes
  an excuse.
- **A check nobody can run is not a check.** Say what would make it runnable, or drop it and record
  in §2 that this is unverified.
- **A check whose evidence the `enact` gate produces cannot be decided at `verify`, which runs
  earlier.** The order is `ground -> investigate -> plan -> implement -> verify -> human -> enact ->
  record`, so at the moment the checks are run the commit is unpushed, the form is unfiled and the
  issue is still open. That evidence belongs in the **delivery record**, which is written after the
  act — not in the check list. *A check once asserted that a signal was no longer OPEN and that a
  GitHub issue was closed, both outcomes of the enact gate, and the fresh verifier returned
  INCONCLUSIVE for structural reasons with nothing wrong with the work. That is the cost: the verify verdict
  stops discriminating, because a clean phase and a genuinely uncertain one come back with the same
  word.*

  **The one exception, and it is a declaration rather than a licence.** Where the evidence genuinely
  cannot exist any earlier — the issue number a filing returns, the remote that only answers once the
  push has landed — the check may stay in the list, declared `post-enact` **with the reason it cannot
  be decided earlier written beside it, here, at planning time**. At `verify` it is then recorded
  `INCONCLUSIVE` by that declaration, and the **delivery record** answers it. What the declaration
  buys is that the `INCONCLUSIVE` is expected rather than improvised, carries a reason written before
  anyone knew how the work would go, and is owed an answer in a document written after the act. **It
  does not buy back the cost above** — a phase carrying one still comes back overall `INCONCLUSIVE`
  at `verify` — so declare the check that cannot be moved, and move the one that can.
- **A control must exercise the same pattern as the claim it supports.** A control proving the
  search *ran* leaves the half that actually fails untested — whether the pattern *could* match.
  Distinct from the text-search rule above, which governs the **check's** pattern; this one governs
  the **control's**. *A suite's comparison mode once scored two byte-identical copies of the code
  under test as different - 0 failures against 1 - so the control meant to prove the suite detects a
  change passed a change of nothing at all. Its paired check, demanding the opposite verdict from the
  same command, is what stopped the first being satisfiable by deleting the mode.*
  **It fixes only half the question.** What a control must *vary* is stated once, in "A control
  varies the one thing that could make the claim wrong" in `keel-orchestrator/SKILL.md`.
- **A check asserting a literal must be run against the drafted deliverable text before the `plan`
  gate is recorded, and matched whitespace-flattened.** Reasoning that the string is there is not
  the act of matching it, and hard-wrapping puts line breaks inside the phrase you are matching.
  *A check once obeyed the text-search rule above exactly - it chose a token that could not exist
  unless the deliverable did - and still could never pass: it demanded one form of a verb where the
  prose in the same plan document used another, wrapped across a line break. Neither the word nor the
  break was visible to the session that wrote both, because the `plan` gate reviews the check list and
  the deliverable text as separate objects. It cost a full fresh-verifier round trip and one of the
  phase's few permitted iterations.*
- **A check must state the procedure that decides it, and the `plan` gate asks whether that
  procedure could reach a violation of what the check's own prose forbids** — not merely whether it
  could return FAIL — including any hazard in running it. *A check once forbade "a new state field"
  but decided it by diffing the `param()` block and the skill inventory, structurally blind to a new
  `keel.json` key - the exact question that phase had to adjudicate; the fresh verifier stated the
  check as written would have returned PASS even had that key been the violation. Every instance of
  this in that workstream was found by the verifier and none by the drafting session. The hazard half:
  another check required temporarily editing the file that held the change under verification, where
  the ordinary `git checkout --` revert would have destroyed it.*
- **A check's assertion must describe the state the fix produces, never the mechanism the fix
  removes.** This is the second member of the same family as the `enact`-evidence rule above — a
  check that cannot pass, rather than one that passes too easily — and it fails for a different
  reason: not timing, but direction. A check written against the defect's own machinery is
  unfailable in the right direction, because the fix's whole purpose is that the machinery is gone,
  so nothing that ships can satisfy the assertion as worded. What happens next is worse than a
  `FAIL`: the criterion gets quietly restated as something satisfiable, in the verifier's brief,
  after the `plan` gate has closed on the original wording. *A check once demanded that a `-Detail`
  value containing embedded double quotes "reaches `gh` as one intact argument", where the fix's
  entire point was that the value stops travelling as an argument and travels in an `--input` file
  instead. It was made decidable only by a clarifying note added to the verifier's brief, which the
  verifier flagged unprompted as load-bearing rather than decorative.*
- **Two checks in one phase must be satisfiable together, and the `plan` gate tests that by naming
  one artifact that would satisfy both.** The third member of that family: each check is defensible
  alone and the pair is impossible, so whichever runs second cannot pass however well the work is
  done. Naming the artifact is the test because it is answerable at planning time, before anything
  is built — if no single deliverable can be described that satisfies both, one of them is wrong
  now, not at `verify`. **Distinct from the deliberate pairing the control rule above endorses**,
  where two checks demand opposite verdicts from the same command over *different* inputs and are both
  satisfiable; the failure here is that no input satisfies both. *One check once required a template
  at `HEAD` to be refused by a new contract, while another required every existing verify report
  across three projects to keep conforming. The template used the same shape as the reports, so the
  only rule that refused the template refused some of the delivered reports too. A decision dropped
  the first check's limb mid-phase, after the check list had already been approved.*
- **A completeness check over a population defined by a judgement and graded by a fresh reader is
  written closed-world, or the `plan` gate names how it could reach PASS.** The fourth member of that
  family: where membership is a reading call, "nothing meeting this definition is left unlisted" has
  no point at which an independent reader must stop, so the check fails however good the work is and
  the failures read as progress. Closed-world means every member of a named list is answered, and a
  miss an independent reader finds is recorded and answered rather than failed. **Tightening the
  definition does not repair it**, because the shape is the defect. *A check once asked for every
  site instructing a reader how to treat a recorded decision and failed all its verify rounds. The
  re-plan wrote a tighter definition and kept the shape, and failed all its rounds too. Both phases
  were abandoned at the cap. The closed-world version - every site in a given list answered with a
  block to ship or a no-change reason - passed.*
- **A check whose scope spans more than one file — whether it names them, points at a directory or
  globs — is run against each of them before the `plan` gate is recorded, and its per-file counts
  are written into the check.** A non-zero total is satisfiable by one file: it proves the pattern
  reached *somewhere* and says nothing about the files it never touched, and those are invisible in
  precisely the way a passing check is supposed to rule out. **A directory or a glob hides this
  better than a list does**, because there is no enumeration on the page for the number to be read
  against — so the scope that most needs the per-file count is the one least likely to prompt it.
  Where a file returns zero, decide at planning time whether the pattern is wrong or whether that
  file was never going to carry the text — either can be the right answer, and neither survives
  being folded into one combined number. **Distinct from the procedure rule above**, which asks
  whether the procedure could detect the violation at all; this one asks where the procedure was
  pointed. A check can satisfy that rule completely and still never look at two of the three files it
  covers. *A check once ran a keyword search across `plugins/` and required 0 hits at `HEAD` and more
  than 0 in the working tree. The change was about three files, a skill and two brief templates, and
  the line it added to the templates matched none of the check's alternations. The verifier measured
  hits only in the skill and 0 at `HEAD` - exactly the result the check demanded - and noted that the
  check would have passed on a change that left both templates untouched. One number for `plugins/`
  could not show that two of the three files returned zero.*
- **When a phase ships prose that asserts facts about the change, one check covers those assertions,
  and it names which ones.** The numbered checks are written against the deliverable; the text that
  travels with it — a delivery record, a cover letter, a filed summary, a release note — makes
  factual claims that no check reaches, so it is the one part of a phase that ships unverified by
  construction. Name the claims rather than the document: "the entry is accurate" cannot fail,
  whereas "each of the three quantities in the entry matches the output of the command cited beside
  it" can. *One phase ran fresh-verifier rounds until its cap. Every round passed every check, and
  every round still found a factual defect in the prose that phase shipped - a different one each
  time, from a misattributed citation to one quantity given as two different numbers. Each round
  before the last consumed an iteration, so the entire cap was spent on findings no check produced,
  and what the last round found could not be re-verified at all: with the cap gone it was surfaced to the
  operator rather than fixed and re-run. The prose in question there was a changelog entry; in a
  project that ships no releases it is whatever that phase hands over, which is why the obligation
  above names the kind of text and not the file.*
- **A check over a document's factual claims is scoped by the CLASS of claim it covers — never by
  what the author chose to quote, mark or list — and its instrument extracts the subject from the
  published artifact rather than from a list kept beside it.** The rule above obliges one check to
  cover a phase's outbound prose and to name which claims; **naming the class is how that naming is
  done**, because a class can be enumerated from the document at the moment the check runs, whereas
  a frozen list of instances drifts away from what was actually published. A scope the author
  controls measures the marked fraction and is blind by construction to everything else, so the
  check passes while the document is wrong — and both failure modes sit outside what it compared:
  prose the author never marked, and list entries that no longer match the text as published. State
  the class — "every sentence asserting shipped behaviour" — and have the instrument pull its
  subject out of the published document, so the checked set and the published set cannot diverge.
  *A check once required every sentence a document quoted as shipped text to match the committed
  file, and was implemented over spans the author wrapped in markers. It was recorded PASS in every
  one of that phase's verify rounds - the last matching every marked span, with its controls
  returning zero - while the document was wrong in all of them. Every defect was found by a fresh
  reader and none by any check row, and one of them sat INSIDE a marked span, escaping because the
  hand-maintained list beside the document had been trimmed to a form that did match.*

### The check set covers what the row demands

The rules above govern whether an individual check can fail. None of them asks whether the checks,
taken together, cover what the phase was asked to **produce** — and a phase can pass every numbered
check while its record omits half of what its own row demanded.

**Enumerate what the phase's row demands the phase produce, and map each demand to the check that
decides it.** The enumeration comes from the row's own sentences: its line in the section 4 phase
table together with the whole of its section 5 block, not only the block's opening description,
because a block often states a demand below its opening. Where the two state
different demands, that difference is itself a finding. It never comes from the shape of the
deliverable you expect: that shape is the author's output, and a check set derived from the author's
output cannot find what the author omitted. Write the mapping into the phase's section 5 block, in
the slot `SPEC_TEMPLATE.md` carries for it.

Four rules about that table:

- **A demand with no check is written in as `uncovered`, with one line saying why that is
  acceptable.** It is never deleted from the list and never folded into a neighbouring row. Making
  it visible on the page is the whole of what this buys — whether it is acceptable is a separate
  judgement, and one a reader can then argue with.
- **A constraint is not a requirement, on either side of the table.** "Edits no file under
  `plugins/`", "touches only these files", "ships no release chore" — these bound how the phase
  works rather than name something it produces. Leave them out of the enumeration, and record the
  check that enforces one as covering no requirement. Both halves are needed and for one reason:
  count the constraint as a requirement and it reads as uncovered, or let its check cover the
  nearest real requirement and the covered count is inflated by a check that was never about the
  deliverable. Either way the same row yields a different number depending on who read it.
- **The count is over what the row demands, never over the checks.** More demands than checks is an
  ordinary shape, and every check being mapped to something is not evidence that every demand is
  covered.
- **Enumerate at the grain the row itself uses.** Where the row introduces a list — after a colon,
  or as a run of comma-separated items — each item is one demand, and the sentence introducing them
  is not a demand of its own. A row reading "design the guard: what detects it, what each verb does,
  what the message says" demands three things and not one. **Grain is the dimension on which two
  careful readers of the same row still diverge**, and collapsing a list into its introduction is
  how a row demanding six answers is enumerated as demanding one — after which every demand is
  covered, the table reads clean, and nothing has been checked. Where the grain is genuinely
  arguable, take the finer reading: an over-enumerated table costs a row saying why something needs
  no check of its own, and an under-enumerated one hides exactly what this rule exists to surface.

*One phase's row demanded an enumeration and a set of design answers, and was given five checks, one
of which was a constraint on how the phase worked rather than on what it produced. Several of the
demanded answers were covered by nothing, and a record omitting them would have passed every
numbered check while handing the implementing phase a foundation wrong in exactly the places its own
guard and its whole test suite were then built on. Found by that phase's fresh plan reviewer, and by
no check.*

### Run order is declared, never inferred

State it explicitly in the phase table, and say why when it is not numeric order. The wrapper
enforces uniqueness per workstream (exit 92).

## Step 5 — register the phases

Show the rows and have the human confirm **once**, then:

```
keel-state.ps1 add-phase -Phase W<n>.<p> -Scope "<scope>" -Actor <agent|self|external> -RunOrder <int> `
    [-Repos <csv>] [-Due <yyyy-MM-dd>] [-PromptPath plan/prompts/W<n>.<p>-prompt.md]
```

**Never auto-apply.** A spec is markdown written for people; a mis-parse landing in the state file
is worse than one that does not, because the state file outranks the conversation.

`-Due` only where a date is real. A due date invented to look diligent trains you to ignore the
`OVERDUE:` line, and that line has to stay meaningful.

## Step 6 — the next phase's prompt, and only that one

**Only after the human approves the spec.** Write **exactly one** phase prompt — the **next runnable
phase's**, by the declared run order — from `templates/PHASE_PROMPT_TEMPLATE.md`, to
`plan/prompts/W<n>.<p>-prompt.md`.

**Every later phase's prompt is written by `keel-run-phase` at its `record` gate**, at the moment the
phase before it delivers, informed by what that phase actually found, and registered onto its phase
with `keel-state.ps1 revise-phase -PromptPath`. That is the whole of the just-in-time flow, and this
step's only job is to stop before it.

**Why one.** In one measured workstream six prompts were written at planning time; after exactly
**one** phase delivered, **five** of the six had been rewritten or abandoned and two more added. The single prompt that was never touched survived because it had already been consumed before
anything could invalidate it. A brief written before its inputs exist necessarily asserts things
about artifacts that do not yet exist.

**This changes nothing about the spec, and that separation is the point.** The phase table, the
declared run order and every numbered `W<n>.<p>-C<n>` check stay whole and up front, exactly as Step
4 requires. The falsifiability argument — checks written after seeing results cannot fail — is an
argument about **checks**, which live in the spec. It is not an argument about **prompts**, which are
operational briefs for a fresh session and commit nobody to anything.

**An amendment the operator makes to a decision, carrying the checks written from it, is not a check
rewritten after seeing results:** its trigger is the operator's changed decision, dated and
attributed - see
"An earlier decision is a tradeoff to show, not a rule to enforce" in `keel-orchestrator/SKILL.md`.

A phase prompt is written for a **fresh session that has never seen this conversation**. It names
paths, commands and checks. It never says "as we discussed".

**In amend mode the same rule holds:** write the next runnable phase's prompt if it does not already
have one, and no others. A re-plan that regenerated every downstream prompt would be recreating the
population this step exists to keep at one.

**The spec and the prompt stale the document index — rebuild it in the same commit.** Both land
under `plan/`, which `keel-index.ps1` scans, so `reference/INDEX.md` is wrong until it is rebuilt —
and in a project whose commit gate checks the index, the commit is refused until you do (keel's own
does, in `scripts/check-suite-docs.ps1`). The order and the staging rule are stated once in
`keel-orchestrator`'s "Ending a session" section — follow it there; the command is under
"Rebuilding the index" in `keel-project-context`. Amend mode too: an
amended spec is a document write like any other.

## Amend mode

When a workstream in flight turns out to be shaped wrong, you are dispatched in amend mode. **This
is normal and expected** — a session opening phase N reviewing what N-1 produced and concluding the
rest is wrong is the review working.

- **Append** a dated Decision row saying what changed, why, and who decided it.
- **Revise** the phase table and the declared run order.
- **Never rewrite** a delivered phase's plan text or its delivery record. The plan as written is the
  record of what was intended, and the difference is the useful part.
- **A delivered phase cannot be revised** (exit 90). If delivered work needs redoing, that is a
  **new phase** whose scope says what it supersedes. A description that is simply wrong takes
  `revise-phase -Correction`, a dated note beside the frozen scope.

**What you are amending against is the spec's own section 1, which is a dated planning snapshot** —
governed by **"Material keel produced is re-measured before you act on it"** in
`keel-orchestrator/SKILL.md`.

**Amend mode ends at the amended spec. It does not then run a phase.** Hand back.

One decision amended by the operator inside a running phase is not amend mode: the running session
appends that row and carries on - see "An earlier decision is a tradeoff to show, not a rule to
enforce" in `keel-orchestrator/SKILL.md`.

**Before you hand back, write the handoff** — see "Ending a session — write the handoff before you hand back" in `keel-orchestrator/SKILL.md`.

### The judgement amend mode exists for

The ask is usually *"do it properly, no shortcuts, no tech debt — without over-engineering."* Both
halves are real. Be concrete about which this is:

- *"Phase 1 hard-coded the account mapping; extracting it now costs one phase and stops three
  future phases copying it"* — debt repayment.
- *"While we are here, let us make it generic over every bank format"* — over-engineering.

**Name the call and let the human correct it.** That is what the amended Decision row is for.

## Must not

- **Plan without grounding.** No spec ships whose §1 is recalled rather than measured.
- **Generate the phase prompt before the human approves the spec** — or generate more than the one.
- **Write a phase with no actor**, or default everything to `agent`.
- **Write a check that cannot fail.** "Looks right" is not a check.
- **Infer run order from phase numbers.**
- **Edit a Decision row.** Append.
- **Implement anything.** This skill ends at the one prompt.
- **Plan a child workstream of another workstream.** That is an epic (charter P17).
