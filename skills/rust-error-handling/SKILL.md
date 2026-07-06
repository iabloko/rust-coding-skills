---
name: rust-error-handling
description: Design Rust error handling correctly — Result-first, the `?` operator, custom error enums with thiserror for libraries, anyhow for binaries, error context, and the narrow cases where panicking (unwrap/expect/panic!) is actually correct. Use whenever code returns Result, defines an error type, calls unwrap/expect, or decides between recoverable and unrecoverable failure.
---

# Rust Error Handling

The single most common source of sloppy beginner Rust is error handling: `.unwrap()` everywhere, `Box<dyn Error>` as the answer to everything, and panics on inputs that should be handled. This skill is the house rulebook. Pair with [[rust-conventions]].

## The one decision: recoverable or a bug?

Every failure is one of two kinds. Decide first, because it dictates the mechanism:

- **Recoverable** (expected in normal operation): bad user input, a missing file, a network timeout, a parse failure, a not-found lookup. → Return `Result<T, E>`. The caller decides what to do.
- **Unrecoverable** (a bug — an invariant your code guarantees was violated): indexing past a length you just checked, a `match` arm you proved is impossible, a poisoned lock. → `panic!` (or the macros). The program cannot sensibly continue.

Getting this wrong in *either* direction is a defect: panicking on bad input is a crash-the-server bug; returning `Result` for a genuine invariant violation hides a bug behind noise. Most of the time the answer is `Result`.

## `Result` and `?`

- Return `Result<T, E>` from every fallible function. Propagate with `?`, don't `match` unless you handle the error right here.
- `?` converts the error via `From`, so a function returning `Result<T, MyError>` can `?` any error that has `impl From<OtherError> for MyError`. This is why custom error enums (below) pay off.
- `let ... else` for the "extract or bail" shape:
  ```rust
  let Some(user) = cache.get(&id) else {
      return Err(Error::NotFound(id));
  };
  ```
- Turn an iterator of `Result`s into a `Result` of a collection with `.collect::<Result<Vec<_>, _>>()?` — short-circuits on the first error.
- Combinators for transforming without unwrapping: `.map`, `.map_err`, `.and_then`, `.ok_or`, `.ok_or_else`, `.unwrap_or`, `.unwrap_or_else`, `.unwrap_or_default`. Reach for `.map_err` to translate a foreign error at a boundary.

## `.unwrap()` / `.expect()` — banned on shipping paths

They panic on `Err`/`None`. In library and production code that is a landmine.

- **Allowed:** tests, examples, benches, prototypes/spikes, `build.rs`, and `main` *only* when you genuinely want the process to abort with a message (prefer returning `anyhow::Result<()>` from `main` instead — see below).
- **Not allowed:** anywhere a caller could hand you data that makes it panic. Every surviving `.unwrap()` on a shipping path is a review finding.
- If you can *prove* it never fails, that proof belongs in an `.expect("reason the invariant holds")` message, not a bare `.unwrap()`. `expect` documents *why it's safe*; `unwrap` documents nothing. Even then, prefer restructuring so the impossibility is encoded in the types.
- `unwrap_or`, `unwrap_or_else`, `unwrap_or_default` are **not** the banned `unwrap` — they provide a fallback and never panic. Use them freely.

## Library errors: `thiserror`

For any library crate (a `lib.rs` others depend on), define an error **enum** with `thiserror`. This gives callers a typed, matchable error and free `From` conversions.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("user {0} not found")]
    NotFound(UserId),

    #[error("invalid email: {0}")]
    InvalidEmail(String),

    #[error("database error")]
    Database(#[from] sqlx::Error),   // `?` on a sqlx::Error now Just Works

    #[error("connection pool exhausted")]
    PoolExhausted,
}
```

Rules:

- One error enum per crate (or per bounded module) — the crate's public error contract. Name it `<Domain>Error` or just `Error` in a focused module.
- `#[error("...")]` messages are lowercase, no trailing period, no "error:" prefix (the `Display` chain adds context). They describe *what failed*, not "an error occurred".
- `#[from]` for wrapping a lower-level error you propagate as-is. `#[source]` to attach a cause without a `From`.
- Don't leak dependency types in your public error signature unless you mean to (wrapping `sqlx::Error` couples your API to sqlx). For a stable API, map it to a domain variant with `.map_err`.
- Never define an error type as a bare `String` (`Err("bad".to_string())`) — it's unmatchable and unconvertible. Stringly-typed errors are a review finding.

## Application errors: `anyhow`

For a binary / application top level (handlers, `main`, glue code) where you don't need callers to match on the error variant, use `anyhow`.

```rust
use anyhow::{Context, Result};

fn load_config(path: &Path) -> Result<Config> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("reading config from {}", path.display()))?;
    let cfg: Config = toml::from_str(&raw)
        .context("parsing config as TOML")?;
    Ok(cfg)
}

fn main() -> Result<()> {
    let cfg = load_config(Path::new("app.toml"))?;
    run(cfg)
}
```

Rules:

- `anyhow::Result<T>` (`= Result<T, anyhow::Error>`) as the return of application functions; `?` propagates anything.
- **Always add `.context(...)` / `.with_context(...)`** at each boundary as the error crosses it — this builds the human-readable chain that makes a production log actionable ("parsing config as TOML: expected value at line 4"). A bare `?` with no context loses the trail. Use `.with_context(|| ...)` (lazy closure) when building the message allocates.
- `anyhow::bail!("...")` for an early return, `anyhow::ensure!(cond, "...")` for a checked precondition.
- **`thiserror` for libraries, `anyhow` for binaries** is the rule of thumb. A library returning `anyhow::Error` forces its callers to give up typed handling — don't do it in a `lib.rs` meant for reuse.
- Never `Box<dyn std::error::Error>` as the house error type — `anyhow::Error` is strictly better (context, backtraces, downcasting). Bare `Box<dyn Error>` in new code is a smell.

## When panicking is correct

`panic!`, `unreachable!`, `todo!`, `unimplemented!`, `assert!`, `debug_assert!`:

- `assert!` / `debug_assert!` to check invariants at the boundary of `unsafe` or a performance-critical assumption — fail fast, loudly, in a bug.
- `unreachable!("...")` only when you can *prove* the branch is impossible; the message states the proof.
- `todo!()` / `unimplemented!()` are fine *during* development but must not reach a commit that claims the feature is done — they're a review finding on a "finished" path.
- Panicking across an FFI boundary is undefined behavior — never let a panic unwind into C. Use `catch_unwind` at the boundary.
- In async tasks, a panic aborts only that task (tokio) but you lose the work silently — prefer returning `Result` from spawned tasks and handling the `JoinError`.

## Option is not Result

- `Option<T>` models "a value may be absent" as a *normal* state, not a failure. Don't force it into `Result` unless absence *is* an error here — then `.ok_or(Error::Missing)?` / `.ok_or_else(...)`.
- `?` works on `Option` too (in a function returning `Option`). Don't mix them without an explicit conversion.

## Anti-patterns (flag on sight)

- `.unwrap()` / `.expect()` on a shipping path.
- `Err("some string".to_string())` or `Result<T, String>` as a public error type — unmatchable.
- `Box<dyn Error>` as the default error type in new code — use `anyhow` (bin) or a `thiserror` enum (lib).
- `anyhow` in a library's public API — leaks an untyped error to consumers.
- `?` with no `.context()` in an `anyhow` app — the failure will be un-diagnosable in prod logs.
- Swallowing errors: `let _ = fallible();` or `if let Ok(x) = ...` that silently drops the `Err`. Log it or propagate it — [[engineering-philosophy]] "Investigate, Don't Mask".
- `.unwrap()` inside `.map()`/iterator closures to dodge the fact the closure is fallible — use `.collect::<Result<_,_>>()` instead.
- Matching on an error's `Display` string (`if e.to_string().contains("timeout")`) instead of on a typed variant.

## Verification checklist

- [ ] No `.unwrap()`/`.expect()` on a non-test shipping path (fallbacks like `unwrap_or_else` are fine).
- [ ] Library crates return a `thiserror` enum, not `anyhow`/`String`/`Box<dyn Error>`.
- [ ] Binary/app code uses `anyhow::Result` with `.context()` at each boundary.
- [ ] No error is silently swallowed (`let _ =`, dropped `Err`).
- [ ] Panics (`panic!`/`unreachable!`/`assert!`) appear only for genuine invariant violations, each justified.
- [ ] No `todo!()`/`unimplemented!()` on a path the change claims is complete.

## Cross-references

- [[rust-conventions]] — the naming, layout, and `Result`-first summary this skill expands.
- [[rust-ownership]] — error types often wrap owned data; when to clone vs borrow into an error.
- `running-tdd-cycles` — write the failing test for the error path first (bad input → expected `Err(variant)`).
- `reviewing-changes` — unwrap/panic/stringly-typed-error checks fold into the code-quality pass.
- `engineering-philosophy` — Fail-Fast and Investigate-Don't-Mask drive these rules.