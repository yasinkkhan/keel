# Contributing to keel

## Reporting a problem, and pull requests

**Issues are welcome, and so are forks. Outside pull requests are not taken for now.** Open an issue
on this repository for a problem, a question or an idea, or send one from inside a keel project as a
signal (see "Reporting a problem or suggesting a change" in `GETTING-STARTED.md`). Fork keel and
change your copy as you like, under the MIT licence.

A pull request opened from outside is read as a report: what it changes is taken as a description of
the problem, and the pull request itself may be closed with a note saying where the report went.
Fixes are made in keel by its maintainer, by the process below. That matches the design charter's
P26, in which a fix comes back as a pull request authored in keel itself.

## Why so little process

keel has one maintainer, who proposes and reviews every change. So there is no review
ritual and no precedent log. What replaces them is `DESIGN-CHARTER.md`, read live before every
plugin change, and `scripts/check-suite-docs.ps1`, which refuses the commit when the docs did not
move with the change.

## The change process

1. **Read `DESIGN-CHARTER.md` in full, this session.** The repo-local `PreToolUse` gate blocks
   `plugins/**` edits without it. Reading it afterwards to satisfy the gate defeats the point.
2. **Answer the eleven questions** at the end of the charter, in writing, in the conversation. Any
   "yes" is a red flag, not a blocker - it means say why anyway.
3. **Make the change.**
4. **Move the docs with it**: `CHANGELOG.md` entry, version bump in BOTH
   `plugins/<name>/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, and
   `powershell -File scripts/gen-suite-docs.ps1 -Write` for the README inventory.
5. **Commit.** The pre-commit hook runs the validator on staged files; pre-push runs it strict.

## Versioning

Semantic-ish, per plugin:

- **patch** - wording, a clarification, a fix with no contract change
- **minor** - a new verb, a new skill, a widened contract
- **major** - a tightened contract, a removed verb, anything that could strand an in-flight project

A tightening is the one that needs care. Charter P24: contracts widen freely; tightening ships with
a migration and a cited failure, because nothing pins a project to a version. An installed copy
moves when a release is cut and the update commands are run, and from the next session every
project on that machine runs the new version together.

**Fold, don't stack.** Compute the bump against the last committed version, never the working tree.

## Releasing

Users and work machines install keel from the `release` branch (README, "Install"). Development
happens on `main`, and `release` moves only when a release is cut. Each release is also tagged
`v<version>`, the version being the marketplace's own, in `.claude-plugin/marketplace.json`.

1. **Land the change on `main` and push it**, with its docs and version bumps. A plugin whose files
   changed carries a new `version`: Claude Code offers an update only when a plugin's version
   changes, so a change without a bump never reaches an installed copy. The marketplace version
   names the release, and there is one release per marketplace version.
2. **Preview**, from the repo root:
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/keel-release.ps1
   ```
   It refuses, naming why and changing nothing, unless the tree is clean, the branch is `main`,
   `main` is on the remote (read live with `git ls-remote`), the tag `v<version>` does not exist
   here or on the remote, the remote's `release` would fast-forward to `main`, and
   `scripts/check-suite-docs.ps1 -Strict` passes. Its header lists the exit code for each.
3. **Cut it:**
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/keel-release.ps1 -Apply
   ```
   One atomic push moves `release` to `main`'s commit and creates the tag there. The pre-push hook
   runs `-Strict` again on that push, so budget for two runs of it.
4. **Confirm:**
   ```
   git ls-remote origin refs/heads/main refs/heads/release refs/tags/v<version>
   ```
   All three lines carry the same sha.

The README and this file are read from `main` and are not plugin content, so a change to them alone
needs no release.

## Adding a skill

The default answer is no (charter P12). Before proposing one, name which existing skill could
absorb it. Every skill's description is always-on in every session and competes for routing
attention with every other, so the marginal skill makes all the others slightly worse at firing.

Check the cost after adding one:

```
claude plugin details keel-workflow@keel
```

## Changing the wrapper

`keel-state.ps1` is the only writer of state, so a bug there is a bug in every project at once.

- **Run it.** Every contract in it was written confidently and three were wrong on first execution.
  A change that has not been executed has not been tested.
- **Test the refusals, not just the successes.** The first test run of this script had every
  refusal passing and every success path broken, which a happy-path test would have called green.
- **Keep it ASCII and 5.1-compatible.** It runs under `powershell.exe -NoProfile`.
- **Widen, do not tighten** (P24). A new required parameter with no default strands in-flight work.

## What never goes in this repo

- **State.** It lives under `%USERPROFILE%\.keel\` and is written only by the wrapper.
- **Sensitive material.** Financial documents, identifiers, keys, seed phrases. These live in the
  per-project quarantine outside every repo, redacted at extraction (charter P23).
- **A second backlog.** Signals are the queue. A `TODO.md` here would be a second authority, and it
  would be the one nobody reads.
