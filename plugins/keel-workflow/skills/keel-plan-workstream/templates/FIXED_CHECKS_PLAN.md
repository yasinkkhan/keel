<!--
FIXED CHECKS - KIND PLAN. The checks of a planning phase W{{N}}.0, which plans workstream W{{N}}. Nobody
writes them: keel-run-phase copies them into the phase's plan.md and into its verifier brief, as that
phase's checks, in place of a spec's section 5, which does not exist until this phase writes it.

The eight gates run as for any phase (charter P2): the artifact each holds is in keel-run-phase,
"Before anything: what kind of phase is this?". Check 8 is answered twice: against the spec at
verify, and again after the enact step has registered the rows, in the delivery record (its second
half is post-enact).

C1 and C3 are written closed-world, as keel-plan-workstream's rule beginning "A completeness
check over a population defined by a judgement" requires. C1 grades the items listed under
section 1's Measured heading, C3 the checks in section 5. Within its list each still fails on
what its first sentence requires and is missing (a date, a command, a number, what decides a
check, a form), on a wrong figure, and on an absence found present. Anything a reader finds
beyond that - an unbacked phrase, a missing control, a statement outside the list, a form judged
weak - is noted in the verify report, answered in the delivery record, and decides nothing.

Fill {{N}}, keep the wording, and delete these comments.
-->

# Fixed checks - W{{N}}.0, planning W{{N}}

- **W{{N}}.0-C1** - Section 1's `Measured` heading names a date or a commit, and each item listed under it names the command it ran or the file it read and what that printed. A heading with no date or commit, a listed item that names no command or file or not what it printed, a figure, quotation or reading in a listed item that a reader re-takes and finds different, and an absence a listed item states that a reader finds present each fail this check. Anything else a reader would want backed - a phrase in a listed item that its command does not back, an absence stated without a positive control, a statement outside the list, true or not - is noted under the verify report's `Anything else I noticed` and answered in the phase's delivery record; it does not decide the verdict, through this check or through the rule for defects outside the check rows.
- **W{{N}}.0-C2** - Every phase row has a scope, an actor, a unique run order, and the prose order matches it.
- **W{{N}}.0-C3** - Each check in the spec's section 5 is numbered `W{{N}}.<p>-C<n>`, says what decides it, and carries one of three forms: a positive control and what it printed, the output a broken instrument prints, or the word unmeasured with a reason. A check in section 5 without a number, without what decides it, or carrying none of the three forms fails this check. A carried form a reader judges too weak is noted under the verify report's `Anything else I noticed` and answered in the phase's delivery record; it does not decide the verdict, through this check or through the rule for defects outside the check rows.
- **W{{N}}.0-C4** - Every requirement row is covered by at least one check, and every check covers a row or says it bounds the phase.
- **W{{N}}.0-C5** - Every Decision row opens with a who-decided label.
- **W{{N}}.0-C6** - The workstream claims at least one goal (a planning workstream: none), and each claimed goal exists.
- **W{{N}}.0-C7** - The spec names the next runnable phase by its declared run order, so the record gate knows which one prompt to write.
- **W{{N}}.0-C8** - The rows to register equal the spec's phase table, both ways; answered again after enact, at record (declared post-enact for its second half).
