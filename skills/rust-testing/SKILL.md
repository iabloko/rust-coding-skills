---
name: rust-testing
description: Write and run Rust tests correctly — unit tests in `#[cfg(test)]` modules, integration tests in `tests/`, doc tests, `#[tokio::test]` for async, proptest for invariants, table-driven cases, real objects over mocks, and coverage. Use whenever adding or changing any logic in a Rust crate. Pair with running-tdd-cycles for the red-green loop.
---

# Rust Testing

How to structure, write, and run tests in a Rust crate. This is the *mechanics*; `running-tdd-cycles` is the *discipline* (write the failing test first). Pair with [[rust-conventions]] and [[rust-error-handling]].

## Where tests live

Three kinds, three locations — pick by what you're testing:

- **Unit tests** — in the *same file* as the code, in a `#[cfg(test)] mod tests { use super::*; ... }` block. They compile only under `cargo test` and can reach **private** items. Use for logic internal to a module.
  ```rust
  fn parse_port(s: &str) -> Result<u16, ParseError> { ... }

  #[cfg(test)]
  mod tests {
      use super::*;

      #[test]
      fn parses_valid_port() {
          assert_eq!(parse_port("8080").unwrap(), 8080);
      }

      #[test]
      fn rejects_out_of_range() {
          assert!(matches!(parse_port("99999"), Err(ParseError::OutOfRange)));
      }
  }
  ```
- **Integration tests** — each file in `tests/` at the crate root is its own crate that links your library and sees only its **public** API. Use for end-to-end / black-box behavior, exactly as a consumer would call it. Share setup via a `tests/common/mod.rs` (not `tests/common.rs` — that would run as its own test binary).
- **Doc tests** — runnable ` ```rust ` examples in `///` docs. `cargo test` compiles and runs them, keeping public examples honest. Use `?` in doc examples by making the hidden `main` return `Result`; hide setup lines with a leading `# `.

`.unwrap()`/`.expect()` are **fine inside tests** — a panic there is a test failure, which is what you want. The shipping-path ban ([[rust-error-handling]]) does not apply to test code.

## Anatomy of a good test

- **One behavior per `#[test]`.** Arrange-Act-Assert, one assertion focus.
- **Descriptive `snake_case` names** stating the behavior: `returns_err_on_empty_input`, `retries_three_times_then_gives_up`. The name is the spec.
- **Assertions:** `assert_eq!`/`assert_ne!` (they print both sides on failure — prefer over `assert!(a == b)`), `assert!(matches!(x, Pattern))` for matching an enum variant/`Err` kind without deriving `PartialEq`, `#[should_panic(expected = "...")]` only for code that legitimately panics.
- **Test the error paths, not just the happy path.** For a `Result`-returning fn, a test that feeds bad input and asserts the specific `Err(variant)` is as important as the success test. Missing error-path tests is a `reviewing-changes` finding.

## Table-driven cases

For the same logic across many inputs, iterate a table instead of copy-pasting tests:

```rust
#[test]
fn classifies_status_codes() {
    let cases = [
        (200, Class::Success),
        (404, Class::ClientError),
        (503, Class::ServerError),
    ];
    for (code, expected) in cases {
        assert_eq!(classify(code), expected, "code {code}");
    }
}
```

The trailing message (`"code {code}"`) tells you *which* row failed. For richer per-case reporting use the `rstest` (`#[case(...)]`) or `test-case` (`#[test_case(...)]`) crates — each row becomes a separately-named test.

## Async tests

- `#[tokio::test]` turns an `async fn` test into one backed by a fresh runtime. `#[tokio::test(flavor = "multi_thread")]` when the test needs real parallelism.
- Control time deterministically with `tokio::time::pause()` + `advance()` instead of real `sleep` — fast, non-flaky timeout tests. See [[rust-async]].
- Never `block_on` inside an already-async test; just `.await`.

## Property-based testing

When a law holds for *all* inputs — round-trips, idempotence, invariants — assert the law over generated inputs with `proptest` (preferred) or `quickcheck`:

```rust
proptest! {
    #[test]
    fn encode_decode_roundtrips(bytes in proptest::collection::vec(any::<u8>(), 0..1024)) {
        prop_assert_eq!(decode(&encode(&bytes)), bytes);
    }
}
```

Property tests *complement* example tests — keep specific edge cases (empty, boundary, known-bad) as named example tests for documentation; use properties for the general law. `proptest` shrinks a failing case to a minimal counterexample automatically.

## Real objects over mocks

- **Prefer the real object.** Rust makes constructing real values cheap; a real `Config`, a real in-memory store, a real struct beats a mock. Over-mocking tests the mock, not the code.
- **Mock only at true I/O boundaries** — network, database, clock, filesystem — and do it by depending on a **trait** you define, then supplying a test impl (a hand-written fake is often clearer than a framework). Reach for `mockall` (`#[automock]`) only when hand-writing the fake is genuinely tedious.
- **Fakes over mocks** where possible: an in-memory `HashMap`-backed `UserRepo` impl is a fake you can reuse across many tests; a per-test `expect_*()` mock script is brittle. This is the repository pattern paying off — see [[rust-architecture]].
- Inject the clock (`trait Clock { fn now(&self) -> Instant; }`) rather than calling `Instant::now()` directly, so time-dependent logic is testable.

## Running

```sh
cargo test                       # everything: unit + integration + doc tests
cargo test <name>                # filter by substring (the active TDD cycle)
cargo test -- --nocapture        # show println!/dbg! output from passing tests
cargo test -- --test-threads=1   # serialize (for tests sharing global state)
cargo test --doc                 # doc tests only
```

- **`cargo nextest run`** is a faster, better-output runner (parallel, per-test isolation, retry flags) — use it if the project has it; note it does **not** run doc tests, so pair with `cargo test --doc`.
- **Coverage:** `cargo llvm-cov` (preferred, precise) or `cargo tarpaulin`. Use coverage to find *untested branches*, not as a target to game — 100% line coverage with no error-path assertions is worthless.
- **Shared global state / env vars:** tests run in parallel by default. Tests mutating a process-global (env, a `static`, the current dir) must be serialized — group them behind `serial_test`'s `#[serial]` or a `Mutex`, or (better) refactor to inject the dependency.

## Fixtures & builders

- Extract repeated setup into a helper fn or a **builder** (`TestUserBuilder::new().with_email(...).build()`) rather than copy-pasting arrange blocks — DRY applies to tests too.
- Keep fixtures in the test module (unit) or `tests/common/mod.rs` (integration). Don't leak test-only constructors into the public API; gate them behind `#[cfg(test)]` or a `test-util` feature.

## Anti-patterns (flag on sight)

- Only happy-path tests; the `Err`/`None`/boundary paths untested.
- Asserting on an error's `Display` string (`e.to_string().contains(...)`) instead of `matches!(e, Error::Variant)`.
- Over-mocking: mocking a plain data struct or pure function instead of using the real thing.
- A mock script (`expect_x().times(1)...`) so elaborate it re-implements the collaborator — use a fake.
- Tests that share mutable global state and pass only because of run order (flaky under `--test-threads`).
- `thread::sleep` in an async test to "wait for" something — use `tokio::time` control or await the actual signal.
- `#[should_panic]` on code that should have returned `Result` — test the `Err`, don't test the panic.
- Committing a `dbg!`/`println!`-debugging test or a `#[ignore]`'d stub as "done".
- Testing private implementation detail through the public API contortions — put it in a `#[cfg(test)]` unit test instead.

## Verification checklist

- [ ] Every new fallible fn has both a success test and an error-path test (asserting the specific variant).
- [ ] Async logic tested with `#[tokio::test]`; time-based logic uses `tokio::time` control, not real sleeps.
- [ ] Invariants/round-trips covered by a `proptest` where applicable.
- [ ] Mocks appear only at I/O boundaries; everything else uses real objects or fakes.
- [ ] No test depends on run order or shared global mutable state (or it's explicitly serialized).
- [ ] `cargo test` (incl. doc tests) green; coverage checked for untested branches, not gamed.
- [ ] No `#[ignore]`/stub/`dbg!` left in a change that claims to be complete.

## Cross-references

- `running-tdd-cycles` — the red-green-refactor discipline that drives *when* to write these tests (failing test first).
- [[rust-error-handling]] — test the error variants; `.unwrap()` is fine in tests, banned on shipping paths.
- [[rust-async]] — `#[tokio::test]`, deterministic time control.
- [[rust-architecture]] — trait-based seams (repository pattern) are what make real-object/fake testing possible.
- `reviewing-changes` — missing error-path tests and over-mocking are code-quality findings.