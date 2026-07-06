---
name: running-tdd-cycles
description: Drive strict red-green-refactor TDD discipline on any Rust change — cargo test / nextest, proptest for invariants, one requirement per cycle.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(cargo test *), Bash(cargo nextest *), Bash(cargo check *), Bash(cargo clippy *), Bash(cargo fmt *), Bash(git status *), Bash(git diff *), Bash(git add *), Bash(git commit *)
---

## Loop

For each new piece of behaviour:

```
1. Extract <requirement> — the smallest piece of logic that adds value.
2. RED      → write ONE failing test that pins down <requirement>.
3. GREEN    → write the minimal code that makes it pass.
4. REFACTOR → improve structure with the test as a safety net.
5. COMMIT   → one logical change per commit (defer to committing-changes).
6. Repeat 2–5 until the task is done.
7. REVIEW   → defer to reviewing-changes for the final pass.
```

Always one requirement per cycle. If the cycle feels big, the requirement was too big — split it.

## RED — write a failing test

- **One test, one requirement.** Don't write a suite up front; one test, fail, pass, refactor, next.
- **Arrange-Act-Assert.** Three blocks, one assertion focus. Name tests `fn x_when_y()` / `fn returns_err_on_empty_input()` — descriptive, `snake_case`.
- **Fail for the right reason.** Run the test before writing the implementation. The failure must point at *missing behaviour*, not a compile error from a typo or missing import. In Rust a genuine RED often *is* a compile error (the function doesn't exist yet) — that's fine for the first cycle, but once it compiles the assertion must fail for the behavioural reason. Confirm with `cargo test <name>`.
- **No premature edge cases.** Happy path first. `None`/empty/overflow/error paths get their own RED-GREEN-REFACTOR cycles.
- **Property-based for invariants.** Use `proptest` (or `quickcheck`) when a law holds for all inputs (round-trips, idempotence, sort stability): `proptest! { #[test] fn roundtrips(s in ".*") { assert_eq!(decode(&encode(&s)), s); } }`. Example-based tests are for specific edge cases and documentation.

## Test layout (Rust)

- **Unit tests** live in the same file behind `#[cfg(test)] mod tests { use super::*; ... }` — they can reach private items. Put them here for logic internal to a module.
- **Integration tests** live in `tests/` at the crate root — they exercise the crate through its *public* API only, exactly as a consumer would. Put end-to-end/black-box tests here.
- **Doc tests** — runnable `# Examples` in `///` docs are tests too (`cargo test` runs them). Use them to keep public examples honest.
- Mark each test `#[test]`; async tests `#[tokio::test]`. Multiple cases: a table (`for (input, expected) in [...]`) or `#[test_case(...)]` from the `test-case` crate.

## Running

```sh
cargo test <name>                # the single test driving the active cycle
cargo test                       # full suite before commit
cargo nextest run                # faster runner if the project uses it
```

Between edits, `cargo check` is the fast "does it compile" gate; `cargo clippy -D warnings` and `cargo fmt --check` before declaring the cycle done (see [[rust-conventions]]).

## GREEN — minimal code to pass

- **Smallest possible change.** A hard-coded return is fine for the first cycle. Triangulate (generalise) only when a second test forces it.
- **No bonus features.** No error handling, logging, or generality unless a test demands it. The next cycle will.
- **Don't modify the test.** If the test is wrong, go back to RED. If the test is right and the code is wrong, fix the code.
- **Run the full suite after each change.** Confirm green; confirm no regression.

## REFACTOR — improve structure

- **Tests stay green throughout.** Run the suite after every micro-step.
- **Rust code smells to act on:** duplication (extract fn / trait default), long functions (decompose — the "does five things" beginner function), `.clone()`-spam ([[rust-ownership]]), `.unwrap()` on shipping paths ([[rust-error-handling]]), deep `match` nesting (flatten with `?` / `let ... else` / combinators), stringly-typed data (newtype/enum), primitive obsession (value objects via newtypes), dead code (delete — `#[allow(dead_code)]` is not a fix).
- **SOLID weights.** Single Responsibility first; small focused traits over god-traits. See [[engineering-philosophy]].
- **Tests refactor too.** Extract common fixtures/builders, rename for clarity, kill duplication. Coverage stays equal or improves.
- **Performance refactors are measured.** `criterion` bench before and after; commit the measurement alongside the change. No unmeasured "this is faster".
- **Refactoring is not optional.** Skip it and debt compounds; the next RED gets harder to write.

## Anti-patterns

- Writing implementation before the test.
- Writing a test that already passes.
- Writing many tests at once and implementing them in a batch.
- Modifying a test to make it pass.
- Skipping refactor because "the test passed."
- Adding tests during the GREEN phase.
- Test-after rationalised as TDD.

If discipline breaks: stop, identify the violated phase, revert to the last green state, resume from the right phase, note what went wrong.

## Validation checkpoints

**End of RED:** test exists, fails, the failure names the missing behaviour (not a stray typo), no false positive.

**End of GREEN:** all tests pass, the change is the minimum that could work, the test wasn't modified, coverage didn't drop.

**End of REFACTOR:** all tests still pass, complexity no worse, duplication addressed, `cargo clippy -D warnings` clean, `cargo fmt` applied, performance measured if performance was the goal.

## Scratch testing

Quick exploration belongs in a gitignored scratch file, not in production code or the committed suite:

- A throwaway `#[test]` in the module's `#[cfg(test)]` block, run via `cargo test <name>`; delete before commit.
- Or a `examples/scratch.rs` run with `cargo run --example scratch` (gitignore it).

Never use inline heredocs (`cargo script` stdin, `rustc -` piping) — the file pattern keeps history and stays inspectable.

## Cross-references

- `committing-changes` — commit after every successful GREEN or REFACTOR phase.
- `reviewing-changes` — final pass after the loop ends.
- [[rust-conventions]] — `cargo fmt`/`clippy`/`test` gates and layout.
- [[rust-error-handling]] — write the failing test for the error path first (bad input → expected `Err(variant)`).
- `engineering-philosophy` — Small Steps, Investigate-Don't-Mask, KISS, YAGNI apply directly.