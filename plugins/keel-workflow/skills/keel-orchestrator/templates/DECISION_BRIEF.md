<!--
DECISION BRIEF TEMPLATE - fill this BEFORE rendering any question that reaches the operator.

WHAT IT IS. A shape a question is built from. It is NOT a checklist to grade a question against
afterwards: the five obligations already exist as prose, in the section "Asking the human
- the question must be answerable without keel's vocabulary" in keel-orchestrator/SKILL.md, and a
second statement of them here would duplicate a fact that already has a home. This file states no
obligation. It gives each one a slot, and section 6 is what the slots produce.

WHY IT EXISTS. Charter P13's ladder is nudge -> skill prose -> wrapper exit code -> hook, and a
rule climbs a rung only after failing at its current one with the failure cited. The four
obligations that existed when this file was written lived at rung two and were observed failing
there: a phase put two planning options to the operator in keel's own vocabulary, and the operator
had to ask twice for them in plain language. This is the rung above - still prose, but a shape
rather than a rule.

WHY THE SECTIONS ARE IN THIS ORDER, which is NOT the obligations' numbering. Obligation 2 says the
stake leads, so the stake is section 1. Obligation 1 is section 2 because the expansions have to
exist before the options can be written in them. Obligation 5 is section 3 for the same reason one
step further on: the recap has to be WRITTEN in those expansions, and it has to come before the
options it exists to make judgeable. Obligation 3 is section 4. Obligation 4 is a property of each
option, so it lives inside section 5 rather than in a section of its own - a separate "claims"
section would be a checklist, which is the one thing this file must not be. Do not "fix" the order.

WHY THIS FILE DOES NOT CARRY THE SUBAGENT PROHIBITION. Each of the three files in
keel-run-phase/templates/ forbids its reader to load or invoke a keel skill, because each becomes a
prompt handed to a fresh subagent. This one is filled by the orchestrator and read by the OPERATOR.
There is no subagent to prohibit anything, and the absence is deliberate rather than an omission -
said here because the filename carries the word "brief" and the three files that share it are all
subagent prompts.

NOTHING ENFORCES THIS FILE. No exit code reads it and no hook sees it. Under P13 the rung above
stays out of reach until this one is observed failing too.

Fill every {{...}} and delete these comments.
-->

# {{the decision, in one line, in the operator's own words}}

## 1. AT STAKE - one sentence, before the options

<!--
Obligation 2. The reader needs a frame to judge the options against; without one, correct options
are still unanswerable. Write the sentence itself, exactly as they will read it - not a topic, and
not a restatement of the title. It says what is different for them depending on which they pick.

A question whose first words are the first option has no frame. So does one whose header is a bare
identifier.
-->

{{one sentence: what changes for them, depending on which option they pick}}

## 2. PLAIN WORDS - every identifier, expanded here and used expanded below

<!--
Obligation 1. Signal ids, charter principle numbers, decision ids, workstream and phase ids, gate
names, exit codes - every one of them is jargon to the person being asked, and an answer to a
question written in it is not consent to anything in particular.

The right-hand column is the text that ACTUALLY APPEARS in section 6. Not a gloss for you; the
replacement. Expansion belongs inside the question, never in a linked file and never earlier in the
conversation.

An identifier with no right-hand column does not appear in the question at all.
-->

| identifier | the words that replace it in the question |
|---|---|
| {{S0007}} | {{...}} |
| {{P25}} | {{...}} |
| {{...}} | {{...}} |

## 3. WHAT THIS IS ABOUT - the work they did not watch

<!--
Obligation 5. They did not do this work and have usually not read the records the question rests on.
What is missing at that point is not a WORD - obligations 1 and 2 already handle words - it is the
frame the words are about. A question can satisfy every other section here and still be
unanswerable.

Three things, in plain language, in this order: what this project is FOR, what was being tried,
and what came back. Written in the expansions from section 2, which is why this section sits after
it. It goes BEFORE the options in section 6, never inside them.

Why: a question once satisfied all four of the other obligations, and the operator replied that
they did not understand and asked to be assumed confused about what was currently happening. The
second attempt supplied exactly the three things below and was answered in one round.

Skip it only when the question rests on nothing they have not seen - a choice about the next hour's
work, made from a conversation they are in. If you are unsure whether they have read something, they
have not.

Two further lines follow the three, each answered or marked as not applying: the earlier decision
this question touches, and, for a question about what a table, column, figure or file will hold, a
worked instance. Both are covered by obligation 5; the earlier-decision
line is shaped by "An earlier decision is a tradeoff to show, not a rule to enforce" in
keel-orchestrator/SKILL.md.
-->

{{what the project is for, in one or two sentences}}

{{what was tried, and by whom - the work this question is downstream of}}

{{what came back - the finding, the result, the thing that makes a decision necessary now}}

{{the earlier decision this touches - what was decided, who decided it, why, and what keeping it
costs now - or `none`}}

{{where the decision is about what a table, column, figure or file will hold: one or two of their own
real instances worked through - in conversation only if the project has quarantine on - or `not a
data-shape question`}}

## 4. WHAT CANNOT BE UNDONE

<!--
Obligation 3. Irreversibility is named in the words they are choosing between, not only in a preview
attached to the question. "Close the issue and resolve the signal?" does not say that the call can
never be made again.

The two values below already exist - they are the answers collected at the enact gate before the
act (charter P21). Copy them; do not re-derive them, and do not soften them because the softer
answer is the one that avoids asking.

If nothing here is irreversible, say so and say how each option is undone. That is a real answer.
-->

**Reversible:** {{none / partial / full}} · **Observable:** {{yes / no}}

{{the sentence naming what cannot be taken back, in the words they are choosing between}}

## 5. THE OPTIONS - each claim measured, or labelled unmeasured

<!--
Obligation 4. A claim about what a mechanism does, what a setting enforces, or what a check would
catch is not part of the rendering - it is the REASON they pick that option, and it is the one part
of the question they cannot check for themselves. Run it, or write UNMEASURED in the option's own words.
An option honestly weakened is the correct outcome, and a claim you decline to check is not a
selling point you are entitled to keep.

This obligation carries its own cited failure: an option was once offered as a "real,
mechanical switch" with "the strongest guarantee" of three, chosen on that basis, and measured only
afterwards - the guarantee did not exist.

Two to four options. Each Claims entry carries either the command AND ITS ACTUAL OUTPUT, or the
single word UNMEASURED. Nothing in between.
-->

### Option A - {{label, in plain words}}

{{what happens if they pick this, in one or two sentences}}

**Claims:**
- {{the claim, worded as it appears in the question}} -> {{the command and its actual output, or UNMEASURED}}
- {{...}} -> {{...}}

**Costs:** {{what it takes, or what it gives up}}

### Option B - {{label, in plain words}}

{{what happens if they pick this, in one or two sentences}}

**Claims:**
- {{the claim, worded as it appears in the question}} -> {{the command and its actual output, or UNMEASURED}}

**Costs:** {{what it takes, or what it gives up}}

**Recommendation:** {{which one, and the single reason}}

<!--
The recommendation stays. keel-orchestrator/SKILL.md is explicit that the question still carries
one, and that a convention turning questions open-ended "would trade one defect for another and
leave the human with more to read and less to go on". It is a bold label inside this section rather
than a heading of its own, because it is a statement about the options.
-->

## 6. THE QUESTION, ASSEMBLED

<!--
The literal text put to the operator, built from 1 to 5 above. This is the artifact the five
sections exist to produce, and it is what makes this file a shape rather than a list.

Order: the stake sentence, then the recap from section 3, then irreversibility if section 4 named
any, then the options with their claims, then the recommendation. Every identifier appearing here
comes from section 2's right-hand column.

Then ask it - as plain text in your reply, the recommended option first, in the form the section
"Asking the human" in keel-orchestrator/SKILL.md defines.

Fill the shape below. It is this order rendered: the layout clause in that same section states the
contract, and the shape is what meeting it looks like rather than a second statement of it
(charter P10). The clause is where the marks and the blank lines are specified; read it there.
-->

```
# 🔶 {{the decision, in one line}}

**{{the stake, in one sentence}}**

{{the recap - what the work was, in plain language, for a reader who did not watch it}}

⚠️ **{{what cannot be undone}}** - or: Nothing here is irreversible.

## The options

> ✅ **{{A - the recommended option}}**
> {{what it means, each claim measured or labelled unmeasured}}

**{{B - the next option}}**
{{what it means}}

**{{C - the next option}}**
{{what it means}}

## Why I recommend {{A}}

{{one short paragraph}}

**Reply however you like** - pick one, name a different option, or ask about any of them.
```

## Do NOT

- Do not ship this brief with a `{{...}}` left in it. An unfilled slot is a question with a hole in
  it, and the hole is always in the part the reader most needed.
- Do not put an identifier in section 6 that section 2 does not expand. That is the failure this
  whole file exists for.
- Do not write a claim in section 5 with neither a measurement nor the word UNMEASURED beside it.
  Silence there reads as measured.
- Do not answer section 3 with the phase id and the document paths. Those are identifiers, and
  section 2 is where identifiers get replaced. They need what the work WAS.
- Do not restate the five obligations anywhere in a filled copy of this file. They live in
  keel-orchestrator/SKILL.md and this file composes from them; two homes for one fact is charter
  P10's violation, and turning this into a list of assertions to sign off afterwards is the one way
  it stops being a shape.
- Do not use this to decide WHETHER to ask. That is settled elsewhere, by reversibility: an act
  whose reversibility answer is `none` is always asked about. This file governs only how the
  question is written once it is owed.
