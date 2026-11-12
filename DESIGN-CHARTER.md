# Design charter — keel

**This file is read *live*, in full, before any change to `plugins/**`.** Not summarised, not
recalled from a previous session, not quoted from a skill that paraphrases it. A repo-local
`PreToolUse` gate requires a marker proving it was read this session. That is the whole of the
governance process here: keel has one maintainer, who proposes and reviews every change.

Each principle carries a **Rule**, a **Why** (the concrete failure that produced it), and a
**Violation looks like** so it can be checked rather than agreed with.

Principles are numbered and never renumbered. A retired principle keeps its number and is marked
RETIRED with a date and a reason.

## Provenance, stated honestly

**P1–P16 are inherited from the charter of an earlier workflow built for one software estate**,
adapted from one estate to many projects. Their "Why" sections cite failures measured in that estate
between 2026-07 and 2026-08. Those failures are real and dated, but they happened *there*, not in
keel. Keel has met failures of its own since, and this charter records some of them where they
changed a principle, but not every one; read the principles as well-supported priors rather than as
something keel has earned.

**P17–P26 are new.** They cover what that estate never had to model: many projects instead of one, work
performed by someone other than an agent, time, irreversibility, and a tooling estate that its own
consumers can report against. They were written as predictions, with no measured failure behind
them. When one turns out to be wrong, amend it here with the date and the evidence that disproved
it, and do not quietly stop following it.

**Keel itself grew out of a manual planning loop**, run by hand across chat and Claude Code sessions
before keel existed, and it automates that loop.

### External provenance — what keel is a variant of

**Added 2026-08-21, from a report that keel recorded where it came from but never what it
resembled.** Everything above this heading records keel's provenance from inside: the workflow it
was adapted from and the loop it automates. This records the outside, in the same form and to the
same standard.

**The category, named.** Keel is a variant of the **stage-gate (phase-gate) process** — the
product-development family Robert G. Cooper named in the late 1980s, in which work moves through
stages separated by decision points that consume the previous stage's deliverables and return a
verdict. Stage-Gate International defines a gate as "an explicit decision point where the business
must choose whether and how to continue investing", assembled from gate deliverables ("defined
outputs from the previous Stage"), gate criteria ("both project readiness and project value") and
gate outputs ("a clear decision and an agreed plan. Typical outcomes are Go, Kill, Hold, or
Recycle"). Keel's eight-gate phase is that shape, with two substitutions that are the whole of what
makes it a variant rather than an instance:

- **Its criteria are evidential, not commercial.** Cooper's criteria cover readiness *and* value;
  keel's cover readiness only — the artifact exists, the artifact conforms, the verdict was recorded
  (P3). **No phase gate can return Kill.** That is precisely the gap two of keel's early reports
  described, and naming the category is what makes it legible as a missing gate output rather than
  as a vague absence of judgement. Row 1 of the table below is where keel took it up: once per
  workstream, at the close step, never per phase.
- **Its gatekeepers do not exist.** Cooper's gates are attended by "senior managers from different
  functional areas, who own/control the resources required by the project leader and team". In
  every keel project the gates are attended by the person running keel and by fresh subagents, and
  nobody above them. The third parties a project may involve (P18) act in a phase; they do not own
  its resources or sit at its gates. **Every practice in the table below that presumes a second
  party at the gate fails here for that single reason**, and each such row
  says so rather than inventing a fresh objection.

**The machinery is a second and separate category: a durable-execution workflow engine.** Temporal's
documentation describes an Event History that is "a complete and durable log of everything that has
happened in the lifecycle of a Workflow Execution", from which a worker "replays the Workflow code
from the beginning" after a crash, skipping what already completed. Keel's `state.json` is that log,
`keel-state.ps1` is its only writer, a fresh session per phase is the replay, and P3's "the state
file outranks the conversation" is the replay rule written as prose. **What keel cannot have is the
precondition.** Temporal requires determinism — "the same Commands in the same sequence given the
same input" — and an LLM session is not deterministic. Keel substitutes **conformance for
determinism**: unable to re-derive the same work, it gates instead on an artifact that exists,
conforms, and carries a recorded verdict. That substitution is the most load-bearing design fact
about keel and until this section it was written down nowhere.

**What keel is not a variant of, stated so the next proposer does not reach for it.** It is not a
project-management methodology in the PRINCE2 or PMBOK sense. Those are built on defined roles, a
board, delegated tolerance and a business case; keel has none of the four, and the table below is
mostly the consequence of that.

**The three named precedents, adjudicated.** An earlier planning session asserted, from its own
recall with no citation and no measurement, that continued-justification-re-tested-at-a-stage-boundary
is settled prior art, naming three precedents. The plan written after it carried that in as a
hypothesis to check, not as a finding to inherit. Checked against sources read on 2026-08-21:

- **PRINCE2 continued business justification.** Real, and the wording is close: justification is
  "regularly reviewed throughout the project's lifecycle, for example, at the end of each stage",
  and if it fails "it could result in the project being halted". **Right about the shape, wrong
  about the instrument.** The instrument is a Business Case document, updated at each stage boundary
  and assessed by a Project Board. Keel has no board, no executive and no business case, so what
  transfers is the *timing* and not the mechanism.
- **Stage-gate kill-or-continue.** Real: "Go, Kill, Hold, or Recycle" is the literal list of gate
  outputs. **The strongest of the three, and the right one** — not because it is closest in wording
  but because keel is already a variant of this family, as the paragraphs above establish. A missing
  gate output in a system you already are is a far more precise finding than an analogy.
- **Lean pivot-or-persevere.** Real, and **the weakest fit of the three, which the asserting session
  did not notice.** The decision runs on validated learning measured by innovation accounting, which
  "focuses on learning milestones" rather than on revenue or market share — presupposing a stream of
  outcome data from users. A keel project is judged by the one person running it, and keel projects
  include a tax filing and a house sale, which generate no such stream. The cadence without the data would be ceremony,
  which P13 records as the thing that gets routed around at 11pm, taking the load-bearing gates with
  it.

**Verdict on the asserting session: it named three real precedents and was still wrong in the exact
way the report behind this section predicted.** All three exist and all three re-test continuation at a boundary, so nothing
was fabricated. What was absent was any check of whether their preconditions hold *here* — and two
of the three fail that check against facts this section already states about keel. A claim that is
true of the field and false of the reader is what an uncited recall produces, and stated as a
finding it would have shipped.

**How to read the table.** It is a record of decisions, not a shopping list. Under P12 the default
answer to a new thing is no, under P13 enforcement escalates only after a cited failure, and under
P14 every skill description taxes every session; a review returning twenty things to take up would
make keel measurably worse. Each row carries exactly one verdict.

| # | Practice, and where it comes from | Verdict | Why — and where it lands |
|---|---|---|---|
| 1 | **Stage-gate:** a decision point whose outputs include Kill and Hold, not only pass (Cooper) | ADOPTED | The one real gap the category comparison exposes: no phase gate can stop the work. Taken at **exactly one point per workstream**, at the close step that already exists — never per phase, because a value question asked eight times per workstream is the ceremony P13 predicts will be routed around. |
| 2 | **PRINCE2:** a Business Case re-tested at every stage boundary and assessed by a Project Board | REJECTED | The instrument presumes a board and an executive. Keel's gates are attended by the person running keel, with nobody above them. Copied here it reduces to asking oneself in writing whether one still wants one's own idea. The *timing* survives, in row 1. |
| 3 | **PRINCE2:** manage by exception — escalate to the level above when a tolerance is forecast to breach | ADOPTED | Already built, and never credited to a precedent until now: exit code 2 `CAP-REACHED`, the `escalated` stage, and `status` printing `STOP: N phase(s) escalated`. Ships no change. The other half — numeric tolerances on time, cost and benefit — is not taken: P12, and there is no level above to escalate to. |
| 4 | **PRINCE2 / MSP:** a post-project benefits review, planned in its own document and owned after closure by corporate or programme management | REJECTED | P12 — a new process, with a new artifact and a named owner that does not exist here, where keel instead deepened the close step it already runs. The question it asks is worth asking; the apparatus around it is not. |
| 5 | **Lean Startup:** pivot-or-persevere, decided by validated learning under innovation accounting | REJECTED | Requires a stream of outcome data from users. A keel project is judged by the one person running it, and keel projects include filings and property sales that produce none. Taking the cadence without the data is P13's ceremony exactly. |
| 6 | **Estimation:** story points, velocity, weighted numeric scoring of value | REJECTED | A new scoring mechanism where nothing asked for one (P12), and ruled out by the report that raised the gap, in its own words: the gap is the absence of a moment where the plan is re-judged, not the absence of numbers. A tax filing and a house sale would be actively harmed by story points. |
| 7 | **Gawande:** a do-confirm checklist held to five-to-nine items at one defined pause point | REJECTED | **Stated with its cost, because this section's own addition of question 11 takes the "Applying this" list to eleven, past that bound.** The bound is derived from working memory under time pressure in an operating theatre; keel's list is answered in writing, at a pause point already defined ("when proposing a change to `plugins/**`"), by a reader who can re-read it. Recorded as a live cost rather than dismissed: if a session is ever measured skipping the list because it is long, **this row is the cited failure P13 requires** to cut it back. |
| 8 | **Scrum:** a Definition of Done an increment must meet or it "cannot be released or even presented" | ADOPTED | Already built, and stricter: P3's three facts — artifact exists, artifact conforms, verdict recorded — plus a wrapper that refuses non-conformance at exit 96 rather than relying on a team convention. Ships no change. Recorded so the next proposer sees the precedent and sees that keel's version is the harder one. |
| 9 | **Nygard:** decision records superseded rather than edited | ADOPTED | Already built, convergently: every workstream spec's Decisions table, and this charter's own rule that principles "are numbered and never renumbered" and a retired one "keeps its number and is marked RETIRED with a date and a reason". Ships no change. |
| 10 | **Google SRE:** a postmortem triggered by a defined incident threshold, with a named owner per postmortem | REJECTED | Keel closes on a schedule — every workstream — not on a threshold, and has no SLO to breach. The blameless half is already keel's practice: a signal cites a moment and evidence, never a person (P25). Adding a trigger threshold would be enforcement escalated with no cited failure (P13). |
| 11 | **Amazon:** the weight of the process is set by whether the door is one-way | ADOPTED | The external precedent for P6's amendment of 2026-08-21. Bezos, 2015: "Many decisions are reversible, two-way doors. Those decisions can use a light-weight process", and the named failure is applying the heavy process to Type 2 decisions, which is what one measured keel session showed: six confirmations, of which three decided nothing. Needed no new mechanism: P21 already collected `-Reversible` and `-Observable` before the act, and the amendment is what reads them. |

**What this review changes on its own: nothing.** Eleven practices, one verdict each. Six carry a
no. Of the five that carry a yes, **three describe something keel already does** and ship no change at
all — they are here so the next proposer finds the precedent instead of re-deriving it — and the
remaining two were changes keel had already planned: P6's amendment (row 11) and the value question
at the close step (row 1). **No skill, no plugin,
no wrapper verb, no state field and no gate is added by this review.** Under P16 that is the
expected result and not a thin one.

**How much weight these sources bear, stated rather than implied.** Cooper's gate definition,
PRINCE2's principles and practices, the Scrum Guide, Google's SRE book, Temporal's documentation and
Amazon's published copy of the 2015 shareholder letter were each read at their own sites on
2026-08-21. **The Lean Startup and Checklist Manifesto rows rest on secondary summaries of those
books, not on the primary texts** — no primary source was reachable — and that is marked here rather
than smoothed over.

**This section is a snapshot with a date on it, exactly like the one above it.** When one of these
verdicts is overturned, amend it here with the date and the evidence, and do not quietly stop
following it.

---

## A. Control flow

### P1 — One funnel, one dispatcher

**Rule.** `using-keel` is the only entry point. `keel-orchestrator` is the only skill that dispatches
stages. `keel-plan-project`, `keel-plan-epic`, `keel-plan-workstream`, `keel-run-phase` and
`keel-close-workstream` are never session entry points, even when the user's words match them
exactly ("plan this", "implement phase 3", "close it out").

**Why.** A stage reached directly is a stage reached without its gates, without the project's state,
and without knowing whether earlier work already answered the question. The earlier workflow's reference
implementation names skipped discovery as *the most common failure mode of the workflow* — the one
thing it warns about before anything else.

**Violation looks like.** A skill description that would plausibly win on a bare verb. A stage skill
whose body works when invoked cold. Any path into implementation that does not pass through
`keel-state.ps1 status`.

---

### P2 — One pipeline; type and actor select data, never steps

**Rule.** Every phase runs the same eight stages in the same order. The phase's **actor**
(`agent` / `self` / `external`) and the project's **type** select which evidence a check accepts and
which recipes apply. Neither may add, remove, or reorder a stage.

**Why.** A tax filing's checks ("the return was accepted, confirmation number recorded") are still
artifact-plus-verdict — the *shape* is identical to a typecheck, only the recipe differs. The moment
actor forks the pipeline there are three pipelines to keep correct, two of which are exercised
rarely enough that their bugs surface at the worst time.

**Violation looks like.** A conditional in the orchestrator keyed on actor that changes the stage
list. A gate that exists only for `agent`. An actor recipe containing the word "skip".

---

### P3 — A gate is three facts, and the file outranks the conversation

**Rule.** A gate is satisfied only when **the artifact exists**, **the artifact conforms** to its
content contract, and **the verdict was recorded** through `keel-state.ps1 record-verdict`. All
three. When the state file and the conversation disagree, the state file is right.

**Why.** Conversation memory does not survive compaction or a new session, and keel runs one fresh
session per phase by design, so the conversation is *guaranteed* to be gone. The middle fact exists
because "I ran the checks" is exactly the kind of claim that turns out to mean "I reasoned about the
checks".

**Why the third fact is separate from the first.** An artifact can exist and be empty, or exist and
be the previous phase's. Recording is a deliberate act with a timestamp.

**Violation looks like.** `record-verdict` called before the artifact is written. A skill that says
"the check passed" without naming the file. Any code path that reads gate status from anywhere but
the wrapper.

---

### P4 — Caps and refusals are exit codes, not judgement

**Rule.** Anything that must always hold is enforced by the wrapper returning a nonzero exit code,
never by prose asking a model to remember. Loop cap → exit 2. Undeclared phase → exit 94. Enact
without a reversibility answer → exit 95. Non-conforming artifact → exit 96. Signal without evidence
→ exit 97.

**Why.** Prose-only enforcement of an always-rule is a known failure mode. A model asked to count its
own retries will, under pressure, decide this attempt is different.

**Violation looks like.** A skill that says "do not loop more than three times". A wrapper verb that
warns where it should refuse. Second-guessing an exit code because the situation "obviously" differs.

---

### P5 — Fresh subagents, self-contained briefs

**Rule.** Independent verification and factual investigation run in **fresh** subagents whose brief
is complete on its own: paths, commands, scope, required output format, and the prohibition *do NOT
load or invoke any `keel-*` skill*. The agent that made a change never verifies it in its own
context.

**Why.** The author's transcript is full of the reasoning that produced the change, including the
rationalisations. A verifier that inherits them inherits the blind spot. Separately, this is the
context-management mechanism the whole suite exists for: the grep, the false starts and the dead
ends happen in the child's context and die there.

**Violation looks like.** A brief that names a skill instead of a path. A verifier prompt containing
"as we discussed". A subagent that returns its whole investigation rather than a summary and a path.

---

### P6 — Nothing outward-facing without an exact preview

**Rule.** Every tracker write, every commit, every push, every enactment, and every edit to a file
outside the current project is previewed in its exact final form and waits for explicit
confirmation. No silent writes, ever. Uncertainty defaults to the *inaction*: SKIP, not CREATE.

**Why.** These are the actions with no undo. In keel the stakes are higher than in a code estate: an
enacted phase may be a filed tax return, a signed agreement, or a broadcast transaction.

**Amended 2026-08-21, from a measured session in which half the confirmations decided nothing.** The rule above says *every*, and
*every* is now qualified in one direction only. An act that is **reversible**, **observable**, and
**inside a change set the human already approved** at the `plan` and `human` gates is **performed
and reported** rather than previewed and confirmed a second time. An act whose declared
`-Reversible` answer is `none` is previewed and confirmed exactly as before — no exception, no
pre-authorisation — and that is the class this principle was written for. The convention is stated
once, in `keel-orchestrator`'s section "Whether to ask, or to act and report — reversibility
decides"; this clause is the charter permitting it.

**Why, and why it is a widening.** One measured keel session had the human confirm six times, and
three of those confirmations decided nothing; by the sixth they opted out in writing, mid-session. P13's
**Why** predicts precisely that — ceremony is routed around at 11pm before a deadline, "taking the
gates that *were* load-bearing with it" — so a P6 that gates a `git commit` like a broadcast
transaction was spending the operator's attention where it bought nothing, and debasing the
confirmations that buy everything. The external precedent is row 11 of the practice table above:
Amazon's two-way door, whose named failure is applying the heavy process to the reversible decision.
Under P24 this **loosens** and therefore strands no project in flight. Under P12 it adds no verb, no
gate and no skill — two answers P21 already collects simply start being read.

**What is unchanged.** The exact-preview requirement itself, in full, for everything irreversible: a
preview that summarises is still not a preview, wherever a preview is owed. Uncertainty still
defaults to inaction — and uncertainty about which class an act falls into resolves to `none`, which
asks. A project that wants the unamended rule back sets `"confirmEveryAct": true` in its
`keel.json`; absent means the amendment applies. That setting is honoured by skill prose and by
nothing else, which is stated here rather than left to be discovered: the `human` gate is
deliberately artifact-free and `enact` is recorded after the act, so no exit code can detect a
confirmation that did not happen. It is a convention, and P4 is the reason that is said out loud.

**Violation looks like.** "I'll create these and you can delete any that are wrong." A preview that
summarises rather than shows the literal text. A confirmation inferred from an earlier, broader yes.
Treating the amendment above as covering an act that is irreversible, unobservable, or outside what
was approved — three conditions, all required.

---

## B. Knowledge

### P7 — Measure, don't assert; and prove the instrument

**Rule.** Any claim about live state — a file's contents, a board's contents, a deployed commit, a
balance, what a document says — is re-measured at the moment it matters. Every claim of **absence**
carries a positive control: a second query proving the instrument would have found the thing had it
been there.

**Why.** In the earlier estate, one workstream logged twenty numbered planning failures in nine
days, and nineteen were this. That estate has a family of measured cases where a zero was a lie: `findstr /S` returning
nothing because it never searched; `grep -c $'\r'` returning a plausible non-zero for a pure-LF
file; function-definition line-filtering producing three false absence conclusions against one RPC.

**Keel's own first instance, 2026-08-20.** A sweep for a hardcoded path reported zero
occurrences under `plugins/` and zero in every `.json`, with a positive control attached. The
control proved the grep had *descended into* `plugins/`; it did not prove the *pattern* would
match. Two occurrences were present the whole time: one JSON-escaped as `C:\\Users\\...`, which a
single-backslash pattern cannot see, and one under a sibling directory the pattern never covered.
The control was genuine, the conclusion was false, and it read as rigour.

**Violation looks like.** A number quoted from a document. "I grepped: it's absent" with no control.
A doc read where a query was available. A control that proves the search *ran* where what was
needed is a control proving the *pattern* would have matched.

---

### P8 — Anchors, never line numbers

**Rule.** A pointer from one place to another — comment to code, doc to doc, brief to file — cites a
symbol name, a unique string, or a heading. Never a line number. A line number is acceptable only in
a *dated one-off measurement*, where the date tells the reader it is a snapshot.

**Why.** Three citations in the earlier estate, each correct when written, all rotted within three
days; every one was found by accident rather than by anything failing.

**Violation looks like.** `see foo.ts:412`. A generated index storing line offsets. Any standing
pointer that a single insertion above it would break.

---

### P9 — Slow knowledge in files, fast knowledge from disk

**Rule.** Reference files hold only *slow* knowledge: principles, conventions, placement rules,
decisions. Anything *fast* — what skills exist, what a project's plan currently says, what is on the
board, which projects exist — is derived live at use time and never cached in a skill.

**Why.** A cached inventory is a second authority that rots silently, and the rot is invisible
precisely because the cache looks authoritative.

**Violation looks like.** A skill listing the other skills. A reference file restating a project
plan's current contents. Any table in `plugins/**` that would need editing because a project changed.

---

### P10 — One authority per fact

**Rule.** Every fact has exactly one home. Other places point at it; they do not restate it. When two
places disagree, that disagreement is itself the finding and is surfaced, not resolved in favour of
whichever was read most recently.

**In keel specifically:** the project's files are the authority for the plan. Any tracker — Trello,
Jira, GitHub Projects — is a **projection** of them and is never read back as truth.

**Why.** The earlier estate hit this repeatedly and expensively: three competing repo inventories, one figure in
three documents, a migration file that disagreed with the applied function body. Each was caught by
accident.

**Violation looks like.** Copying a table "for convenience". Reading a card's description to decide
what a phase's scope is. Two files that must be edited together with nothing enforcing it.

---

### P11 — A generated artifact must be mechanically checkable, or it does not ship

**Rule.** Anything generated (the README inventory, any doc index, the architecture page) carries a
hash or equivalent, has a `gen-*` script that rebuilds it and a `check-*` script that detects drift,
and is never hand-edited. If drift cannot be detected mechanically, the artifact is not built.

**Why.** The suite's whole purpose is to stop stale assertions. A stale generated index inside the
grounding router would make the tool built to prevent the failure into its newest instance of it —
and a *more* trusted one, because it looks systematic.

**Violation looks like.** A hand-maintained list of projects. A generated file with no checker. A
checker that is not wired to anything.

---

## C. Growth

### P12 — The default answer to a new thing is no

**Rule.** New plugin, new skill, new script, new state field, new node role: default REJECT. The
suite grows by deepening what exists. Ask first "which existing thing absorbs this", and only if
nothing can, ask where a new thing goes. Enthusiasm is not fit.

**Why.** Every skill's description is always-on in every session, competing for routing attention
with every other. The marginal skill makes all the others slightly worse at firing. The earlier workflow's
reference suite reached ~30 skills serving a team and three products; keel has one maintainer, and
each installed copy serves the one person running it.

**Worked example.** Reviewing signals looked like it needed a `keel-review-signals` skill. It did
not: keel is itself a keel project, so a signal is triaged by the planner that already exists.

**Violation looks like.** A skill that is one branch of an existing skill. A new plugin justified by
tidiness. A script that wraps one command.

---

### P13 — Enforcement escalates only after a real failure, cited

**Rule.** The ladder is: SessionStart nudge → skill prose → wrapper exit code → `PreToolUse` block. A
rule moves up one rung only after it has actually failed at its current rung, with the failure cited
by date and project.

**Why.** Hardening a gate that has never leaked is how a small suite acquires ceremony, and ceremony
is routed around at 11pm before a deadline — taking the gates that *were* load-bearing with it.

**Acknowledged tension.** Keel v1 shipped at full parity with that earlier workflow, which means it
started partway up the ladder for rules keel had never seen fail. That was a deliberate exception,
recorded when keel was built: every mechanism copied had failed at least once in the earlier estate,
so none of it was hypothetical. It is not a licence to add *new* enforcement on the same reasoning.

**Violation looks like.** A new hard block whose justification is hypothetical. Three enforcement
mechanisms for one rule. Any "while we're here, let's also enforce".

---

### P14 — Plugin hooks tax every session; repo-local hooks tax one repo

**Rule.** A hook that enforces a rule about *this repo* ships as repo-local `.claude/settings.json`.
Only a rule that must hold in **any** session anywhere ships as a plugin hook, and those are capped
at two. Plugin hooks must be cheap, must fail open, and must be silent when there is nothing to say.

**Why.** Plugin hooks spawn a process in every installer's every session. Keel is installed globally
and its consumers are every project folder, so the tax is paid more often here than in the earlier estate.

**Violation looks like.** A third plugin hook. A plugin hook that fails closed when no phase is in
flight. A hook that prints on a clean run.

---

### P15 — State lives outside every git repo unless a project shares its progress; sensitive material always does

**Rule.** Pipeline state lives under `%USERPROFILE%\.keel\` and is written **only** through
`keel-state.ps1`. Sensitive source material and every artifact derived from it before redaction live
there too, under `quarantine\<project>\`. Neither is ever committed anywhere, and neither is ever
written by a direct file edit.

**Amended 2026-11-11, decided by the maintainer.** A project that declares shared progress in its
`keel.json` keeps its progress and gate records in its own repo, under `progress/`, one file per
item and per entry, each naming its author by a person id; they are still written only through
`keel-state.ps1` and never by a direct file edit, and they are committed with the project.
Sensitive material does not move with them: it stays under `quarantine\<project>\`, it is never
committed, and a project with quarantine on cannot declare shared progress. The reason given
below for state, "meaningless elsewhere and misleading if shared", holds for a project one person
runs; for a project two people run, state kept on one machine is what misleads the other.

**Why.** State is machine-local by nature — it records where a half-finished workstream got to, which
is meaningless elsewhere and misleading if shared. Sensitive material is a one-way door: git makes
deletion ineffective.

**Violation looks like.** An `Edit` on a `state.json`. A `.gitignore` narrowed to let one document
through. A redaction step that happens at render time rather than at extraction.

---

### P16 — Silence is a success

**Rule.** A close-out that proposes nothing is the *expected* outcome. A grounding pass that
concludes "nothing here contradicts the plan" is complete work. A clean SessionStart prints nothing.
Output is not evidence of value.

**Why.** The alternative is a suite that generates a finding every session to justify itself, which
trains the operator to skim, which is how the one real finding gets missed.

**Violation looks like.** A close-out that always finds five things. A hook that prints "all clear".
A verification report padded to look thorough.

---

## D. Structure — new in keel

### P17 — Depth is free; roles are not

**Rule.** Containment nests as deep as a project needs. The **roles** are a closed set —
`goal`, `epic`, `workstream`, `phase` — and the nesting rules are enforced by the wrapper: a phase is
always a leaf; a workstream contains only phases; an epic contains epics and workstreams; every epic
states in one line what it groups.

**Why.** Unbounded nesting with no closed role set means nothing can tell whether a node is
*runnable*, and two projects drift into shapes that cannot be compared or reported on together. The
constraint has to live somewhere; putting it on roles rather than on depth is what lets a two-level
tax project and a six-level platform project use the same tooling.

**Violation looks like.** A fifth role. A phase with children. A workstream nested in a workstream. An
epic whose "groups" line restates its title.

---

### P18 — The actor selects evidence, never steps

**Rule.** Every phase declares an actor: `agent` (Claude), `self` (you), or `external` (an
accountant, auditor, exchange, counsel). The actor determines which evidence a check accepts. It
never determines which gates run.

**Why.** This is P2 applied to the thing that most tempts a fork. The moment human-executed work gets
its own lighter pipeline there are two pipelines, and the one that runs rarely is where the bugs
hide — and in keel the rarely-run one is the one handling irreversible real-world acts.

**Violation looks like.** "Skip verify, I did this myself." A gate marked N/A because the actor was
not an agent. A check on a `self` phase with no artifact behind it.

---

### P19 — A wait names who, and when it is re-checked

**Rule.** A phase in `waiting` must record **who or what it waits on** and **the date it will be
re-checked**. The wrapper refuses the state without both.

**Why.** A wait with no review date is an abandoned phase wearing a status. Six weeks pass, the plan
still reads "in progress", and nothing in the system distinguishes "the auditor is working on it"
from "I forgot".

**Violation looks like.** `waiting` with `waitingOn` set to "them". A review date in the past that
nothing surfaces. Using `waiting` for work you simply have not started.

---

### P20 — The active project is derived, never stored

**Rule.** Which project a session is working on is resolved by walking up from the working directory
to the nearest `keel.json`. It is never stored in state, never cached, and never carried in a
conversation.

**Why.** A stored "current project" pointer is wrong the first time two windows are open, and wrong
*silently* — the second window writes its phase artifacts into the first project's state.

**Violation looks like.** A `currentProject` field anywhere. A skill that asks which project this is
rather than resolving it. Any wrapper verb that accepts a project name where it could derive one.

---

### P21 — Irreversibility is declared before the act, not discovered after

**Rule.** The `enact` gate requires `-Reversible none|partial|full` and `-Observable yes|no` before
the act, not after. An irreversible act whose outcome is currently unobservable holds until it can be
observed.

**Why.** Filing, signing, sending and broadcasting have no undo. The question has to be answered
while the answer can still change the decision; asked afterwards it is a postmortem, not a gate.

**Strengthened 2026-08-21, with P6's amendment.** These two answers stopped being a record and became a
decision: P6's amendment reads them to decide whether the human is asked at all. Declaring
reversibility before the act was always the rule; it now also determines the interaction, so an
answer given carelessly — or optimistically — buys silence rather than merely mis-describing the
record. Answer for the act in front of you, never from what a similar act was last time.

**Violation looks like.** A reversibility answer supplied to satisfy the wrapper after the act. "It's
probably reversible." An enact recorded DONE with `-Observable no` and no follow-up phase. An act
declared `partial` or `full` because that is the answer which avoids asking.

---

### P22 — Every goal is claimed, or explicitly unaddressed

**Rule.** Every goal is either linked from at least one workstream or carries the token
`UNADDRESSED`. Every workstream declares at least one goal. Coverage is reported, not felt.

**Why.** A goal nobody planned work against reads exactly like a goal that is going fine. This is the
whole reason goals are cross-cutting links rather than a containment level: linkage makes coverage a
query.

**Violation looks like.** A workstream with no goal. A goal that has silently had no work for the
life of a project. A coverage report that infers linkage from titles.

---

### P23 — Sensitive material never enters a tracked folder

**Rule.** Each project declares in `keel.json` whether it is a git repo and where its quarantine is.
Sensitive source material lives in `%USERPROFILE%\.keel\quarantine\<project>\`, outside every repo,
and redaction happens **at extraction** — so an unredacted fact cannot exist in a downstream
artifact, redacted or not.

**Why.** P15 made per-project, because keel spans projects whose blast radii differ: a public crypto
repo and a folder of tax slips cannot share one policy, and the weaker policy would win by default.

**Violation looks like.** A `.gitignore` as the only thing standing between a document and a commit.
Redaction applied when a report is rendered rather than when the fact is read. A quarantine path
inside a project folder.

---

### P24 — A keel change must not invalidate an in-flight project

**Rule.** Contracts widen freely. Tightening one — a stricter artifact contract, a new required
field, a narrower enum — ships with a migration and a cited failure, never on its own. Each project
records the keel version it was planned under, and `status` warns on drift.

**Why.** There is one keel and many projects, and nothing pins a project to the keel version it was
planned under. An installed copy moves when a release is cut on the `release` branch and the update
commands are run, and from the next session every project on that machine runs the new version
together. A clone used as a directory source, the way keel itself is developed, moves sooner: its
working tree *is* the load path, so an edit is live in every project's next session. A tightened
contract can strand a half-finished workstream in a project nobody was thinking about
when the change was made.

**Violation looks like.** A new required parameter with no default. An enum value removed. A contract
check added to a gate that already has recorded verdicts. "Existing projects can just re-run it."

---

### P25 — A project reports; it does not legislate

**Rule.** A project session never edits `plugins/**`. It files a **signal** through the wrapper,
citing project, phase and evidence. Promotion is decided in keel, with the other projects in view.
`unsafe` and `refusal` signals act at n=1; `gap` and `friction` wait for a second project or an
argued exception.

**Why.** The session filing the signal has a sample size of one, has not read this charter, and is
mid-way through unrelated work. The earlier workflow's close-out rule already establishes the harder half: a
finding with no citable moment is dropped. The evidence requirement is what keeps this a queue of
defects rather than a queue of wishes.

**Violation looks like.** A signal whose evidence is a paraphrase. A promotion made because the queue
had been sitting a while. A signal filed by hand with no phase behind it. Editing a `SKILL.md` from a
project folder.

---

### P26 — A signal crosses machines only as a report

**Rule.** Signals stay on the machine that filed them, even in a project that shares its progress
(P15), and leave it only as reports. They are filed
**locally first**, then pushed as **GitHub issues** on the repo each user chooses (with
`keel-state.ps1 signals-target`) by an explicit, preview-gated step; with no choice made it stays on
their machine. The fix travels the other way as a **pull request**, authored in keel by a session
that has read this charter.

**Evidence discipline is per project.** A project with `quarantine` on may file evidence **by
reference only** — a local path plus a short description, one line — never pasted content. The
wrapper refuses content from a quarantined project with exit 97; it does not warn.

**Why an issue and not a PR.** A PR is a proposal to change code. A signal is deliberately not a
change (P25): the session filing it has n=1 and has not read this charter. Letting a project session
open a PR would make it the author of the fix, from exactly the position the queue exists to
prevent. Issues in, PRs out — and GitHub allocating issue numbers also removes the collision two
machines would otherwise create by both allocating the same first signal id.

**Why local first.** A signal filed with no network must not be lost, and the wrapper must work
offline. The push is a separate, deliberate act with its own preview.

**Why this is a carve-out and not a hole in P15.** Per-machine pipeline state is machine-local
because it is meaningless elsewhere; shared progress is the project's own record and travels with
it. A signal is the opposite: it is only useful elsewhere. What must still never
cross is *content* from a quarantined project, which is why the evidence rule is an exit code rather
than a convention.

**Amended 2026-11-01, decided by the maintainer.** "Pushed as GitHub issues on the keel repo" no
longer holds once keel is public: every user's project details would be published. A signal now goes
where each user chooses, and with no choice made it stays on their machine. **In effect from
keel-workflow 0.68.0.** The rest of this principle stands.

**Amended 2026-11-03, decided by the maintainer.** "A `git pull` and a new session" described the one
way a fix reached a machine while every machine ran keel from a clone. Keel now installs from GitHub
by its `release` branch, so a merged fix reaches an installed copy with the next release and an
update, and a clone used as a directory source by a `git pull`; a new session either way. The
violation line below says so. The rest of this principle stands.

**Violation looks like.** A project session opening a PR against keel. A push with no preview of the
exact issue body. Pasted statement lines, identifiers or key material in an issue. A signal that
exists only on GitHub with no local record. Treating a merged PR as reaching other machines without
a release and an update (or a `git pull` in a clone) and a new session there.

---

## Applying this

When proposing a change to `plugins/**`, answer these eleven in writing. **Any "yes" is a red flag, not
a blocker — it means say why anyway.**

1. Does this add a new *thing* where deepening an existing one would do? (P12)
2. Does it duplicate a fact that already has a home? (P10)
3. Does it cache something fast in a file? (P9)
4. Does it add a rule enforced only by prose? (P4)
5. Does it escalate enforcement without a cited failure? (P13)
6. Does it add a plugin hook? (P14)
7. Does it let a stage be reached without its gates? (P1, P3)
8. Does it make an unmeasured claim about live state? (P7)
9. Does it tighten a contract an in-flight project already satisfies? (P24)
10. Does it act on one project's signal as if it were every project's? (P25)
11. Is this a known solved problem outside keel, and if so why is keel not doing it their way? (see "External provenance — what keel is a variant of")
