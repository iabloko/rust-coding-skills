# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes, tuned for Rust and a backend newcomer. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If a borrow-checker or type error is fighting you, understand *why* before reaching for `.clone()`/`Rc<RefCell>`/`unsafe` — those often mask a design problem.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No generics, traits, or macros for single-use concrete code.
- No `pub` surface "in case someone needs it."
- No error handling for impossible scenarios (but do handle the possible ones — `Result`, not `.unwrap()`).
- If you write 200 lines and it could be 50, rewrite it.

Ask: "Would a senior Rust engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

- Don't "improve" adjacent code, comments, or formatting.
- Don't let `cargo fmt` reformat files your change didn't touch — stage only your lines.
- Match existing style, even if you'd do it differently.
- Remove imports/bindings/functions *your* change made unused; leave pre-existing dead code (mention it, don't delete it unasked).

The test: every changed line traces directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

- "Add validation" → "Write tests for invalid inputs (expected `Err(variant)`), then make them pass."
- "Fix the bug" → "Write a test that reproduces it, then make it pass."
- "Refactor X" → "Ensure `cargo test` passes before and after."

The quality gate is always: `cargo fmt --check` clean, `cargo clippy -D warnings` clean, `cargo test` green. A change is not done until all three pass.

For multi-step tasks, state a brief plan with a verify check per step.

---

## 5. Active Skills

### Rust skills (auto-activated when relevant)

| Skill | When it applies |
| --- | --- |
| `rust-conventions` | Any `.rs` file — naming, layout, fmt/clippy gates, `Result`-first, forbidden patterns, beginner smells |
| `rust-error-handling` | Any `Result`, error type, `.unwrap()`/`panic!`, or recoverable-vs-bug decision — `thiserror`/`anyhow` |
| `rust-ownership` | Any borrow-checker fight, `.clone()`/`Rc`/`Arc`/`RefCell`/`Mutex`, or lifetime annotation |
| `rust-testing` | Any logic change — unit/integration/doc tests, `#[tokio::test]`, `proptest`, real objects over mocks |
| `rust-async` | Any async code — tokio, no blocking the runtime, spawning/`JoinSet`, cancellation, channels, axum handlers |
| `rust-architecture` | Organizing a crate, adding a trait/module boundary, wiring services — layering, DI via traits, dispatch choice |
| `rust-performance` | Any hot path or throughput/latency/memory goal — measure first, cut allocations, tune the release profile |

### Engineering skills (auto-activated; principles apply to every change)

- `reviewing-changes` — strict five-pass review before merging any branch. **This is the harsh-review gate.**
- `running-tdd-cycles` — red→green→refactor on every logic change (`cargo test`/`nextest`).
- `committing-changes` — feature branch + PR + git hooks; never push `main`, never merge.
- `designing-architecture` — crate/module + crates.io scan before implementing a new system.
- `engineering-philosophy` — KISS, YAGNI, DRY, SOLID, Fail-Fast on every decision.
- `shell-discipline` — one command per call, no inline env vars.

**These guidelines are working if:** fewer `.unwrap()`/`.clone()` crutches in diffs, fewer god-functions, error paths tested, and clarifying questions come before implementation rather than after mistakes.