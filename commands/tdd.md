---
description: Run a red-green-refactor TDD cycle on $ARGUMENTS (Rust).
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(cargo test *), Bash(cargo nextest *), Bash(cargo check *), Bash(cargo clippy *), Bash(cargo fmt *), Bash(git status *), Bash(git diff *)
---

Scope: $ARGUMENTS

Invoke the `running-tdd-cycles` skill on the requirement above. That skill is the single source of truth for the red-green-refactor procedure, the fails-for-the-right-reason verification, and the refactor-only-when-green gating.

If `$ARGUMENTS` names a phase explicitly (`red`, `green`, `refactor`), run only that phase. Otherwise drive the full cycle.

Compose with the Rust rule skills:
- `rust-testing` — where the test lives (`#[cfg(test)]` unit vs `tests/` integration vs doc test), `#[tokio::test]`, `proptest`, real objects over mocks.
- `rust-conventions` — the `cargo fmt`/`clippy -D warnings`/`cargo test` gate the cycle must leave green.
- `rust-error-handling` — write the failing test for the error path first (bad input → expected `Err(variant)`).
- `engineering-philosophy` — Small Steps, one requirement per cycle.