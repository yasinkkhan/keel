<!--
FIXED CHECKS - KIND PLAN. The checks of a planning phase W{{N}}.0, which plans workstream W{{N}}. Nobody
writes them: keel-run-phase copies them into the phase's plan.md and into its verifier brief, as that
phase's checks, in place of a spec's section 5, which does not exist until this phase writes it.

The eight gates run as for any phase (charter P2): the artifact each holds is in keel-run-phase,
"Before anything: what kind of phase is this?". Check 8 is answered twice: against the spec at
verify, and again after the enact step has registered the rows, in the delivery record (its second
half is post-enact).

Fill {{N}}, keep the wording, and delete these comments.
-->

# Fixed checks - W{{N}}.0, planning W{{N}}

- **W{{N}}.0-C1** - Every factual premise in section 1 carries the command that measured it and its result, at a named commit or date; every absence claim carries a positive control.
- **W{{N}}.0-C2** - Every phase row has a scope, an actor, a unique run order, and the prose order matches it.
- **W{{N}}.0-C3** - Every check is numbered, says what decides it, and states how it can fail (a positive control, a broken-instrument output, or the word unmeasured with a reason).
- **W{{N}}.0-C4** - Every requirement row is covered by at least one check, and every check covers a row or says it bounds the phase.
- **W{{N}}.0-C5** - Every Decision row opens with a who-decided label.
- **W{{N}}.0-C6** - The workstream claims at least one goal (a planning workstream: none), and each claimed goal exists.
- **W{{N}}.0-C7** - The spec names the next runnable phase by its declared run order, so the record gate knows which one prompt to write.
- **W{{N}}.0-C8** - The rows to register equal the spec's phase table, both ways; answered again after enact, at record (declared post-enact for its second half).
