# Getting started with keel

This guide takes you from nothing installed to a first project, and answers the questions people
ask before they trust a tool with their work. The [README](README.md) has the reference material:
the requirements table, the exact install and update commands, and the plugin inventory.

## What keel is, and whether it is for you

keel is a set of Claude Code plugins for planning and running long projects, software or not: a
product, a tax return, a house sale. It keeps the plan in files inside the project's folder and the
progress in a state file on your machine, so the work survives new sessions, long conversations
being summarised, and months away from it. Claude reads both at the start of every session and picks
up where the last one stopped.

**New to Claude Code?** It is Anthropic's tool for working with Claude from a terminal: you start it
by typing `claude` in a terminal opened in a folder. Install it and sign in by following Anthropic's
Claude Code documentation before going further; this guide assumes it works. Two Claude Code words
appear below: a **skill** is a set of instructions Claude loads when a request matches it, and a
**subagent** is a separate Claude instance a session starts for one job, such as checking work it did
not do itself.

It breaks a project into four kinds of thing:

- **goals**, the states of the world the project is for;
- **epics**, for work too big to plan in one go, holding other epics and workstreams;
- **workstreams**, one coherent piece of work, each claiming at least one goal;
- **phases**, one sitting's work inside a workstream.

Every phase passes the same eight gates, and each gate leaves a written record. A phase's work is
checked by a fresh Claude subagent that did not do it, and you approve the result before anything
irreversible happens.

**It suits you if** you use Claude Code on Windows, you run work that spans many sessions, and you
want a plan that is kept in files and checked rather than remembered. **It is not** a team
project-management tool: there are no shared boards, no user roles and no server. It runs for one
person, on one machine.

## Before you install

- **Windows.** Mac and Linux are not supported. keel keeps its state under `%USERPROFILE%\.keel`,
  where `%USERPROFILE%` is your Windows user folder, usually `C:\Users\<your user name>`.
- **Windows PowerShell 5.1**, which comes with Windows. Every keel script runs in it, as
  `powershell.exe`; PowerShell 7 (`pwsh`) is not what they are written for.
- **Claude Code.** keel is a set of Claude Code plugins, and its skills run inside a Claude Code
  session.
- **`git`**, to install keel, which is cloned from GitHub, and for any project that uses git.
- **The GitHub CLI, `gh`, signed in to GitHub**, only if you want to send reports about keel to
  GitHub (see [What leaves your machine](#what-leaves-your-machine)). Nothing else uses it.
- **Optional: a connector in Claude Code** (an MCP server), only if you want a tracker board or want
  keel to read Google Drive documents. keel installs none; set up the one you need in Claude Code
  first.

The README's [Requirements](README.md#requirements) table has the same list in more detail. If `git`
or `gh` is missing, the command that needs it says so.

## Install

In a terminal such as PowerShell (the blocks in this guide are marked `bash`, but the commands are
the same in PowerShell):

```bash
claude plugin marketplace add yasinkkhan/keel#release
claude plugin install keel-workflow@keel
claude plugin install keel-project@keel
claude plugin install keel-surfaces@keel
```

The first command adds keel's marketplace (the catalogue Claude Code installs plugins from),
following its `release` branch, which moves only when a
new version is released. The other three install keel's plugins. Then start a new Claude Code
session: close any session that is open and type `claude` again, because skills load once, when a
session starts.

To check it worked, run `claude plugin list`. It lists the three plugins, each with a version, and
`Status: ✔ enabled`.

## Your first project

A walk-through, from nothing.

1. **Make an empty folder for the project**, anywhere you like (a `Projects` folder in your user
   folder works well), named the way you want the project called, in lowercase with hyphens: for
   example `tax-returns`. The name becomes the project's permanent identity in keel's state, so choose
   it once. Keep each project in its own folder, side by side with any others. keel refuses to create
   a project inside another project's folder.
2. **Open Claude Code in that folder**: open a terminal there and type `claude`. Then say what the
   project is, in your own words: *"I want to start a new keel project here: sort out my tax returns
   for the last three years."* You do not need to name a skill. keel's entry skill, `using-keel`,
   runs first on any request, finds no project here, and hands over to the skill that creates one.
3. **Answer three questions**, asked one at a time, each with a recommendation you can take or argue
   with: whether the folder is a git repository, whether to use a tracker, and whether the project
   holds sensitive material. They are explained in the next section.
4. **Say where the project goes.** keel never guesses a location. If your request said the project
   goes here, as the example above does, that is your answer, and the preview in the next step shows
   this folder. Otherwise keel asks, and you answer that it goes in this folder.
5. **Check the preview.** keel shows the exact folder path and the exact `keel.json` it will write,
   and waits for you to say yes.
6. **Write the charter with it.** keel asks four things: what "done" means for this project; who
   benefits, and how you will know they have; what would make abandoning it the right call; and what
   is out of scope. It may also ask a few facts for the charter's other sections, such as what you
   already have and what you do not know yet. It writes the answers into `CHARTER.md`.
7. **Agree three to five goals**, each written as a state of the world ("all three returns filed and
   accepted"), not as a task.

Then it stops. The first session creates the project and its goals and nothing more: no plan of the
work yet, and no commit, which is left to you. keel writes `keel.json`, `CHARTER.md` and the folders
`plan\`, `record\` and `reference\` (plus `repos\` if the project produces code, and `private\`,
ignored by git, if you chose git), and a short handoff note saying what the next session should do.

**Next time**, open Claude Code in the same folder and ask *"what's next?"*. keel reads its state and
the handoff and proposes the next step, usually breaking the goals into workstreams. From then on
every session starts the same way.

## The three choices a project makes

They are asked once, when the project is created, and stored in its `keel.json`. Every later session
reads them before doing anything else.

- **git** (recommended: yes). Whether the project folder is a git repository. With git, keel runs
  `git init`, and later reads branches and unpushed commits and records what each check examined.
  Without it, keel makes no git calls for the project and committing is never a step.
- **tracker**: `none`, `trello`, `jira` or `github` (recommended: `none` for a first project). A
  tracker is a copy of the plan on a board you can glance at from a phone. The files stay the
  authority, so keel never reads the board back as truth. With `none` there is nothing to update. To
  use one, the matching connector must be set up in Claude Code; this has not been tested with
  anyone's accounts but the maintainer's.
- **quarantine** (recommended: yes if in doubt). Whether the project carries sensitive material:
  financial documents, government identifiers, health information, keys, anything about a named third
  party. With it, keel creates `%USERPROFILE%\.keel\quarantine\<project>\` for that material, outside
  every repository, and works to remove identifying detail at the moment a fact is read rather than
  later. That does not keep the material from the model: Claude reads it in order to remove the
  detail, and keel installs no hook that could act first. It also limits reports about keel: from
  such a project, a report's evidence must be one line of at most 240 characters, a path and a short
  note, and keel refuses anything longer, which is what pasted content usually looks like. A wrong
  "no" cannot be undone once something sensitive has been committed; a wrong "yes" costs an unused
  folder.

## What happens in a phase

Every phase runs the same eight gates, in order:

1. **ground**: re-measure what the phase depends on, since the plan was written.
2. **investigate**: settle the facts the plan needs. Fresh subagents answer factual questions.
3. **plan**: write exactly what will change. A fresh subagent reads the plan and sends back problems.
4. **implement**: make the change, or record what you or a third party did.
5. **verify**: a fresh subagent that never saw the work runs every check.
6. **human**: you approve or reject.
7. **enact**: the outward act, such as a commit, a push, a filing or a payment.
8. **record**: the delivery record, and the next phase's brief.

So fresh subagents, ones that did not do the work, take part at three gates: advisors answer
factual questions at investigate, when there are any; a reviewer reads the plan; and a verifier
runs the checks.

A phase's **actor** is `agent` (Claude does the work), `self` (you do it and Claude records and
checks it) or `external` (an accountant, an exchange, a lawyer). The actor changes what evidence a
check accepts, never which gates run.

**What you are asked:**

- When a new piece of work starts: whether it is a quick one-sitting job ("express": one phase, no
  workstream document in the project folder, the same eight gates) or a full workstream with several phases. keel
  suggests one.
- For a full workstream: to approve its written plan, and to confirm the phases it registers.
- During a phase: only questions about scope, cost, risk, anything irreversible, anything involving
  a person, or an earlier decision the work would go against. keel answers factual questions itself
  and lists every one it answered for you at the human gate.
- At the human gate: the change itself, the verifier's report including every check it could not
  run, and that list of answered questions. You approve or reject.
- Before the outward act, depending on whether it can be undone. Anything that cannot, such as a
  filed return or a sent payment, is shown to you exactly and waits for your yes, every time. An act
  that can be undone and observed, inside the change you approved, such as a commit or a push to
  your own repository, is done and reported to you. To be asked before every act instead, put
  `"confirmEveryAct": true` in the project's `keel.json`. Only the skills' instructions honour that
  setting; nothing in the code checks it.

**When it goes round in circles:** a failed check, a rejected plan or a rejection at the human gate
starts another round. A phase can go round three times; asked for a fourth, keel stops and puts
every round's findings to you. Only you can grant more rounds.

## Where keel keeps things

**On your machine, in `%USERPROFILE%\.keel\`**, outside every repository and never committed:

| Path | Holds |
|---|---|
| `projects\<project>\state.json` | the project's state: goals, workstreams, phases, verdicts. Written only by keel's state script, `keel-state.ps1`. Never edit it by hand. |
| `projects\<project>\phases\<phase>\` | each gate's record: `grounding.md`, `plan.md`, `verify-report.md` and so on |
| `signals\` | reports about keel itself, one file each (see [Reporting a problem](#reporting-a-problem-or-suggesting-a-change)) |
| `signals-target.txt` | where reports are sent, if you have chosen anywhere |
| `quarantine\<project>\` | sensitive material, for projects that chose quarantine |

**In your project folder**, as the work goes on:

| Path | Holds |
|---|---|
| `keel.json` | the project's three choices, and the keel version it was planned under |
| `CHARTER.md` | what done means, why it is worth doing, scope, goals |
| `plan\epics\`, `plan\workstreams\` | the written plans |
| `plan\prompts\` | the brief for the next phase, written for a fresh session |
| `plan\handoffs\` | the note left for the next session when there is no brief (in the quarantine folder instead, for a quarantined project) |
| `record\` | delivery records and other results |
| `reference\` | project knowledge, and `INDEX.md`, a generated index of every document's headings |
| `repos\` | the code the project produces, only if it produces any |
| `private\` | scratch files, ignored by git, only if you chose git (sensitive material goes in the quarantine folder instead) |

Nothing here syncs between machines. keel's state is per machine.

## What leaves your machine

Like any Claude Code session, what the session reads is sent to the model. keel adds the following,
and nothing else:

- **Reports about keel, sent as GitHub issues**, only after you choose a destination. `signals-push`
  creates the issues, `adopt-signal` reads one, and `resolve-signal -CloseIssue` comments on one and
  closes it. With no destination chosen nothing is sent: `signals-push` and `adopt-signal` refuse,
  and `resolve-signal -CloseIssue` records the resolution on your machine and leaves the issue
  alone. keel never works out a destination from your repository's `origin`. `signals-push` on its
  own only prints the exact title and body of each issue; it sends only when run again with
  `-Apply`. These calls use `gh`.
- **A read of your project's own git remote.** When `status`, the state script's summary of the
  project, runs in a project with git (Claude runs it before any keel work in a session), it asks the
  project's `origin` which commits it holds, to warn you about work that exists only on this machine.
  It sends nothing of the project's content. A project without git makes no such call.
- **Tracker updates**, if the project chose a tracker. Every card written is shown to you exactly
  first, and keel waits for your yes.
- **Commits and pushes of your project's repositories**, at a phase's enact gate, under the rule in
  [What happens in a phase](#what-happens-in-a-phase).
- **Reads of documents in Google Drive**, if you ask `keel-documents` to read one. It writes nothing
  back.

To stop every outward call keel's state script makes (the issue calls and the remote read), set the
environment variable `KEEL_OUTWARD=block` before you start Claude Code: in PowerShell,
`$env:KEEL_OUTWARD = 'block'`, then `claude` in the same window. `status` then says the remote read
was blocked. To keep it on in every session, add it to Claude Code's user settings file,
`%USERPROFILE%\.claude\settings.json`, as `"env": {"KEEL_OUTWARD": "block"}` beside the keys already
there. The other three have no switch: each tracker write is shown to you first, commits and
pushes follow the rule in [What happens in a phase](#what-happens-in-a-phase) (set
`confirmEveryAct` to be asked before each one), and Drive is read only when you ask.

keel's plugins install no hooks, so no keel code runs in a session until one of its skills is used.
Their descriptions are loaded into every session, which is how Claude knows when to use them. The
hooks the README and `CONTRIBUTING.md` mention belong to keel's own repository and run only for
someone working on keel itself.

## Updating and removing keel

**To update**, run:

```bash
claude plugin marketplace update keel
claude plugin update keel-workflow@keel
claude plugin update keel-project@keel
claude plugin update keel-surfaces@keel
```

The first command fetches the newest release; each `plugin update` installs it, or says the plugin
is already at the latest version. Then start a new session. A project planned under an older version
is told so by `status`, and keel checks what changed before carrying on.

**To remove it**, run:

```bash
claude plugin uninstall keel-workflow@keel
claude plugin uninstall keel-project@keel
claude plugin uninstall keel-surfaces@keel
claude plugin marketplace remove keel
```

Afterwards `claude plugin list` prints `No plugins installed.` if keel's were the only plugins, and
otherwise no longer lists keel's. Claude Code keeps a copy of each removed plugin's files in its
plugin cache folder, `%USERPROFILE%\.claude\plugins\cache\keel\`, marked as orphaned. It holds keel's
plugin files only, none of your projects' data, and you can delete it: Claude Code lists, installs
and removes plugins normally without it.

Removing the plugins does not touch your project folders or `%USERPROFILE%\.keel\`. Delete that
folder yourself if you want keel's state gone; it holds the state of every project on the machine,
and it cannot be recovered afterwards.

## What keel does not do

- **It runs on Windows only.** Every script is written for Windows PowerShell 5.1.
- **It is young.** It has one maintainer, and an install on a freshly set-up machine has not been
  tested yet. The core pipeline and the state script are exercised by real projects; the companion
  skills, `keel-project-context`,
  `keel-documents` and `keel-tracker`, ship but have not been measured under real use, and the
  trackers have not been tried with anyone else's accounts.
- **It does not share or sync.** State stays on the machine it was made on, and there is no team
  mode.
- **It does nothing irreversible on its own.** Anything that cannot be undone waits for your yes,
  and a phase never moves past a gate without its record. Which acts that can be undone it does and
  then reports to you is set out in [What happens in a phase](#what-happens-in-a-phase).
- **It cannot enforce everything.** Some rules live only in the skills' instructions, such as
  `confirmEveryAct` and whether a question was put to you; the state script enforces the rest with
  exit codes, and the [design charter](DESIGN-CHARTER.md) says which is which.
- **It does not change mid-session.** A new version, or a change to a skill, is seen only by a new
  session.

## Reporting a problem or suggesting a change

**Open an issue on this repository**, `yasinkkhan/keel` on GitHub. That is the way in for any
problem, question or idea.

**From inside a project**, keel has its own route: a **signal**, a short report that names the
project, the phase and the evidence. It is kept on your machine until you decide to send it. You
normally ask Claude to file one ("file a signal about this"); the commands it runs are these, from
keel's state script inside the installed `keel-workflow` plugin:

```
keel-state.ps1 signal -Phase W4.2 -Kind gap -Detail "what went wrong" -Evidence "where it shows"
keel-state.ps1 signals
keel-state.ps1 signals-target -Repo owner/name
keel-state.ps1 signals-push
keel-state.ps1 signals-push -Apply
keel-state.ps1 signals-target -Clear
```

Claude runs each one as `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <path to
keel-state.ps1> ...`, so you do not need to change PowerShell's execution policy.

A signal's kind is one of `unsafe`, `refusal`, `wrong-doc`, `gap` or `friction`. `signals` lists
yours. `signals-target -Repo owner/name` chooses, once per machine, which GitHub repository signals
go to; choose `yasinkkhan/keel` to reach keel's maintainer. `signals-push` shows exactly what would be
sent, and `signals-push -Apply` sends it. keel's instructions tell Claude to show you that preview
and wait for your yes before it runs `-Apply`. `signals-target -Clear` removes the choice, after
which nothing is sent. **An issue on a public repository is public**, so read each preview before
you send it.

**Pull requests are not taken for now, but forks are welcome** under the licence. The maintainer makes
every change to keel, and a pull request that is opened is read as a report.
[CONTRIBUTING.md](CONTRIBUTING.md) has the detail.

## Licence

keel is released under the MIT licence, copyright (c) 2026 Yasin Khan. The full text is in
[LICENSE](LICENSE).
