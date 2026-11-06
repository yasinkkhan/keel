# keel - working rules for a Claude session

This repository is the `keel` plugin marketplace: the plugins under `plugins/`, the scripts under
`scripts/`, `DESIGN-CHARTER.md`, the manifests and two generated inventories. It is not itself a
keel project, so `keel-state.ps1 status` exits 91 here by design.

- **Read `DESIGN-CHARTER.md` in full before changing anything under `plugins/`**, this session,
  with the Read tool. A repo-local `PreToolUse` gate (`.claude/settings.json` runs
  `scripts/keel-plugins-gate.ps1`) refuses the change until you have.
- **The change process is in `CONTRIBUTING.md`.** A plugin change ships with its `CHANGELOG.md`
  entry, its version in the plugin's `plugin.json` and in `.claude-plugin/marketplace.json`, and
  both generated inventories, `README.md` and `ARCHITECTURE.html`, rebuilt with
  `scripts/gen-suite-docs.ps1 -Write`. `scripts/check-suite-docs.ps1` enforces this at commit and
  push.
- **The git hooks are in `.githooks/`.** The SessionStart hook, `scripts/keel-session-start.ps1`,
  points `core.hooksPath` at that folder; where it has not run, set it with
  `git config core.hooksPath .githooks`, or the commit and push checks do not run.
- **Scripts are Windows PowerShell 5.1-compatible and ASCII-only.** They run from git hooks and
  Claude Code hooks through `powershell.exe -NoProfile`, which is 5.1, and
  `scripts/check-suite-docs.ps1` refuses a `.ps1` holding a non-ASCII byte.
- The wrapper's verb list, which exits 0 from here:

  ```
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "plugins/keel-workflow/skills/keel-orchestrator/wrappers/keel-state.ps1"
  ```
