---
name: keel-documents
description: Grounds a keel project in documents that live OUTSIDE its folder - Google Drive files, exported statements, PDFs, anything the project must account for but does not own. Dispatched by keel-orchestrator or keel-plan-workstream when a premise depends on a document nobody has read. READ-ONLY: it never writes to Drive or any external store. Redacts at EXTRACTION for a project whose keel.json has quarantine on, so an unredacted fact cannot reach a downstream artifact - the raw document stays under %USERPROFILE%\.keel\quarantine and never enters the project folder or a git repo. Loads the deferred MCP tools by exact name via ToolSearch before any call, and says plainly when a connector is unavailable rather than describing what it would have found. Every extraction records what was read AND what was not, because an inventory whose gaps are unstated reads as complete.
---

# External documents

Some of a project's most important facts live in documents it does not own: bank statements, a
signed agreement, an auditor's report, a prior year's filing. This skill reads them so the project
can be grounded in what they actually say.

**Read-only.** Nothing is ever written back to Drive or any external store.

## Step 1 — quarantine decides everything that follows

Read `keel.json` first.

### `quarantine: false`

Ordinary documents. Read them, quote what matters, cite by document name and heading.

### `quarantine: true`

**Redaction happens at extraction, not at rendering** (charter P23). This is the whole rule, and the
order matters:

```
  WRONG   read the document -> put it in the project -> redact when reporting
  RIGHT   read the document -> extract only what the project needs, already redacted
                            -> the raw document never enters the project folder
```

If redaction happens at render time, an unredacted fact already exists in a file, and files get
committed, copied and pasted. Redacting at extraction means the unredacted version never exists
downstream at all.

**Where the raw document lives:** `%USERPROFILE%\.keel\quarantine\<project>\`, outside every git
repo. If you download something, it goes there. It **never** goes in the project folder, not even
temporarily, not even in `private/`.

**What a redacted extraction looks like:**

> **Raw (stays in quarantine):** `2026-01-04  ACME PAYROLL  ****4471  3,812.55`
> **Extracted into the project:** *"12 payroll deposits in 2023, monthly, all to the joint account;
> total consistent with the T4. Source: quarantine/tax-returns/2023-statements.pdf"*

The extraction is useful, checkable, and carries no identifier. If you cannot make it useful without
the identifier, that is a finding — say so and let the human decide, rather than deciding for them.

## Step 2 — load the tools

Deferred MCP tools, loaded **by exact name**:

```
ToolSearch: select:mcp__claude_ai_Google_Drive__search_files,mcp__claude_ai_Google_Drive__read_file_content,mcp__claude_ai_Google_Drive__get_file_metadata,mcp__claude_ai_Google_Drive__list_recent_files
```

**If the connector is unavailable, say so and stop.** Do not describe what the document probably
contains. An unread document is an unknown, and recording it as an unknown is correct work.

Local files need no MCP at all — read them directly.

## Step 3 — find before you read

Searching is cheap; reading a 200-page PDF into context is not.

1. **Search by name and date range** to find candidates.
2. **Read metadata** — name, modified date, size, owner — to choose.
3. **Read the file**, and only the part you need.

For a large document, say which part you read. *"Read the 2023 summary page"* and *"read the whole
statement set"* support very different claims.

## Step 4 — record the extraction

Every extraction produces a written record, either in the phase's `grounding.md` or as a file in the
project's `reference/`:

```
Source:    <document name>, modified <date>, from <Drive folder | local path | quarantine path>
Read:      <which parts - pages, sections, sheets>
Not read:  <what you skipped, and why it does not bear on this>
Extracted: <the facts, redacted at extraction if quarantine is on>
```

**`Not read:` is not a formality.** An inventory whose gaps are unstated reads as complete, and a
gap here is a premise nobody will ever check (charter P7).

If the extraction lands in `reference/`, rebuild the index so a future session can find it, with the
command under "Rebuilding the index" in `keel-project-context` (load that skill first if this
session has not; only that skill can give the path to `keel-index.ps1` for the copy of keel on this
machine).

## Absence claims need a positive control

*"There is no 2023 vehicle expense in these statements"* is a claim about a document, and it needs
the same discipline as any other absence: show that the same search **does** find a category you
know is present. Without that, "not found" may only mean "not searched properly" — a scanned PDF
with no text layer returns nothing for every query.

## Must not

- **Write to Drive or any external store.** This skill reads.
- **Put a quarantined raw document in the project folder**, temporarily or otherwise.
- **Redact at render time.** Extraction is the only correct moment.
- **Read a whole document when a section answers the question.**
- **Describe a document you could not open.** Say it is unread.
- **Claim an absence without a positive control.**
- **Quote identifiers out of a quarantined project** into chat, a signal, a tracker card, or a
  committed file.
