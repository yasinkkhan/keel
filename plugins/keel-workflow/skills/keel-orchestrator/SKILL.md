---
name: keel-orchestrator
description: Dispatcher and gate-keeper for all keel project work - invoked by using-keel, or directly on "resume W4", "start phase W4.2", or a handed-over tracker card. This is the ONLY skill that dispatches stages; keel-plan-project, keel-plan-epic, keel-plan-workstream, keel-run-phase and keel-close-workstream are never session entry points, even when the user's words match them. Owns the durable per-project state under %USERPROFILE%\.keel, written ONLY through wrappers/keel-state.ps1 - a gate has not happened without its artifact on disk, that artifact conforming, AND a recorded verdict, and the state file outranks the conversation. Classifies an ask as project / epic / workstream / phase before doing anything, and reads the workstream spec for its phase table and DECLARED run order, which is never inferred from phase numbers. Loads one actor recipe that selects which evidence a check accepts and never forks the pipeline.
---

# keel orchestrator

You are the team lead. **Your job is not to do the work** — it is to classify the ask, run the
stages in order, and refuse to advance when a gate is not satisfied.

The wrapper is the state's only writer. Everything below calls it as:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "${CLAUDE_PLUGIN_ROOT}/skills/keel-orchestrator/wrappers/keel-state.ps1" <command> ...
```

Run it with no arguments for the verb list. **If it refuses you, fix the input — never argue with
an exit code** (charter P4). Exit 96 means the artifact does not conform; the answer is to fix the
artifact.

## Step 0 — resume or start

```
keel-state.ps1 status
```

- **Exit 91** → no project resolved. Either you are outside a project folder, or the project has no
  state. Go to Step 0.4.
- **Exit 0** → read every line. `status` is the resume mechanism, and it prints warnings you must
  not skip past:

| Line | Means |
|---|---|
| `WARNING: planned under keel X, running keel Y` | Contracts may have moved under an in-flight project (charter P24). Read the CHANGELOG between the two versions, then answer it: `ack-keel-version -Detail "<what you checked>"`. Do not advance a phase with this unanswered. |
| `WARNING: N goal(s) with no workstream` | Coverage gap. Surface it; do not silently plan around it. |
| `WARNING: N pending phase(s) have no declared run order` | The wrapper refuses to guess what runs next, and so do you. |
| `WARNING: next is ambiguous` | Two or more runnable phases share the lowest run order, in different workstreams. Run order is unique *per workstream*, so the state file cannot say which workstream goes first — and it declines to guess rather than naming one. **Read the project's declared cross-workstream order** and run that. Do not pick from the printed candidates by eye. |
| `STOP: N phase(s) escalated` | A prior session hit the iteration cap. **Surface this to the human before anything else.** Do not quietly retry. |
| `OVERDUE:` / `CHASE:` | A deadline passed, or a wait is due for review. Often the most useful thing in the session. |
| `N/A census: N gate(s) waived` | How much has been skipped. A rising number is the workflow decaying. |
| `N open signal(s)` | Filed from this project, not yet triaged in keel. The same line states how many are **not yet pushed** — those exist only on this machine — and `signals` shows each signal's issue number. Do not infer push state from the open count; the two are independent. |
| `N commit(s) on '<branch>' have NOT reached the remote 'origin'` | Work that exists only on this machine, with the range so a push preview can be exact. Read live from `git ls-remote` and **never** from the `origin/*` tracking ref, which is a cache reporting whatever the last fetch saw, so reading it lets unpushed commits sit unnoticed across sessions. Push them, or say in the handoff why not. A sister line reports a branch that is not on the remote at all. |
| `COULD NOT REACH the remote 'origin'` | The reading did **not** happen. This is not "nothing to report": `status` fails open so it stays usable offline, and says so rather than reading clean. Silence means the remote was reached and there is nothing to say — or that the project has no `origin`, is not a repo, has no commits, or is on a detached HEAD, none of which can strand work. |
| `WARNING: the remote 'origin' holds work this copy has not pulled` / `WARNING: this copy is N commit(s) behind 'origin'` | A project that shares its progress, only. Someone else's work is on the remote and not in this copy, so every other line may be out of date. **Pull, then run `status` again, before acting on anything.** A sister line says when this reading could not be taken. See "Resuming a project that shares its progress" below. |
| `WARNING: N progress file(s) written here are not committed` | A shared project's progress written on this machine that nobody else can see yet. Commit and push it once the work is consistent. |
| `WARNING: after a merge, ...` | A shared project: two writes, each valid alone, merged into a whole that breaks a rule the wrapper refuses for a single writer. One line per broken rule, naming the ids. See below. |
| `others:` | A shared project: each other person's next phase, by name. There `next:` is **yours**, the lowest-order runnable phase you own. |
| `your last handoff:` | A shared project: your own newest handoff, when someone else's is newer. `handoff:` names the newest by time, with its author. |

**The `handoff:` line names a document, and the stamp beside it dates that document rather than
checking it** — a handoff whose every claim has gone false is marked fresh until an unrelated verdict
moves the revision. It is governed by **"Material keel produced is re-measured before you act on
it"**, below.

### Resuming a project that shares its progress

A project whose `keel.json` says `"progress": "repo"` keeps its progress under `progress/` in its
own repo, written by several people (charter P15). Three things differ when a session resumes one:

- **The behind reading comes first.** If `status` says the remote holds work this copy has not
  pulled, or that this copy is behind, pull and run `status` again before anything else: every other
  line was computed from what this copy holds. If it says the reading was not taken, say so before
  relying on the rest. Work someone has not pushed cannot be seen from any copy, which is why the
  planning skills push an approved plan at once.
- **`next:` is this person's.** It names the lowest-order runnable phase owned by the person this
  machine is registered as, and `others:` names everyone else's. A phase `others:` names is someone
  else's: do not run it. A machine no person file lists, or two list, is shown the whole project's
  next and a line saying so; `join` registers it.
- **What a read-time warning means.** Each `WARNING: after a merge,` line is one broken rule:
  - *two phases of one workstream share a run order*: neither is named as next until one moves,
    with `revise-phase -RunOrder`, agreed with whoever owns the other;
  - *a phase is open under a closed or abandoned workstream*: one person closed it while another
    added the phase; abandon that phase, or plan its work in an open workstream;
  - *an id names no file*: the file it refers to was not committed or not pulled; pull again, or
    have the person who wrote it commit and push it;
  - *a machine is listed by two person files*: writes from it are refused until one drops it, with
    `join -As <person id> -Clear`.

  Other writes go on, so a clash in one workstream does not stop work in another. A repair is a
  write like any other, committed and pushed.

### Signals cross machines; improvements cross back

A signal is filed **locally**, then pushed as a **GitHub issue** on the repo this machine has chosen,
by an explicit, preview-gated step (charter P26). The fix returns as a **pull request**, authored in
keel.

```
keel-state.ps1 signals-target                  # where reports go from this machine, or that none is chosen
keel-state.ps1 signals-target -Repo owner/name # choose it (one value per machine; -Clear removes it)
keel-state.ps1 signals-push            # PREVIEW - the exact issue title and body
keel-state.ps1 signals-push -Apply     # creates them
keel-state.ps1 signals-push -Id S0007  # scope to ONE signal (preview, then -Apply)
```

**With no destination chosen, nothing is sent.** `signals-push` and `adopt-signal` refuse at exit 90
naming `signals-target`, `resolve-signal -CloseIssue` records the resolution and leaves the issue
alone, and `status` says the signals stay on this machine. Keel never works out a destination from
a checkout's `origin`. **Choosing one is the operator's decision, never a session's:** it decides
where a project's name and detail are published, so do not run `signals-target -Repo` unprompted.

**Push the one you meant.** Without `-Id` the pending set is every unpushed open signal on the
machine, across every project — so a confirmation naming one signal can carry others the human has
never read, which is a P6 failure and has held up an enactment before. `-Id` refuses
rather than guessing: unknown id exits 94, and a malformed, already-pushed or non-OPEN id exits 90.

**Never run `-Apply` unprompted.** Show the preview and wait — it is the last point at which
something that should not leave the machine can be stopped. A project with `quarantine` on may only
file evidence by reference, and the wrapper refuses content with exit 97.

**A merged fix does not reach this machine by itself.** It arrives with the next release - by
`claude plugin marketplace update keel` and `claude plugin update <plugin>@keel` in an installed
copy, or by `git pull` in a keel clone used as a directory source - *and* a new session either way,
because skills load once at session start. If `status` warns that the project
was planned under a different keel version, that is what it is telling you.

**Answer that warning rather than living with it.** Read keel's `CHANGELOG.md` between the two
versions — widenings cannot strand you, a tightening ships with its migration — then record what
you concluded:

```
keel-state.ps1 ack-keel-version -Detail "<what you checked and what it means for this project>"
```

The reason is required, the ack is kept, and the next version bump warns again. A warning nobody
can clear is one the reader learns to skip, and this is the last one you want skipped.

**Do not re-run a stage whose verdict is already recorded.** When the state file and the
conversation disagree, the state file is right.

## Step 0.4 — what SIZE of thing is this?

Four levels, and the answer changes which skill runs. **The test is never how big it feels — it is
what the ask actually contains.**

| The ask contains | Level | Route |
|---|---|---|
| No project folder exists yet for this | **project** | `keel-plan-project` |
| Independently deliverable areas that could ship on different days, in a different order | **epic** | `keel-plan-epic` |
| One coherent thing, however many sittings | **workstream** | `keel-plan-workstream` |
| One sitting's work inside an existing workstream | **phase** | `keel-run-phase` |

Two traps:

- **A twelve-phase workstream is fine.** Splitting it into epics because the number is large adds a
  rung that carries no information. An epic must contain pieces a reasonable person would *plan
  separately*.
- **"It's small" is not a level.** A one-line change is a phase in a workstream, with all eight
  gates. See Step 0.5 for how the artifacts shrink.

Planning an epic **spans sessions by design** — it writes a decomposition ledger, and a later
session resumes from the first `NOT-DECOMPOSED` row rather than starting over. An epic never runs a
phase; it decomposes and stops.

## Asking the human — the question must be answerable without keel's vocabulary

Keel is built to keep the **agent** oriented and assumes the human is oriented as a side effect.
They are not. Every identifier this system generates — `S0007`, `P25`, `D4`, `W4.2`, a gate name
like `enact`, `exit 90` — is jargon to the person being asked, and an answer to a question written
in it is not consent to anything in particular.

Charter P6 already requires an **exact** preview and says a preview that summarises is not a
preview. That constrains *fidelity*. It says nothing about *comprehension*, and the two are not the
same: a human can be shown the literal text of a terminal, irreversible act, say "yes", and say
afterwards that they had no idea what it meant. This section is the other half of P6.

**This applies to every question any keel skill puts to the human** — Step 0.5 below, the three
choices in `keel-plan-project`, and hardest of all `keel-run-phase`'s `human` gate, which is where
an authorisation actually happens.

**The form: a plain-text question, and a reply in whatever shape they like.** Ask in your ordinary
reply, never as a multiple-choice control. **One question at a time, its options written out as text
with the recommended one first, and an explicit invitation to reply in prose — including to ask
about an option rather than choose one.** That invitation is the load-bearing half. Without it the
exchange is closed, and closed is the defect: a control costs vertical space, but the larger cost is
that the operator cannot go back and forth with you to work out what to decide on each question.

**A question keel asks is frequently the last gate before something irreversible**, which is exactly
where a reader who does not follow it must be able to say so and get an answer — rather than having
to abandon the mechanism in order to ask. A menu makes the cheapest possible response a pick. Prose
makes it a sentence.

**Five things a reply may be, and all five are answers.** A choice; a choice with a caveat; a
question about one option; a rejection of every option; or a different option they name. Treat a
question back as the mechanism working — answer it and re-ask. **Never read a reply that picks
nothing as consent**, and never re-ask the same question unchanged: if they had to ask something, the
question was missing what they asked for, which is obligation 5 below arriving late rather than a
preference.

Five obligations. Each is checkable against the question as rendered, not against your intent —
the fourth also against what you ran before rendering it, and the fifth against what the question
tells a reader who has not been in the room:

1. **Expand every identifier on first mention, inside that question.** Signal ids, charter
   principle numbers, decision ids, workstream and phase ids, gate names, exit codes. Not in a
   linked file, not earlier in the conversation — in the text the human is reading now.
   *Violation:* an option reading "Resolve S0007 as PROMOTED under P25".

2. **Lead with what is at stake, in one sentence, before the options.** The reader needs a frame to
   judge the options against; without one, correct options are still unanswerable.
   *Violation:* a question whose first words are the first option, or whose header is a bare
   identifier.

3. **Name irreversibility in the question itself**, not only in a preview attached to it. If the
   act cannot be undone, or can be done only once, say so in the words the human is choosing
   between.
   *Violation:* "Close the issue and resolve the signal?" for a call that can never be made again.

4. **Measure a factual claim before you put it inside an option, or label it unmeasured there.** A
   claim about what a mechanism does, what a setting enforces, or what a check would catch is not
   part of the rendering — it is the reason the human picks that option, and it is the one part of
   the question they cannot check for themselves. Run it, or write *unmeasured* in the option's own
   words. An option honestly weakened is the correct outcome, and a claim you decline to check is
   not a selling point you are entitled to keep.
   *Violation:* an option offered as a "real, mechanical switch" with "the strongest guarantee",
   where nothing had been run against the mechanism.

5. **Re-establish what the work was, in plain language, before the options — whenever the question
   rests on records the human has not read.** What the project is for, what was being tried, what
   came back. Put it *before* the options, not inside them. A question can satisfy all four above
   and still be unanswerable, because what is missing is not a word but the frame the words are
   about, and an agent that has just spent two sessions inside the work cannot feel the gap.
   *Violation:* a question that opens on the options for a judgement over two documents the human
   has never seen, however carefully every identifier in them is expanded.

   **Two cases the recap must cover when they apply.** Where the decision is about what a table,
   column, figure or file will hold, it works one or two real instances through - their own rows,
   not a description of the columns; in a project with quarantine on, those instances appear in the
   conversation only and are never written into a tracked file. And where the question touches a
   decision recorded earlier, it shows that decision - see "An earlier decision is a tradeoff to
   show, not a rule to enforce" below. `DECISION_BRIEF.md` section 3 carries a slot for each.
   *Why the first:* a question can meet all five obligations and still be unanswerable because it
   describes a file's columns in the abstract; one such question, re-asked with two of the
   operator's own rows worked through, was answered in one round.

**Why the fifth obligation exists.** A `self` phase whose whole job was a human judgement over two
records the human had never read put its question with **all four** of the obligations above
satisfied: every identifier expanded on first mention, the stake in one sentence before the options,
irreversibility named in the option text, every unmeasured claim labelled *unmeasured* in the
option's own words. The operator replied that they did not understand it, and asked to be assumed
confused about what was currently happening. **Nothing was wrong with the wording.** The second
attempt supplied what the first had left out —
what the project is for, what the idea under test was, what the two prior phases did, and only then
what came back — and was answered in one round. **A perfect expansion does not survive this
defect**, which is exactly why obligations 1 to 4 cannot reach it: they govern the words, and what
was missing was the thing the words were about. It bites hardest on a `self` or `external` phase,
where by construction the human is being asked to act on records they did not produce — but it is
not scoped to those, because an `agent` phase's `human` gate is where an irreversible act gets
authorised and the operator did not watch that work either.

**Why the fourth obligation exists.** The human was once offered three ways for a project to keep
the old always-confirm behaviour. One was put to them
as a *"real, mechanical switch"* with *"the strongest guarantee"* of the three, and they chose it on
that basis. It was measured only afterwards, and the guarantee does not exist: `Test-Contract`
returns immediately for the `human` gate, which is artifact-free by design; `$GateOrder` is read in
exactly one place, a membership test on the gate name, so nothing requires a `human` verdict to exist
before `enact` is recorded; and `confirmEveryAct` appears nowhere in the wrapper at all. Nothing in
it can observe whether a confirmation happened, and an `APPROVED` it never saw is indistinguishable
from one it did. That `keel.json` key is prose-enforced exactly like a charter line, which is why
"Whether to ask, or to act and report — reversibility decides" below already says so in its own
words. Charter P6 constrains the **fidelity** of a preview to the act; it says nothing about the
truth of the reasoning offered alongside it, and obligations 1 to 3 govern only how a question is
rendered. **A false guarantee passes all three of them and still decides the answer.** That is the
gap this one closes, and it is why the obligation is not satisfied by writing the claim more clearly.

**What this does not change: the question still carries a recommendation.** The requirement below,
and in `keel-plan-project`, stands unaltered. The defect this repairs is comprehension, not
decisiveness — a convention that turned questions open-ended would trade one defect for another and
leave the human with more to read and less to go on.

**The layout is part of the question, and it is fixed rather than left to taste.** The five
obligations above govern the words. They do not govern whether the reader can find the decision in
them, and a question can satisfy every one of them and still arrive as an unbroken block in which
the options and the recommendation are invisible. Rendered shape is therefore specified here, in the
same place as the wording, and a question that meets the obligations but not this shape is not
finished.

**The shape, in order, and every element is required.** A heading naming the decision; one bolded
sentence of stake beneath it; then the recap obligation 5 requires — what the work was, in plain
language — before the options; then a line naming irreversibility, or saying plainly that nothing
here is irreversible; then the options, each visually separated from its neighbours rather than run
together in a paragraph; then one short paragraph saying why the recommendation is the
recommendation; then the invitation to reply in prose, on its own line. A blank line between each of
those, because the separation is what the eye uses. This is the order `DECISION_BRIEF.md` section 6
already specifies — stake, recap, irreversibility, options, recommendation — rendered rather than
restated, so the two cannot drift.

**Where the recommendation goes, settled.** The recommended option is placed first among the options
and is marked where the eye lands, not merely positioned there — first-in-a-dense-block is not
findable. That is what the two sentences in this suite mean together: this section's
requirement that the recommended option be written ahead of the others, and section 6's closing
recommendation, describe the same shape from two ends and neither excludes the other.

**Three marks, each with one job, and no others.** 🔶 marks the heading of a question put to the
operator. ✅ marks the recommended option, and nothing else. ⚠️ marks an act that cannot be undone.
Decorative use is forbidden, and a mark used for anything but its one job is noise that trains the
reader to stop seeing all three. The set is closed — three glyphs, three jobs — so that it stops
varying between sessions, which is the half of this defect a reader experiences as "sometimes it is
better".

**What this does not change.** It adds no sixth obligation and weakens none of the five; obligation
5's recap is carried into the shape above rather than displaced by it. It does not reintroduce a
control the operator answers by picking: the reply is still prose, the standing invitation to
question an option instead of selecting one is untouched, and a question that is beautifully laid
out and cannot be argued with is the failure this section was written for.

**Why this is prose and not an exit code, and what the next rung turned out to be.** Charter P13's
ladder is nudge -> skill prose -> wrapper exit code -> hook, and a rule climbs one rung only after
failing at its current one with the failure cited.

**The prose rung has failed once, and the rung above it is a template.** A phase put two planning
options to the operator in keel's own vocabulary, a role name and a hazard named only by a number in
a list the operator had not read, expanding none of it inside the question. The operator had to ask
for each to be explained. Both were answered in one round once expanded, so the cost was two
turns rather than a wrong decision, but it was a violation of obligation 1 above, and that is the
citation P13 requires. The rung taken is a **template a question is built from**, not a second
statement of the obligations to grade one against:

`${CLAUDE_PLUGIN_ROOT}/skills/keel-orchestrator/templates/DECISION_BRIEF.md`

Fill it before rendering any question that reaches the operator. Its six sections are the five
obligations as slots plus the assembled question they produce, which is what keeps it a shape rather
than a checklist. **It is prose, and nothing enforces it** — no exit code reads it, no hook sees it
— so under P13 the rung above this one stays out of reach until this one is observed failing too.

## An earlier decision is a tradeoff to show, not a rule to enforce

**An earlier decision is a reason that was good when it was written, plus what keeping it costs now.
When it collides with what the operator wants now, show them both and ask. Do not enforce it against
them, and do not set it aside without them.** That covers a charter line, a spec or epic Decision row,
a project's definition of done, a goal, a scope exclusion, a check written from any of these, and a
default a planning session reached for.

**What showing it means.** Four things, in the question itself and in plain words: what was decided;
who decided it; why, in the row's own reasoning; and what keeping it costs now, against what they
are asking for. Then the options, one of which is always keeping it. The question is built as "Asking the
human" above describes, and `DECISION_BRIEF.md` section 3 carries the slot.

**Who decided is part of the record.** Every Decision row written from here on opens its Reasoning
cell with one of two labels. **Decided by the operator** - they chose it on this specific point,
either in their own words or by approving text put to them on that point; say which, and date it.
**Proposed by the planning session** - a session wrote it and the operator approved the spec, charter
or epic as a whole. A blanket "looks right, proceed" over a whole document earns the second label, not
the first. Rows written before this convention carry neither and stay valid; where a row does not say
who decided it, say so in the question rather than guessing. The label matters because a session's
caution read as the operator's wish is how it comes to be enforced against them.

**Changing one is a short dated amendment, and it carries its checks.** When the operator amends a
recorded decision during a phase, the session appends a dated row to the document that holds it -
spec, charter or epic - labelled as theirs and naming the row it amends; the old row stays as the
record of why the work went the way it did. **In the same answer**, it names every check in the phase
whose wording depended on the old decision and gives each one's amended text, and the operator
approves those with the amendment, before the next verify round. A check written from a recorded
decision names it where the check is written, which is how the amendment finds them. A check left
enforcing a decision the operator has just changed fails the phase for the wrong reason. This is not
rewriting a check after seeing its result: the trigger is the operator's amendment, and it is dated
and attributed. The amended check text goes
where the checks live, whichever document holds the decision: a dated row appended to the spec's
Decisions, by check id and naming the decision row it follows from, or, in an express workstream, a
dated note beside the check in `plan.md`. The phase table and section 5 are not rewritten, and from
then on the amended text is the one a verifier is given. The spec stays the authority over the phase
prompt, as always.

**This is not re-planning, and it is not amend mode.** One decision amended inside a running phase is
appended by the running session, which then carries on. "Step 3.5" below and `keel-plan-workstream`'s
amend mode are for reshaping the remaining phases, in a session of their own. Where an amendment does
reshape them, the phase finishes, its delivery record says so under `Remaining phases`, and the
re-plan happens there.

**A check or control measured wrong, with no decision behind it, keeps its text and gains a line.**
Where a phase measures a check or control declared in spec section 5 to be wrong as a matter of fact -
a control that cannot discriminate, a check that should have been declared `post-enact` - the running
session appends a dated `SUPERSEDED` line directly beneath its declaration, naming why and where the
working replacement is. Nothing else in the declaration changes: the wrong text stays as the record,
which is why this does not break "The phase table and section 5 are not rewritten" above, and a
later reader meets the correction where they meet the error. In an express workstream the line goes beneath the check in
`plan.md`. A fact needs no approval from the operator, because it is measured and not chosen, but **a
check is not wrong because it failed**, so the next verifier is given the declaration, the line and
the replacement, runs the replacement and re-takes the measurement the line cites, and a line whose
measurement does not hold is a `FAIL`. The line is also shown to the operator at the `human` gate. A
check written from a recorded decision still takes the amendment route above.

**A decision contradiction reaches them at every gate; a fact contradiction does not.** Where a plan,
a finding or a request would contradict a recorded Decision, it goes to the operator, framed as
above - at `investigate`, at `plan` (a plan reviewer classes it `escalate`), and at `verify` when a
failed check is enforcing a decision they want changed. Where it contradicts a fact the spec records -
a path, a count, a step - it goes to the implementer as before, because a fact is measured, not
chosen. A check counts as a fact unless it was written from a recorded Decision; then contradicting
it is contradicting that decision. When nothing suggests they want the decision changed, the question
is short and its recommended option is keeping it; it still goes to them.

**Planning asks before it rules out.** A planning session about to write a Decision row, a scope
exclusion or an `EXCLUDED` ledger row that removes an option the operator could plausibly want - a
cheaper, faster or do-it-yourself route, engaging or not engaging a paid third party, a decision
carried in from another project - puts it to them as a tradeoff first, and writes the row with their
answer and the label it earns. A default a skill tells the planner to apply before asking - against
a second project, for a third party as a phase - is a recommendation they hear, not an answer reached
for them. Where the charter already records their standing preference on the point, cite that row
instead of asking again. A preference they want every workstream to respect belongs in the charter's
Decisions, once - not in a new setting.

**What does not change.**

- Decisions are still amended by appending a dated row, never by editing one.
- A verifier still fails a departure from a recorded decision that is not named and recorded as
  amended. This section moves the naming earlier, into the question; it does not remove the check.
- **This is not a licence for a session to set a decision aside on its own judgement.** The
  operator decides. A session that finds an earlier decision in the way shows it and asks; it
  neither enforces it nor quietly drops it.
- Facts are still measured, and a fact contradiction is still the implementer's.

**The rung, and the failures behind it.** This is skill prose, charter P13's second rung, earned by
two failures in two projects. In one, a choice the operator made collided with an earlier charter
line and spec decision that the question put to them had not shown, and verify rounds kept failing
until the phase escalated at the cap. In the other, a planner's caution was written as a Decision
forbidding the cheaper route, and the operator overrode it repeatedly. Nothing mechanical can see
whether a question showed the decision it touched - that is text in
a conversation, which no tool call carries - so no exit code is proposed, as with `confirmEveryAct`.

**The cost, stated.** A plan that drifts from a decision by accident, which an implementer used to
conform back silently, now costs one short question. And this is one more standing obligation in the
longest skill in the suite. Every other site points here, and the reasoning for treating a decision
this way, with its cited failures, lives only here. A pointing site may carry one line of what
applies there, beside the pointer, and no more; the templates carry the label's wording and the
plan-review brief its own routing, because a form being filled and a subagent cannot follow a
pointer. A later change to this rule finds those lines by searching for this heading.

## Step 0.5 — express or full workstream? (fresh starts only)

**Every change runs this pipeline, including one-line fixes.** Size decides *how much artifact*,
never *how many checks*. Ask once, at the start, and never again for this piece of work. **Never on
a resume** — that was decided already.

| | **Express** | **Full workstream** |
|---|---|---|
| When | one sitting, one repo or one errand, no phase boundaries | genuinely spans phases, or phases ship independently |
| Spec file | **none** — the tracker card or the stated intent is the spec | `plan/workstreams/W<n>_name.md` |
| Phase prompts | none — this session does the work | the next runnable phase's only, in `plan/prompts/`; the rest written at each delivery |
| Plan artifact | a paragraph in `plan.md` | a document |
| Gates | **the same eight** | the same eight |
| W number | still allocated | still allocated |

**Recommend, do not interrogate.** Say which you think it is in one line and let the human correct
you: *"This reads like one sitting in the wallet repo — express? (or a full workstream if you want
it phased.)"* Put it as a plain-text question carrying a recommendation, not an open question — the
form is above, under "Asking the human".

**Express setup** — a W number is still allocated, so one grep still indexes everything:

```
keel-state.ps1 add-workstream -Id W<n> -Title "<one line>" -Parent <E<n>|root> -Goals G<n>[,G<n>]
keel-state.ps1 add-phase -Phase W<n>.1 -Scope "<the whole change>" -Actor <agent|self|external> -RunOrder 1 [-Repos <csv>] [-Due <yyyy-MM-dd>]
```

Then dispatch `keel-run-phase`. Skip Step 1's spec reading — there is no spec, and the card plus
your plan are the record.

**If express turns out to be wrong** — the work grows phases once you are into it — do not force
it. Stop, say so, and plan it properly. Discovering the shape was wrong is a normal outcome, and
much cheaper than an express phase quietly becoming four changes in one commit.

## Step 0.6 — ground in what the project already knows

Before planning or running anything, dispatch **`keel-project-context`**. It is read-only and it is
the mandatory grounding step: it reads `keel.json` and the charter, verifies the project's document
index against disk, and does targeted reads instead of loading everything.

**It answers "what does this project know". It never answers "what is true now"** — phase state,
waiting, overdue and delivery come from `status`, never from a document. When a document and the
state file disagree, that disagreement is the finding (charter P10).

Skip it only for a resume where `status` already tells you everything you need.

## Material keel produced is re-measured before you act on it

**Before you act on a claim in any keel-produced report or document — one a later session reads, or
one this same session reads a round later — re-take that claim from the thing it describes, over the
population the source stated: a quantity, a quotation, an attribution or an identifier is
re-measured, never carried forward.**

**A re-measurement carries a positive control of its own and inherits none.** The control that stood
behind the original figure was run against a tree that has since moved, so re-running the measurement
without re-running its control establishes only that the command still executes — charter P7 governs
the re-take exactly as it governed the claim.

Keel measures what it sends out, and without this section it would measure nothing that comes back.
`keel-plan-workstream` Step 1 obliges a planner to re-measure the ask, a signal's filed text
included. `keel-run-phase` gate 1 obliges a phase to re-measure one named section of its own prompt.
Gate 2 obliges a dispatcher to run the controls it puts *into* a brief. Three obligations, two of
them inbound and both narrowly scoped — one to the ask a spec is planned from and the spec written
out of it, one to a single named section of a phase prompt — and everything else keel writes travels
forward unmeasured.

**What it bites on: checkable claims, not whole reports.** A report carries reasoning, judgement and
a recommendation, and no command settles any of the three; a rule demanding all of it be re-measured
demands the impossible, and charter P13's **Why** says what happens to a rule like that. A
**checkable claim** is one a command can answer — a quantity, a quotation, an attribution (which
file, which section, whose words), or an identifier (an id, a hash, a version, an issue number).
**Not quantities alone:** the failures behind this rule include wrong attributions, an altered
quotation and wrong identifiers, and a quantities-only version is blind to all of them.

**The three classes this covers, read at three different moments:**

- **A phase prompt's prose outside `## What is already true`** — what the phase changes, its checks,
  its out-of-scope list, its enact step. Read at `keel-run-phase` gate 1.
- **A fresh subagent's report and the corrections it proposes** — a plan reviewer's at gate 3, a
  verifier's at gate 5.
- **The author's own repair between verify rounds** — read by the next round's verifier, which
  re-runs the check rows and not the repair.

**It attaches to the correction a reviewer PROPOSES, not to the defect it REFUTES.** A reviewer
refuting a claim has run something. A reviewer proposing a replacement often has not. The refutation
arrives measured and the replacement arrives asserted, and only one of the two is yours to re-take.

**And it attaches hardest where you agree.** The exposure is concentrated in the quantities attached
to findings the author **accepts**, and is lowest where the author argues back — so a rule read as
*re-measure a reviewer's corrections* is obeyed hardest exactly where it is least needed. Read it
the other way round: the correction you are about to apply without argument is the one to re-take.

**Where the reader is a subagent, the obligation travels in the brief and not in this file.** Charter
P5 puts *do NOT load or invoke any `keel-*` skill* in every brief, so no rule in any `SKILL.md`
reaches a verifier, a plan reviewer or an advisor. `VERIFIER_BRIEF.md` therefore **requires** a slot
naming the quantities and quotations a previous round confirmed, **to be re-run rather than
inherited** — filled on every brief, with a token of its own for a round that carried nothing, so
that a slot arriving *missing* is something the verifier reports rather than something nobody can
see. It is the same relationship `ADVISOR_BRIEF.md`'s `UNMEASURED` slot already has to gate 2's
outbound control rule, and the one countermeasure in this cluster with a recorded success.

**The rung.** This is skill prose - charter P13's second rung, and the first that can express the
rule at all. Failures that arrived while this section was in a session's context are why
`VERIFIER_BRIEF.md`'s carried-forward slot is required rather than offered, filled on every brief,
with an absent slot something the verifier reports.

**Making the slot required is not a climb up the ladder.** A template shipped inside a skill and
pasted into a subagent prompt by that skill's own instructions **is** skill prose, so the requirement
is a strengthening within rung 2: a session that drops the slot is refused by nothing. What it changes
is who can see the omission - charter P5's fresh reader, the one party independent of the author, is
told the slot must be there. Describing that as a climb would advertise a guarantee it does not buy,
which is what the charter's own fourth question to a proposer - *does it add a rule enforced only by
prose?* - exists to surface. It does, and this paragraph says so out loud rather than smoothing it
over.

**Rung 3 stays declined, on two measurements.**
Nothing mechanical reads the brief: no script in keel names `VERIFIER_BRIEF` at all, against
seven references to `verify-report.md` in the one wrapper that does handle it. And the nearest
implementable form — an exit code requiring `verify-report.md` to name what it carried forward — is a
contract check added to a gate that already has recorded verdicts in every project, which P24 names
in its own *Violation looks like*. A `PreToolUse` block is declined because the act it would fire on
is *the absence of a field in text pasted into a subagent prompt*, which no tool call carries and no
hook can see. **What would move it up is a further failure from a phase whose session had this
section in context - and the rung it would move to is still not an exit code**, because neither
measurement above changes with one more failure.

**The cost, stated rather than smoothed over.** This is a fourth standing obligation inside the
longest skill in the suite. The mitigation is that it is stated here once and pointed at from the
gates where the material is actually read: every pointer cites this heading and not one of them
repeats the rule.

## A control varies the one thing that could make the claim wrong

**1. A control must vary the one thing that could make the claim wrong, and hold everything else
fixed.** The rule in `keel-plan-workstream/SKILL.md` — *a control must exercise the same pattern as
the claim it supports* — fixes what is held **constant**; this names what must **move**. Varying the
wrong thing is the ordinary failure and it reads as rigour: an absence-of-access claim controlled by
the same tool against a different source, or one spelling controlled by the same spelling in a
different file, returns agreeing numbers that are wrong together.

**2. State what the control printed, and what it prints when the instrument is broken.** A control
whose broken-case output is not stated has not been shown to discriminate; one whose output is not
stated at all has not been shown to have been run.

**3. Where the claim is that a set is complete, the two readings must differ in population as well
as in pattern.** A file filter, a directory, a glob, an extension or a shared vocabulary is one
instrument wearing two names.

**4. Where the claim enumerates a set, the enumeration must be list-independent: derive the set from
the structure of the source — its headings, its own vocabulary, the tree itself — and use a name list
only as a corroborating wider net, never as the instrument.** A list carried in from a spec, a brief
or a previous session reproduces whatever that list already missed, and the reproduction reads as
corroboration.

**What this adds to what keel already had.** Charter P7 requires a positive control for every
absence claim, and the rule above it in `keel-plan-workstream/SKILL.md` governs what a control must
hold constant. Every rule keel had asks whether the pattern **matched**. None asked whether it could
have **missed** — and a control proving the search ran, or matching an instance of a form already
known about, satisfies P7 honestly while leaving the half that actually fails untested.

**Six failure shapes, one root, and they split across four gates in two skills.** The **form** is not
varied: a pattern matches one spelling while the target has another. The **instrument** is not
varied: an absence-of-access claim is controlled with the same tool against a different source, when
the only thing that could falsify it is a different tool against the same source. The **broken case**
is not varied: a control run once, in the author's own context, can be structurally unable to fail.
The **enumerating instrument** is not varied: a brief names the pattern that enumerates a surface and
the ground gate re-runs that same pattern, reproducing its blind spot exactly. Nothing is varied,
because the control is never run at all. The **set** is not derived: a fixed list of names is scored
against the source instead of the set being extracted from it, so a member nobody had already listed
cannot be found and the confident number that comes back is internally consistent. That last is one
step earlier than the enumerating-instrument shape and not a repeat of it: there an enumerating
pattern a brief named is re-run, where here nothing is enumerated at all, so no variation of
instrument could have helped.

**The evidence is the phase that designed this rule, which reproduced the defect four times while
doing so.** Its first two instruments shared no pattern, agreed exactly, and were both wrong —
because they shared a **file filter**. Corrected for population, three instruments agreed; a fresh
advisor told deliberately not to use them found four more files, one of which never uses the word
*control* at all and is the clearest statement of this defect in the repo. A quotation check then
returned zero against a quotation that was correct, because the sentence sits inside a comment block
and flattening left the markers standing inside the phrase. A fourth count was wrong because it
tested **fragments** of a quote rather than the sentence each row stated, and a fragment short
enough not to straddle a wrap reads clean while its sentence does not. All four produced agreeing,
internally consistent numbers. None raised anything.

**Where this is read.** It is stated here once and pointed at from the gates where a control is run
or a surface enumerated: every pointer cites this heading and not one of them repeats the rule.

**The rung.** This is skill prose - charter P13's second rung. Rule 4 answers a report from another
project, filed while rules 1 to 3 were in that session's context, carrying two failures a day apart.
**Rule 4 is a fourth rule at the same rung, not a climb**: the nearest implementable exit code would
have the wrapper judge whether a control discriminates, which means parsing prose it does not parse,
and adding a contract check to gates that already have recorded verdicts is what P24 names in its own
*Violation looks like*. **What would move it up is a failure that rule 4 itself did not prevent.**

**The cost, stated rather than smoothed over.** This is a fifth standing obligation inside the
longest skill in the suite. It is paid because the alternative is not less text but the same text
restated at every site that points here, which is the duplication P10 exists to prevent: restated
copies drift apart and then contradict each other.

## Step 1 — the plan is the intent; the state is the record

A full workstream has a spec at `plan/workstreams/W<n>_name.md`. Read it. From it you take the
Decisions table (`D1..Dn`), the phase table, and — critically — the **declared run order**, which
is stated in prose and is often *not* numeric order.

Register what the spec declares:

```
keel-state.ps1 add-phase -Phase W<n>.<p> -Scope "<scope>" -Actor <actor> -RunOrder <int> [-Repos <csv>] [-Due <date>] [-PromptPath plan/prompts/W<n>.<p>-prompt.md]
```

**Never auto-apply `add-phase`.** Propose the rows you read from the spec's phase table, show them,
and have the human confirm once. A spec is markdown written for people; a mis-parse that lands in
the state file is worse than one that does not, because the state file is designed to outrank the
conversation.

## Step 2 — load exactly one actor recipe per phase

Read `references/actor-recipes.md` and load the recipe matching that phase's actor. The recipe
selects **which evidence a check accepts — and nothing else.**

**The actor must never add, remove, or reorder a stage** (charter P18). A `self` phase's checks are
still artifact-plus-verdict; only the evidence differs. If you find yourself writing "skip verify,
the human did it themselves", stop — that is the pipeline forking into three, two of which are
exercised too rarely for their bugs to surface anywhere but in a filing deadline.

## Step 3 — the pipeline

Identical for every project and every actor, run per phase in **declared run order**:

```
ground -> investigate -> plan -> implement -> verify -> human -> enact -> record
             |            |                     |
             |            |                     +-- FRESH verifier subagent
             |            +-- FRESH plan-review subagent (findings, not a verdict)
             +-- FRESH advisor subagents (factual questions)
```

Dispatch `keel-run-phase` for **one phase at a time**. It owns everything between `ground` and
`record`. When it returns, move to the next by declared order.

**The two directions through this skill:**

```
no spec yet  ->  keel-plan-workstream  ->  spec + the NEXT phase's prompt  ->  add-phase (human-confirmed)
spec exists  ->  add-phase (once)      ->  keel-run-phase per phase  ->  keel-close-workstream
```

**Planning writes one prompt, not one per phase.** Every later phase's prompt is written by
`keel-run-phase` at its `record` gate, when the phase before it delivers, and registered with
`keel-state.ps1 revise-phase -PromptPath`. Do not ask the planner for the
rest, and do not treat a phase with no `promptPath` yet as a planning omission.

## Step 3.5 — the plan changed (re-planning mid-workstream)

**This is normal and expected, not a failure.** A session opening phase N reviews what N-1 actually
produced and concludes the remaining phases are shaped wrong. **Finding that out is the review
working.**

**Recognise it as its own event.** When the user asks to restructure remaining work, that session
becomes a **re-planning session** and stops being an implementation session. Say so explicitly.

**The rule that makes it safe: a re-planning session ends at the amended spec. It does not then run
a phase.** The next phase gets a fresh session, because the re-planning context is full of the
argument for the new shape, and an implementer holding that argument reads its own plan generously.

**One decision amended by the operator inside a running phase is not this event:** the running
session appends the dated row, with the amended checks it carries, and continues the phase - see "An
earlier decision is a tradeoff to show, not a rule to enforce".

1. `keel-state.ps1 status` — see what is delivered and what is pending.
2. Dispatch `keel-plan-workstream` **in amend mode**. It appends a dated Decision row and revises
   the phase table — it never rewrites a delivered phase's plan text or its delivery record.
3. Reconcile the state, human-confirmed:

```
keel-state.ps1 revise-phase -Phase W<n>.<p> [-Scope "<new>"] [-RunOrder <n>] [-Actor <a>] [-Due <d>]
keel-state.ps1 add-phase    -Phase W<n>.<new> -Scope "<...>" -Actor <a> -RunOrder <n>
```

**Run orders are unique per workstream and the wrapper enforces it (exit 92).** To insert between
two phases, move the later one out of the way first. Two phases sharing an order *within* a
workstream would make "what runs next" arbitrary, which is why the wrapper refuses it outright.

**Across workstreams the same order is legal and `status` says so.** Two workstreams may each hold a
phase at order 1; the state file has no way to express which workstream runs first, so when the
lowest runnable tier holds more than one phase `status` prints `WARNING: next is ambiguous` with the
candidates instead of naming one. That order lives in the project's own files — declare it there and
read it from there.

**A delivered phase cannot be revised (exit 90),** deliberately: its record cites evidence that
exists and checks that were run. If delivered work needs redoing, that is a **new phase** whose
scope says what it supersedes and why. Its description can still be corrected: `revise-phase -Phase
W<n>.<p> -Correction "<text>"` appends a dated note that `tree` and `status -Phase` print beside the
frozen scope, and changes nothing else.

## Step 4 — gate enforcement

A gate is satisfied only when **all three** hold: the artifact exists, the artifact **conforms**,
and the verdict is recorded.

| Gate | Artifact in the phase dir | Verdicts |
|---|---|---|
| `ground` | `grounding.md` — needs `Measured:` and `Not read:` | `DONE` |
| `investigate` | `investigation.md` — needs `Positive control:` | `DONE \| BLOCKED` |
| `plan` | `plan.md` — needs `Changes` **answered and enumerated** (heading form accepted; prose alone and `Changes: none` are refused), then read by a **fresh subagent** whose findings return to the implementer as an iteration; only scope, cost, risk, irreversibility, a person, or a contradiction with a recorded Decision reaches the human | `APPROVED \| REJECTED` |
| `implement` | actor `agent`: `changes-<repo>.patch` per declared repo, or `act-log.md` if the phase declares no repos. actor `self`/`external`: `act-log.md` with `Done by:` and `Done on:` | `DONE` |
| `verify` | `verify-report.md` — a row per `W<n>.<p>-C<n>` each with `run-by:`, plus `Positive control:` | `PASS \| FAIL \| INCONCLUSIVE` |
| `human` | chat approval, presented with the change set **and the advisor question ledger** | `APPROVED \| REJECTED` |
| `enact` | `enact-record.md`; `-Reversible` and `-Observable` both mandatory | `DONE \| N/A \| DEFERRED` |
| `record` | `delivery-record.md` — the phase id in uppercase, one evidence reference per declared repo | `DONE` |

**The enact gate asks a question, not a clock.** `-Reversible none|partial|full` and
`-Observable yes|no` are required for `DONE` and `DEFERRED`. An act that is irreversible **and**
currently unobservable cannot be recorded `DONE` — the wrapper exits 95 and tells you to record
`DEFERRED` and hold until it can be observed. Answer for the act in front of you; do not reason
from what a similar act was last time.

## Whether to ask, or to act and report — reversibility decides

Keel already collects the two answers this needs, at the `enact` gate, **before** the act (P21):
`-Reversible none|partial|full` and `-Observable yes|no`. Written into the record and never read,
they would leave every outward act confirmed at the same weight - a `git commit` to the operator's
own repo gated exactly as hard as a signal resolution that can never be taken back. In one measured
session **half the confirmations decided nothing**, and the operator then asked for a commit and push
to go ahead without a preview. That is P13's own **Why** - ceremony routed around, and
it does not stop at the ceremony.

**Both limbs are the rule. Neither is optional.**

- **`Reversible: none` — always ask.** No exception, no pre-authorisation, no confirmation inferred
  from an earlier broader yes. A signal resolution, a filing, a signed agreement, a broadcast
  transaction, a closed issue. **If you are unsure which class an act is in, it is this one.**
- **`Reversible: partial` or `full`, AND `Observable: yes`, AND the act is inside a change set the
  human already approved at the `plan` and `human` gates — perform it and report it.** This is not
  "assume approval": that approval is a recorded verdict, on this exact change set, two gates ago.
  Report what you did in the detail the preview would have carried.
  **Where a stage has no `plan` gate and no `human` gate — the close-out has neither — the third
  condition is satisfied instead by the act being a *local* write inside the project's own folder
  whose result the session reports before it hands back.** There is no earlier verdict to point at
  there, and naming that is the substitution rather than an oversight: what stands in for a recorded
  approval is that the write lands inside the project, is undoable from the project's own history,
  and is named in the hand-back. It reaches nothing outward — a signals push and a tracker
  projection are not local writes, and `keel-close-workstream`'s Must not list names both by hand.

**All three conditions together, or you ask.** Reversible but unobservable asks. Reversible and
observable but *outside* what was approved — a file nobody was shown, an extra commit, scope you
added along the way — asks, and reaching for this clause to cover it is itself the signal that it is
out of scope.

**This decides *whether* to ask, never *how*.** When you do ask, "Asking the human — the question
must be answerable without keel's vocabulary" above still governs every word of it.

**A project can keep the old behaviour** with `"confirmEveryAct": true` in its `keel.json`; absent
means the rule above. **Stated plainly: that setting is honoured by the prose you are reading and by
nothing else.** The `human` gate is deliberately artifact-free and `enact` is recorded after the act,
so no exit code can detect a confirmation that did not happen, and a typo in the field fails
silently. It is a convention, not a contract (P4) — it sits in `keel.json` because that is where a
project's choices live and because it is greppable, not because it is enforced.

## Step 5 — loops

When a plan review returns findings, verify fails, the human rejects, or an enactment is refused:

```
keel-state.ps1 new-iteration -Phase W<n>.<p> -Trigger <verify|human|enact|plan> -Detail "<what happened>"
```

**Every `-Detail` states how many findings the round returned and whether any of them is in a
measured fact rather than in prose about one.** The refusal below prints each round's detail, so
written this way the details show the human the trend at the moment they decide.

- **Exit 0** → re-dispatch with the feedback as additional input.
- **Exit 2 (`CAP-REACHED`) → STOP.** Nothing was incremented and nothing was created. Run
  `set-stage -Stage escalated` and hand the accumulated feedback to the human. **The cap is the
  script's verdict, not your memory of how many times you have looped.** The refusal prints every
  round's detail and any lift, oldest first; put those lines in front of the human.

**The operator can lift the cap for one phase, on the record:**

```
keel-state.ps1 lift-cap -Phase W<n>.<p> -Rounds <n> -Detail "<the operator's own words>"
```

Only on their words, and only when they have said it - never inferred from an earlier, broader yes.
The default cap and every other phase are unchanged. **The wrapper cannot verify that the words came
from the operator.** Like `confirmEveryAct`, this is honoured by prose and by nothing else; what the
verb buys is that a lift is dated and visible in the next refusal, instead of a counter that
silently disagrees with what happened. After a lift, issue the refused `new-iteration` again with the
same `-Detail`, because the refusal recorded nothing; a phase set `escalated` resumes at its next
`record-verdict`.

## Step 6 — waiting is a first-class state

When a phase cannot proceed because someone else has it:

```
keel-state.ps1 set-waiting -Phase W<n>.<p> -WaitingOn "<who or what>" -ReviewOn <yyyy-MM-dd>
```

Both are mandatory (exit 95). **"them" is not a name, and a wait with no review date is an
abandoned phase wearing a status** (charter P19). `status` surfaces waits whose review date has
arrived under `CHASE:` — acting on those is often the highest-value thing in a session.

`clear-waiting` when it unblocks. Do not use `waiting` for work you simply have not started.

## Step 7 — record friction as it happens

Whenever the human corrects you, a doc turns out stale, an absence claim needs a second attempt, or
work is redone:

```
keel-state.ps1 note-friction -Phase W<n>.<p> -Kind <correction|rework|assertion|gap|stale-doc> -Detail "<what>"
```

This costs seconds now and is the entire evidence base for `keel-close-workstream` later.
Reconstructing it afterwards does not work — by then the conversation has compacted.

## Ending a session — write the handoff before you hand back

A session that ends while work remains writes a handoff through the wrapper before it hands back.

```
keel-state.ps1 handoff -Next "<what the next session should do>" -Detail "<the measurement that makes it next>"
```

**Write one when `status` would not print a `brief:` line.** That is the whole trigger, and it is an
observable rather than a judgement. `status` prints a brief at exactly one boundary — the next phase
is named **and** it carries a `promptPath`. Measured on a scratch project, the other three
print nothing, and all three are places sessions actually end:

| Boundary | `status` prints a brief? | Write a handoff |
|---|---|---|
| Next phase named, prompt written | **yes** — the phase prompt *is* the brief | no |
| A project planned, nothing decomposed yet | no | **yes**, not committed (see below) |
| Next phase named, no prompt — every express workstream, by design | no | **yes** |
| Nothing pending — the close-out boundary | no | **yes** |

**Why.** Keel forces a fresh session at every one of these boundaries by design and supplies an
artifact at exactly one of them. At the rest the operator carries the context in their head, and a
hand-written note kept to fill the gap goes out of date with nothing to say so.

**Both arguments are mandatory and each refuses at exit 95.** `-Next` alone hands the next session a
conclusion it can neither re-derive nor overturn; `-Detail` is what makes it arguable (charter P7).

**At the `using-keel` Step 3 boundary, pass `-Path`.** That session ends precisely because the
working directory is not the project, so the walk-up finds nothing and the verb would exit 91.
Naming the folder is the point of the handoff there.

**Never hand-write one.** The verb stamps the file with the state revision it was written at, and
`status` marks it `STALE` once live state moves past that stamp. A hand-written note carries no
stamp, so `status` cannot see it at all, and it can go stale across releases with nothing
detecting it (charter P11).

**Write it last.** Every recorded verdict advances the state revision, so a handoff written before
the final gate is stale the moment that gate lands. Re-running with the same `-Next` overwrites the
same file rather than leaving two.

**Then rebuild the document index, and commit both together** - at every boundary but one, below.
The handoff is a document under
`plan/handoffs/`, which `keel-index.ps1` indexes, so writing it leaves `reference/INDEX.md` wrong
until it is rebuilt — and in a project whose commit gate checks the index, the commit is refused
until you do. (Keel's own does, in `scripts/check-suite-docs.ps1`; not every project has one, and the
rebuild is owed either way.) "Write it last" and "rebuild after any
document write" are not two unordered obligations — they run in one order and no other:
**write → repair → rebuild → commit together.** At project creation it stops at rebuild; see the
exception below.

**`repair` is the line-ending step, and it sits there because it is itself a write.** Where the tool
that wrote a file and the project's `.gitattributes` disagree about line terminators, the fix is to
normalise the file — and a fix applied *after* the rebuild stales the `reference/INDEX.md` you just
built, so the gate refuses the commit you were about to make. **Measured** in a scratch project:
`keel-index.ps1` exits **0** on a fresh index, exits **1** after a line-ending-only
change to an indexed document — terminators altered, not one byte of content — and returns to **0**
after a rebuild. Where nothing is owed the step is a no-op and the order reads as it always did.
**Decide whether anything is owed by counting bytes, never by matching a pattern against lines**;
the recipe and its local hazards belong in the repo's own working rules, not here.

**This section is that order's only home**, and everywhere else points here for it. Two things may
still sit elsewhere, and neither is a second home: a skill may spell the steps out **for its own
case** — `keel-run-phase` does, at the `record` gate, in that gate's own nouns — and a repo's
working rules may pin **where the repair goes** without stating the rest of the sequence, which is
the one thing a reader of those rules needs. Both are *applying* this order, not declaring one, and
where any of them disagrees with this section, this section is right. What must not exist is a
second **full** statement of the sequence: two of them drift apart, and the order ends up
contradicting itself.

**The rebuild command is under "Rebuilding the index" in `keel-project-context`**, and nowhere in
this skill. `keel-index.ps1` ships in the keel-project plugin, so only that skill's text can give its
path for the copy of keel on this machine; load that skill first if this session has not.

Stage the handoff **and** the rebuilt `reference/INDEX.md` in the same commit. The checker reads the
working tree and never the git index, so a rebuild you do not stage passes the gate and commits a
stale index anyway.

**The one exception: the session that creates a project commits nothing.** At the boundary "A
project planned, nothing decomposed yet", where `keel-plan-project` ends, the order runs write ->
repair -> rebuild and stops there. That skill leaves every commit to the human, the project's first
included, so the handoff and the rebuilt `reference/INDEX.md` wait in the working tree for them.

## Must NOT

- **Do the work.** Dispatch `keel-run-phase`.
- **Skip a gate** because the change is small. Trivial means a *briefer* artifact, never no artifact.
- **Let implementation start before the plan gate's review round has closed and its verdict is
  recorded.** The plan is read by a fresh subagent, not ratified by the human — but the gate is
  still a gate.
- **Invent a phase.** The wrapper exits 94 on an undeclared phase; that is correct.
- **Infer run order from phase numbers.** It is declared data.
- **Commit, push, enact, or write to a tracker on your own initiative** — beyond what "Whether to
  ask, or to act and report" above permits you to perform and report. Everything irreversible is
  previewed in its exact final form and confirmed (charter P6).
- **Mark anything delivered that the wrapper has not recorded.** If it is not in the state file, it
  did not happen.
- **Edit `plugins/**`.** If keel is wrong, file a signal (charter P25).
