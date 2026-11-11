# keel

keel is a set of **Claude Code plugins for planning and running long projects**, software or not: a
product, a tax return, a house sale. The plan lives in files in the project's folder and the progress
in a state file on your machine, so the work survives new sessions, context compaction and months
away from it.

It is for one person who uses Claude Code and runs work that spans many sessions. **keel runs on
Windows only** (see [Requirements](#requirements)).

**New here? Start with [GETTING-STARTED.md](GETTING-STARTED.md)**: installing, a first project
walked through, what keel will ask you, where it keeps things and what leaves your machine.

## What it does

| Capability | Where |
|---|---|
| Plan a project's goals, epics, workstreams and phases | `keel-plan-project` / `keel-plan-epic` / `keel-plan-workstream` |
| Run one phase through eight gates | `keel-run-phase` |
| Close a workstream: record what went wrong where it will be read, or report it about keel as a signal | `keel-close-workstream` |
| Ground a session in the active project | `keel-project-context` |
| Project the plan onto a tracker, read outside documents | `keel-tracker` / `keel-documents` |

## Status

**keel is young, and has one maintainer.** The pipeline, the state script and the governance
scripts are built, tested, and exercised by real projects. The companion plugins' skills,
`keel-project-context`, `keel-documents` and `keel-tracker`, ship, but how they behave under real use
is not yet established. An install on a freshly set-up machine has not been tested yet.

## The model

Four roles, a closed set. **Depth is free; roles are not.**

```
GOALS   flat, many-to-many, project-scoped     G1, G2 ...
  ^
  | claimed by
  |
project
  +-- epic          E<n>   contains epics and workstreams, any depth,
  |                        and must state what it groups
  +-- workstream    W<n>   contains only phases; independently deliverable;
  |                        declares at least one goal
  +-- phase         W<n>.<p>   always a leaf; one sitting; carries the gates,
                               an actor, an optional due date, and waiting state
```

A **check** on a phase is `W<n>.<p>-C<n>`: `C`, not `G`, because `G` is a goal here.

## The pipeline

```
ground -> investigate -> plan -> implement -> verify -> human -> enact -> record
```

Identical for every project and every actor. A phase's **actor**, `agent` (Claude), `self` (you) or
`external` (an accountant, auditor, exchange, counsel), selects which evidence a check accepts. It
never selects which gates run.

`enact` is the outward act: filing, signing, publishing, broadcasting, deploying. It refuses to
record without `-Reversible` and `-Observable` answered **before** the act.

## Where things live

```
<any folder you keep projects in>\
  <project>\
    keel.json               git? tracker? quarantine? - read before anything else
    CHARTER.md              what done means, scope boundary, goals
    plan\  record\  reference\
    repos\                  only if the project produces code
    private\                scratch, ignored by git; only with git

%USERPROFILE%\.keel\        never committed anywhere
  projects\<project>\state.json      written ONLY by keel-state.ps1
  projects\<project>\phases\W4.2\    the gate artifacts
  quarantine\<project>\              sensitive material; the model still reads it
  signals\S0007.json                 a report about keel, one file per report
```

`%USERPROFILE%` is your Windows user folder, usually `C:\Users\<your user name>`. The active project
is resolved by walking up from the working directory to the nearest `keel.json`. It is never stored:
opening a folder *is* selecting the project.

## Reporting a problem with keel

A project session never edits keel itself. It files a **signal**: a short report naming the project,
the phase and the evidence, kept on your machine. **Nothing is sent until you choose where** with
`signals-target`, and each report is then shown to you exactly, and keel waits for your yes, before
it becomes a GitHub issue. A project with `quarantine` on may describe its evidence only by
reference: for such a project the state script refuses evidence that runs over one line or past 240
characters. Fixes come back in a release. The commands are in the guide, under
[Reporting a problem or suggesting a change](GETTING-STARTED.md#reporting-a-problem-or-suggesting-a-change),
and [What leaves your machine](GETTING-STARTED.md#what-leaves-your-machine) lists everything keel
sends.

## Requirements

**keel runs on Windows only.** Mac and Linux are not supported: every script is written for Windows
PowerShell, and the paths and the state folder assume Windows.

| You need | For |
|---|---|
| Windows | everything. keel keeps its state under `%USERPROFILE%\.keel`. |
| Windows PowerShell 5.1, as `powershell.exe` | every keel script. It comes with Windows. The scripts are written for it, not for PowerShell 7 (`pwsh`). |
| Claude Code | running keel at all: keel is a set of Claude Code plugins, and its skills run inside a Claude Code session. |
| `git` | installing keel from GitHub, which clones the repo with it. Then projects whose `keel.json` has `"git": true`, and any phase that declares a repo: keel reads branches and unpushed commits through it, and records what a verify checked. A project without git makes no git calls of its own. |
| The GitHub CLI, `gh`, signed in to GitHub | sending signals to GitHub: `signals-push`, `adopt-signal`, and closing an issue from `resolve-signal`. Nothing else uses it. |

If `git` or `gh` is not installed, the command that needs it says so.

## Token cost

Claude Code estimates what each plugin costs in tokens; `claude plugin details <plugin>@keel` prints
the estimate. The figures below are its estimates for `keel-workflow` 0.68.7, `keel-project` 0.4.7
and `keel-surfaces` 0.3.2, rounded as it prints them, and it says itself that real usage can differ.
Run the command for the copy you have installed.

**Always on**, added to every session: about 2,302 tokens for `keel-workflow`, 260 for
`keel-project` and 624 for `keel-surfaces`.

**On invoke**, paid each time a skill runs:

| Skill | Plugin | On invoke |
|---|---|---|
| `keel-orchestrator` | `keel-workflow` | ~21.2k |
| `keel-plan-workstream` | `keel-workflow` | ~11.1k |
| `keel-run-phase` | `keel-workflow` | ~9.9k |
| `keel-close-workstream` | `keel-workflow` | ~7.4k |
| `keel-project-context` | `keel-project` | ~5.2k |
| `keel-plan-project` | `keel-workflow` | ~5k |
| `keel-plan-epic` | `keel-workflow` | ~2.5k |
| `using-keel` | `keel-workflow` | ~1.9k |
| `keel-tracker` | `keel-surfaces` | ~1.9k |
| `keel-documents` | `keel-surfaces` | ~1.7k |

## Install

From GitHub, with these four commands in a terminal:

```bash
claude plugin marketplace add yasinkkhan/keel#release
claude plugin install keel-workflow@keel
claude plugin install keel-project@keel
claude plugin install keel-surfaces@keel
```

Then start a new Claude Code session. `#release` follows the `release` branch, which moves only when
a release is cut; each release is also tagged `v<version>`.

### Update

```bash
claude plugin marketplace update keel
claude plugin update keel-workflow@keel
claude plugin update keel-project@keel
claude plugin update keel-surfaces@keel
```

The first command fetches the newest release. Each `plugin update` installs it, or says the plugin is
already at the latest version. Then start a new session: skills load once at session start.

### Developing keel: a directory source

To work on keel itself, add your clone instead of the GitHub repo:

```bash
claude plugin marketplace add <path to your keel clone>
claude plugin install keel-workflow@keel
claude plugin install keel-project@keel
claude plugin install keel-surfaces@keel
```

Registered as a **directory source**, so the working tree IS the load path — editing a `SKILL.md`
updates the plugin, with no install step. Two consequences worth knowing:

- **A new session is required** for skill changes to be seen. Skills load once at session start.
- **`claude plugin list` reports a stale version** for a directory source. Use
  `claude plugin details keel-workflow@keel` instead, which resolves live.

## Inventory

<!-- BEGIN GENERATED INVENTORY -->
| Plugin | Version | Skills |
|---|---|---|
| `keel-project` | 0.4.7 | `keel-project-context` |
| `keel-surfaces` | 0.3.2 | `keel-documents`, `keel-tracker` |
| `keel-workflow` | 0.69.0 | `keel-close-workstream`, `keel-orchestrator`, `keel-plan-epic`, `keel-plan-project`, `keel-plan-workstream`, `keel-run-phase`, `using-keel` |
<!-- END GENERATED INVENTORY -->

Generated by `scripts/gen-suite-docs.ps1 -Write` and checked by `scripts/check-suite-docs.ps1`.
Do not hand-edit it (charter P11).

## Contributing

Issues are welcome, and so are forks. Pull requests from outside are not taken for now:
[CONTRIBUTING.md](CONTRIBUTING.md) says why and how to report instead, and describes the change
process. `CLAUDE.md` holds the standing rules for a Claude session working on this repo. Read
[DESIGN-CHARTER.md](DESIGN-CHARTER.md) before touching `plugins/**`: a repo-local `PreToolUse` gate
enforces it.

## Licence

MIT. See [LICENSE](LICENSE).
