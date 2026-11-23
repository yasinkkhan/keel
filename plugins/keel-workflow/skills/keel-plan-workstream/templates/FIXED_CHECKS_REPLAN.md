<!--
FIXED CHECKS - KIND REPLAN. The checks of a re-plan phase W{{N}}.{{p}}, which re-plans workstream
W{{N}} while every other unfinished phase of it is held. Nobody writes them: keel-run-phase copies them
into the phase's plan.md and into its verifier brief, as that phase's checks. The procedure the gates
follow is keel-plan-workstream's amend mode.

The eight gates run as for any phase (charter P2). Check 5 is answered twice: against the amended
spec at verify, and again after the enact step has made the state changes, in the delivery record
(its second half is post-enact).

Fill {{N}} and {{p}}, keep the wording, and delete these comments.
-->

# Fixed checks - W{{N}}.{{p}}, re-planning W{{N}}

- **W{{N}}.{{p}}-C1** - every amendment is an appended, dated, labelled row and nothing above it is rewritten (the spec's diff against the commit before the phase adds lines only, outside the phase table);
- **W{{N}}.{{p}}-C2** - no delivered phase's plan text or delivery record changes;
- **W{{N}}.{{p}}-C3** - every check written from an amended decision has its amended text recorded by check id;
- **W{{N}}.{{p}}-C4** - each held phase is named with the stage it resumes at, and no held phase's prompt is rewritten (the amended spec outranks it);
- **W{{N}}.{{p}}-C5** - the rows to revise equal the amended table, both ways (post-enact half answered at record);
- **W{{N}}.{{p}}-C6** - run orders stay unique;
- **W{{N}}.{{p}}-C7** - the next runnable phase after the re-plan is named by declared run order.
