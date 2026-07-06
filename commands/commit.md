---
description: Commit + PR via committing-changes skill (hooks, cargo gate, gh pr create).
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh auth status), Bash(cargo fmt *), Bash(cargo clippy *), Bash(cargo test *), Read
---

Scope: $ARGUMENTS

Invoke the `committing-changes` skill. If `$ARGUMENTS` is provided, treat it as the intended commit message or scope hint; otherwise let the skill infer the message from the staged diff.

The skill is the single source of truth for:

- Commit-message rules (capital start, ≤72 chars, no trailing period, no Co-Authored-By, one logical change per commit).
- Branch protection (never push to `main`/`master`, never force-push, never merge a PR on the user's behalf).
- Hook installation (commit-msg + pre-commit + pre-push) and the optional PR-size CI gate. The Rust pre-commit hook runs `cargo fmt --check`, `cargo clippy -D warnings`, and `cargo test`.

Before committing, run the auto-fix pass from the skill (`cargo fmt --all`, then `cargo clippy --all-targets --all-features -- -D warnings`). Stage specific paths — don't sweep in `cargo fmt` changes to files this change didn't touch.

Echo any state-changing `git` or `gh` command back to the user before running it.