---
description: Rust-specific security review of $ARGUMENTS (wraps rust-security skill).
allowed-tools: Read, Grep, Glob, Bash(git diff *), Bash(git log *), Bash(git show *), Bash(git rev-parse *), Bash(gh pr view *), Bash(gh pr diff *), Bash(cargo audit *), Bash(cargo deny *), Bash(cargo geiger *)
---

Scope: $ARGUMENTS

If `$ARGUMENTS` is empty, default the scope to `git diff master...HEAD` (or `main...HEAD` if the default branch is `main`). If it looks like a PR number, resolve it via `gh pr diff <N>`. Otherwise pass it through verbatim.

Invoke the `rust-security` skill and apply its checklist to the scoped diff. That skill is the single source of truth for the Rust security categories (unsafe soundness, integer overflow/truncation, panic-as-DoS, injection, deserialization limits, secrets, crypto, dependency advisories, authz, resource exhaustion) and the tooling.

Run the dependency scanners where available: `cargo audit`, `cargo deny check`. For heavy `unsafe`, note `cargo miri test` / `cargo geiger` as follow-ups.

For each finding, spell out the **attack vector** (actor → precondition → impact) and calibrate severity practically — a theoretical issue behind impossible preconditions is Minor; a panic or injection on the request path is Critical. Read-only: report, never edit.

This is the focused single-pass counterpart to the security agent in `/rust-skills:review` — use it when you want *only* the security audit.