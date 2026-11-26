<!--
TRANSCRIPT BRIEF TEMPLATE - the prompt for a FRESH subagent that reads a meeting transcript against
a fixed list of sources, for a re-plan that amends the plan from a meeting.

Why a helper (charter P5): the session that will judge the reading should not also produce it, and
the searches behind every cell happen in the child's context and die there.

The sources table is filled BEFORE dispatch, by the session, as "When the change comes from a
meeting" in keel-plan-workstream/SKILL.md says: a source left off it is a source nobody checks.

Fill every {{...}} and delete these comments. A brief with a gap is a brief that gets a guess.
-->

You are reading one meeting transcript and checking what was said in it against a fixed list of
sources. Report what each source says about each item. Do not decide what the plan should become.

## The transcript

**Path:** `{{absolute path to the transcript, in the meeting\ folder or the quarantine store}}`
**Meeting date:** {{yyyy-MM-dd}}

## The sources

Your reading has one column per source, in this order:

| Source | Kind | Where it is, or how to read it |
|---|---|---|
| {{name}} | code | `{{absolute path to the repo or the files}}` |
| {{name}} | tickets | `{{absolute path to an export}}`, or the read-only command `{{command}}` |
| {{name}} | records | `{{absolute paths to the spec, the charter and goals, the delivery records}}` |

## The plan items

{{The items a row may touch: workstream and phase ids with their titles, goal ids with their text,
and any date or figure the plan names - or `none listed`.}}

## What to produce

Write **one row for every decision and every statement of fact said in the meeting**, not only the
ones a decision rests on. A statement of fact is anything said as true about the work, the product,
the code, a date or a cost. When you are unsure whether something counts, give it a row.

Each row has these columns:

- **Timestamp** - the transcript's timestamp for the item, as the transcript writes it.
- **Kind** - `decision` or `statement of fact`.
- **What it says** - one sentence, close to the transcript's words.
- **Speaker** - who said it, as the transcript names them. Name a speaker here and nowhere else:
  this reading stays on this machine.
- **Plan item** - the item from the list above that it touches, or `none`.
- **One cell per source**, in the sources table's order. Begin each cell with exactly one of:
  - `agrees` - then the words you read that agree, quoted, and where;
  - `contradicts: "<quote>" (<where>)` - the source's own words copied exactly, and the file and
    heading, or the ticket's id;
  - `says nothing` - then the search you ran or the files you read, so it can be re-run;
  - `could not check: <why>` - the source could not be read, and why.

Name in every cell what you read or the search you ran. Leave no cell blank: a source you did not get
to is `could not check`, with the reason.

Write the reading to `{{absolute path to reading.md, in the same meeting\ folder or quarantine
store as the transcript}}` as one markdown table with the columns above, in that order, then a line
`Rows: <n>`.

## What "says nothing" requires

`says nothing` is a claim of absence, so give it a positive control: search the same source by the
same means for a term you know is there, and write that search and what it found into the cell
after your own. Without one, "says nothing" may only mean "not searched".

## Return to the caller

The reading's path, its number of rows, and the timestamp of each row holding a `contradicts` cell.
Not the reading itself, and not your searches.

## Do NOT

- **Do NOT load or invoke any `keel-*` skill.** You are not running the workflow; you are reading a
  transcript for a session that is.
- Do not edit, create or delete anything. This is read-only. The exceptions are the reading's path
  above and a scratch file in the scratch folder
  `{{%USERPROFILE%\.keel\projects\<slug>\phases\W<n>.<p>\scratch\}}`, which is on this machine only,
  never under a project's `progress\` folder.
- Do not write to `%USERPROFILE%\.keel\`, except in those two places, or run `keel-state.ps1`.
- The session that dispatched you compares the project folder, every repo it uses and the top
  level of the phase folder before and after you run, and a file you write there, other than your
  reading, can be recorded against you by name.
- Do not propose changes to the plan, rank the items or say which matter. The session puts each one
  to the operator.
- Do not write a speaker's name anywhere but the reading's Speaker column, your return included.
- Do not treat a ticket as the truth about the plan. Report what it says, as for any other source.
- Do not include identifying personal information in your return if the project has quarantine on -
  describe what you found without reproducing it. In such a project the transcript and the reading
  are in the quarantine store, every control you run uses synthetic values, never a real
  identifier, account number, address or name, and no real identifying value is written anywhere
  outside the quarantine, any scratch file included.
