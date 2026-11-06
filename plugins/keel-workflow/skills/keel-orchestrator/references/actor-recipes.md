# Actor recipes

A phase's **actor** selects two things and *only* two things: **what evidence a check accepts**, and
**what "verify independently" means when the hands were not Claude's**.

**It must never add, remove, or reorder a pipeline stage** (charter P18). Every phase runs
`ground -> investigate -> plan -> implement -> verify -> human -> enact -> record`. A tax filing's
checks are still artifact-plus-verdict — the *shape* is identical, only the recipe differs.

If you find yourself writing "skip verify for this actor", stop. That is the pipeline forking into
three, two of which are exercised too rarely for their bugs to surface anywhere but in front of a
deadline.

> **Project specifics are NOT restated here.** Which repos exist, which tracker is in use, whether
> there is a quarantine — all of that lives in the project's own `keel.json` and `CHARTER.md`.
> This file names *roles*; resolve them against the project at use time (charter P9).

---

## The three actors

### `agent` — Claude does it

**Evidence a check accepts:** command output pasted verbatim; a patch; a headless render; a live
query. Never a summary of output, and never "I confirmed that...".

**Implement artifact:** one `changes-<repo>.patch` per declared repo. The wrapper refuses the gate
if a declared repo has no patch (exit 96).

**A phase that declares no repos may use `act-log.md` instead** — the same artifact the other two
actors use, carrying `Done by:` and `Done on:`. An agent phase whose legitimate output is
*documents* is not an edge case: in research, analysis and bookkeeping projects it is most of them,
and without this route such a phase would have no satisfiable artifact at all. Either route passes when
no repo is declared. Declaring a repo is still a promise: from then on the patch is the only route.

**The multi-repo trap.** A phase touching three repos commits three times, and the failure is that
two land and the third does not — after which the delivery record cites a hash that does not exist,
and the one grep that indexes everything returns nothing for that repo. Three things defend it:

- `add-repo` registers every repo once, with its **branch**, so the per-repo differences that cause
  this are written down rather than remembered. Repos on the same machine do not all track `main`.
- `keel-state.ps1 repos` re-measures before you rely on any of them — missing path, not a repo,
  branch mismatch, detached HEAD.
- The `implement` gate demands a patch per declared repo, and `record` demands an evidence
  reference per declared repo. Declaring a repo is a promise the wrapper holds you to.

**A repo may be external**: declared with a path outside the project because it already exists
elsewhere or is shared between projects. Keel references it; it does not own it, never moves it, and writes to it
only behind the same preview as anything else outward-facing.

**Verify:** a **fresh** subagent that never saw the change being made (charter P5). It re-runs every
`W<n>.<p>-C<n>` check itself and returns the results table.

**The trap:** claiming an absence without a positive control. Every "it's not there" needs a second
query proving the instrument would have found it if it were (charter P7).

---

### `self` — you do it

Logging into a portal, signing something, phoning someone, moving money, taking a photograph of a
receipt. Claude cannot do any of it and must not imply that it did.

**Evidence a check accepts:** an artifact **you point at**, placed in the phase directory or cited
by an identifier that can be looked up later —

- a confirmation or reference number
- a filed document, or a path to one in the quarantine
- a dated screenshot in the phase directory
- a transaction hash
- an email whose date and sender are recorded

**Implement artifact:** `act-log.md`, carrying `Done by:` and `Done on:` lines. The wrapper refuses
without both (exit 96), because "it's done" with no date is unauditable three weeks later.

**Verify:** the fresh subagent cannot re-run the act. It checks the **evidence** instead: that the
cited artifact exists, that it says what the check claims, and that its date is consistent. A check
whose evidence cannot be inspected is recorded `INCONCLUSIVE`, never `PASS`.

**The trap:** the phase drifts to "done" in conversation without evidence, because you know you did
it. You will not know in November. Record the reference number.

---

### `external` — someone else does it

An accountant, an auditor, a lawyer, an exchange, a registrar, a bank. You are neither the actor nor
in control of the schedule.

**Evidence a check accepts:** the **received deliverable itself**, plus who sent it and when. A
report, a signed document, an approval email, a filing acknowledgement.

**Implement artifact:** `act-log.md` with `Done by:` naming the third party and `Done on:` dating
receipt — not the date you asked.

**Verify:** the fresh subagent inspects the deliverable against the check. "The auditor said it was
fine" is not evidence; the auditor's report is.

**Pairs with `waiting`.** An external phase spends most of its life in `waiting`, and the wrapper
demands both who and a review date:

```
keel-state.ps1 set-waiting -Phase W<n>.<p> -WaitingOn "Sarah at Fenwick (audit report)" -ReviewOn 2026-09-08
```

**The trap:** an external phase that quietly sits for six weeks because nothing chased it. The
review date exists so `status` can print `CHASE:` — read that line.

---

## Verification recipes by surface

**These are dated pointers, not guarantees.** Confirm any command against the project's own config
before relying on it — this file holds slow knowledge, and a build command moves faster than it
looks.

| Surface | Recipe | Watch out for |
|---|---|---|
| A code repo under `repos/` | Whatever that repo declares: typecheck, unit tests, a build. Read its `package.json` or equivalent rather than assuming. | A repo with no harness is not a repo that needs one inventing for a small change. Say what you could not run. |
| Anything deployed | A probe that reports the **running** commit or version. | A push is not a deploy landing. |
| A document you produced | Diff against the previous version, and check the specific claim the phase changed. | "It reads better" is not a check. Name the observable. |
| A filing or submission | The receiving system's own confirmation: reference number, acknowledgement email, portal status. | A submitted form is not an accepted one. These are different checks. |
| An on-chain action | Transaction hash, confirmed, read back from an explorer or node. | A broadcast transaction is not a confirmed one, and a confirmed one is not a *correct* one. |
| Money moved | The statement line, not the transfer screen. | A pending transfer can still fail or be reversed. |
| A third party's work | The deliverable, dated, from a named sender. | Verbal assurance. A meeting is not an artifact. |

## Irreversibility, by actor

The `enact` gate needs `-Reversible` and `-Observable` for every actor, but the answers cluster:

| Actor | Typical enactment | Usually |
|---|---|---|
| `agent` | a push, a deploy, a migration | `partial` / observable, if a probe exists |
| `self` | filing, signing, sending funds | **`none`** / observable only once a confirmation returns |
| `external` | authorising a third party to act | `none` / often **not** observable until they report |

The `self` row is why this gate exists. Answer it for the act in front of you — never from what a
similar act was last time.

**These two answers also decide whether the human is asked at all**, not only what the record says —
see "Whether to ask, or to act and report — reversibility decides" in `keel-orchestrator/SKILL.md`.
