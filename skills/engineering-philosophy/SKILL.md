---
name: engineering-philosophy
description: Apply KISS, YAGNI, DRY, SOLID, fail-fast, be-brief on every code decision.
---

## Principles

- **Architecture** — Module/crate responsibilities defined in the project's architecture map (often `docs/architecture.md`).
- **KISS** — Simple solutions over complex ones. In Rust: don't reach for generics, trait objects, macros, or `Rc<RefCell>` before a plain function or owned value solves it.
- **YAGNI** — Build only what's needed now. Less code is better. No speculative generics or `pub` surface "in case someone needs it".
- **Write Less** — If you can avoid writing the code or the comment, don't. The smallest change that solves the problem wins; a comment earns its place only when it says what the code cannot (a *why*, an invariant, a `// SAFETY:` note, a magic-number derivation), never when it restates the code.
- **DRY** — Single source of truth. Never copy-paste. In Rust, prefer a shared function, a trait default method, or a macro (last resort) over duplicated blocks.
- **SOLID** — Enforce Single Responsibility; keep the others in mind. Traits are your interface-segregation and dependency-inversion tools — small, focused traits over one god-trait.
- **No Magic** — Make everything explicit. No hidden behaviour, no clever `Deref` abuse, no macro that hides control flow.
- **No Number Without Measurement** — Performance figures in docs or comments (latency, throughput, alloc counts) MUST come from a real measurement: a `criterion` bench, a profile, a test fixture, or an upstream citation. Author-quoted "approximately X" without a source is a future-self trap; either remove the number or measure it first.
- **Small Steps** — Minimal changes, commit often. One logical change per commit.
- **Stay In Scope** — Change only what the task requires. Don't fix, reformat, or rename unrelated code you happen to read, even when it looks wrong: note it and leave it. Off-task diffs are harder to review and revert; genuine cleanups earn their own PR. (`cargo fmt` reformatting an untouched file is an off-scope diff — stage only your lines.)
- **Use Libraries** — Prefer established crates (serde, tokio, thiserror, clap, sqlx) over reimplementing. Check crates.io and the existing `Cargo.toml` before writing custom code. If a crate in the lockfile already does it, hand-rolling it is a review finding.
- **Backwards Compatibility** — Don't keep code for backwards-compatibility purposes unless asked.
- **CI** — Automate all possible quality checks: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`, `cargo deny` in CI.
- **Investigate, Don't Mask** — When a check fails or the borrow checker complains, find the root cause instead of masking the symptom. A `.clone()` or `#[allow(...)]` added to make an error disappear is masking — see [[rust-ownership]].
- **Fail Fast** — Detect and surface errors immediately at the point of failure. `Result` at boundaries, `assert!`/`debug_assert!` for invariants, early returns with `?` and `let ... else`. See [[rust-error-handling]].
- **Be Brief** — Imperative output. No preamble, no recap, no restating the task back. Compress *response prose*, never *operational checklists*: keep every named rule, severity word, sub-check, and category from the active skill verbatim — cut the explanation around them, not the rule itself. Applies to chat replies, commit messages, PR bodies, review findings, and any other text the agent emits.

## Application

These principles are *judgement weights*, not rules. When two conflict, this skill defers to the workflow skill driving the task:

- During `designing-architecture`: KISS, YAGNI, Use Libraries, and No Magic dominate. Reject premature generics, speculative trait abstractions, and macro machinery.
- During `reviewing-changes`: SOLID, DRY, Investigate-Don't-Mask, Fail Fast, and Stay In Scope dominate. Flag `.unwrap()`/`.clone()` used to mask problems; flag duplication; flag oversized modules/functions; flag edits outside the change's stated scope.
- During `running-tdd-cycles`: Small Steps, Stay In Scope, and Fail Fast dominate. One requirement per red-green-refactor; one logical change per commit; touch only the files that requirement needs.

When a user proposes a change that violates one of these principles, name the principle and explain the consequence — don't just refuse.

## Cross-references

- [[rust-conventions]] / [[rust-error-handling]] / [[rust-ownership]] — the concrete Rust rules these weights sit behind.
- `reviewing-changes`, `running-tdd-cycles`, `designing-architecture` — the workflows these weights defer to.