---
name: keel-tracker
description: Projects a keel project's plan onto its chosen tracker - Trello, Jira or GitHub Projects - and reads it for at-a-glance triage. Dispatched by keel-orchestrator or keel-close-workstream; the tracker a project uses is declared in its keel.json and is never guessed. The files are ALWAYS the authority and the tracker is ALWAYS a projection of them: nothing is decided on a board, and a card is never read back as truth about what a phase is or whether it is delivered. Loads the deferred MCP tools by exact name via ToolSearch before any call. EVERY write - create, move, update, archive - shows the exact final text and target list and waits for explicit confirmation; uncertainty defaults to SKIP, never CREATE. Refuses to project identifying detail out of a project whose keel.json has quarantine on. A project whose tracker is "none" has nothing to do here and that is the common case.
---

# Tracker projection

**The files are the authority. The tracker is a projection.** (charter P10)

Nothing is decided on a board. A card's title, list or description is never read back as the truth
about what a phase is, what its scope says, or whether it is delivered — those come from the spec
and from `keel-state.ps1 status`. The tracker exists for one thing: seeing where a project stands
without opening a laptop.

## Step 1 — which tracker, if any

Read `keel.json`:

```json
"tracker": { "kind": "none|trello|jira|github", "ref": "<board id / project key / project number>" }
```

**`kind: none` → there is nothing to do.** Say so in one line and stop. That is the default and the
common case; do not offer to set one up unless asked.

**`ref` is null but kind is set** → the project has chosen a tracker but not created the board yet.
Offer to create it, previewing the exact name, and write the `ref` back into `keel.json` once it
exists. Never guess a board from a name that looks right.

## Step 2 — load the tools

The MCP tools are deferred. Load them **by exact name** before any call:

| Tracker | ToolSearch query |
|---|---|
| Trello | `select:mcp__claude_ai_Trello__trelloReadBoard,mcp__claude_ai_Trello__trelloWriteCard,mcp__claude_ai_Trello__trelloReadList,mcp__claude_ai_Trello__trelloWriteList,mcp__claude_ai_Trello__trelloSearch` |
| Jira / GitHub | search by keyword; do not assume a tool name that has not appeared in a listing |

If the tools are not available — the connector is not authorised in this session — **say so and
stop**. Do not fall back to describing what you would have done as though it happened.

## Step 3 — what gets projected

Keel's tree is deeper than any tracker's model, so the projection is **lossy on purpose**:

| Keel | Trello | Jira | GitHub Projects |
|---|---|---|---|
| project | a board | a project | a project |
| epic (any depth) | a label, or nothing | an epic | a field value |
| workstream | a card | a story | an item |
| phase | a checklist item on that card | a subtask | a sub-issue or a checklist |
| goal | nothing | nothing | nothing |

**Goals are not projected.** They are cross-cutting links; flattening them onto a board turns a
coverage query into a decoration. Goal coverage is answered by `keel-state.ps1 goal-coverage`.

**Deep epic nesting flattens.** Say so when it does, rather than inventing a hierarchy the tracker
cannot hold.

## Step 4 — every write is previewed

Show the **exact final text** and the **exact destination** — board, list, position — and wait for
explicit confirmation (charter P6). A preview that summarises is not a preview.

```
CREATE card on board "Tax Returns" -> list "In flight"
  Title: W1 - 2023 bank ledger
  Desc:  Goals: G1, G2. Spec: plan/workstreams/W1_ledger.md
         Phases: W1.1 (self), W1.2 (external, waiting on Priya, review 2026-08-24)
```

**Uncertainty defaults to SKIP, never CREATE.** "I'll make these and you can delete the wrong ones"
is the failure this rule exists for.

## Quarantine

If `keel.json` has `quarantine: true`, **nothing identifying is projected**. A card may say
*"W1.1 - retrieve three missing 2023 statements"*. It may not carry account numbers, names of
individuals, amounts, or anything lifted from a quarantined document. Redaction happens as you
compose the card, not as you review it (charter P23).

A tracker is a cloud SaaS. A card cannot be unsent.

## Measured API limits

**Dated 2026-08-17. Re-check before relying on one** — this file holds slow knowledge and these move.

| Tracker | Limit that bites |
|---|---|
| Trello | Free plan: 10 boards **per Workspace** (unlimited Workspaces), unlimited cards, 250 automation runs/month. The MCP has **no comment action**, and `desc` is capped at **2048 characters** — a long spec summary will be silently truncated, so link to the file instead of pasting it. |
| Jira | Free plan: unlimited projects and issues, 10 users, 2 GB storage. Creating an issue needs the project's field metadata; discover it rather than assuming field ids. |
| GitHub Projects | 50,000 items per project. Requires the Projects toolset, which is a separate scope from repo access. |

## Reading the tracker

Reading is safe and needs no confirmation. Useful for *"what did I write on that card"* and for
spotting drift between the projection and the files.

**Report drift; do not silently fix it.** A card that disagrees with the spec is a finding: either
the projection is stale, or someone edited the board expecting it to be authoritative. Say which you
think it is and let the human decide (charter P10).

## Must not

- **Read a card as truth.** Phase state comes from `status`, scope comes from the spec.
- **Write without an exact preview and explicit confirmation** — beyond what "Whether to ask, or to
  act and report — reversibility decides" in `keel-orchestrator/SKILL.md` permits you to perform and
  report.
- **Project a quarantined project's identifying detail.**
- **Create a board, list or card the human did not ask for.**
- **Project goals.**
- **Invent hierarchy** the tracker cannot represent.
- **Claim a write happened** when the MCP tools were unavailable.
