# Rona Coach Claude Plugin Implementation Plan

> **For agentic workers:** Implement task-by-task with test-first development. Do not modify the existing `rona` or `rona-alpha` plugin directories.

**Goal:** Add a standalone Claude Code `rona-coach` plugin that runs the same native coaching protocol as the Support-installed Claude/Codex skill while preserving existing plugins byte-for-byte.

**Architecture:** Create a new plugin directory with a thin `/rona-coach` skill, remote OAuth MCP configuration for users without Support, and coaching-scoped hooks limited to explicit session attachment and safe flush. Generate the skill body from one canonical runtime source and assert parity with the Support bundle during release verification.

**Tech Stack:** Claude Code plugin manifest, Markdown skill, HTTP MCP configuration, shell hooks, repository contract tests.

## Global Constraints

- Existing `plugins/rona` and `plugins/rona-alpha` remain unchanged.
- The new plugin uses native coaching MCP tools and never calls legacy skill generation or topic claiming.
- Hooks observe/flush only; they never report completion.
- User-facing responses do not expose identifiers, local paths, hook names, or credentials.

---

### Task 1: Plugin scaffold and regression protection

**Files:**
- Create: `plugins/rona-coach/.claude-plugin/plugin.json`
- Create: `plugins/rona-coach/.mcp.json`
- Create: `tests/rona-coach-plugin.test.mjs`

- [ ] Write a failing test for manifest, OAuth MCP URL, native tool expectations, and unchanged hashes for legacy plugin fixtures.
- [ ] Run the focused test and confirm missing plugin failure.
- [ ] Add the minimal plugin scaffold and rerun.

### Task 2: Runtime skill and safe hooks

**Files:**
- Create: `plugins/rona-coach/skills/rona-coach/SKILL.md`
- Create: `plugins/rona-coach/skills/rona-coach/hooks/session-link.sh`
- Create: `plugins/rona-coach/skills/rona-coach/hooks/flush-outbox.sh`
- Modify: `tests/rona-coach-plugin.test.mjs`

- [ ] Add failing assertions for start/resume, goal/direction, artifact/evidence, user review, guarded completion, and hook non-authority.
- [ ] Run and confirm failure.
- [ ] Implement the thin runtime and hooks.
- [ ] Run the focused test and repository checks.

### Task 3: Cross-package parity and installation verification

**Files:**
- Create: `scripts/verify-rona-coach-parity.mjs`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`

- [ ] Add the plugin to the marketplace without changing existing plugin entries.
- [ ] Verify the canonical behavior clauses match the Support bundle.
- [ ] Run all repository tests and `git diff --check`.
