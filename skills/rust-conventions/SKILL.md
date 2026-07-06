---
name: rust-conventions
description: Apply idiomatic Rust conventions — naming, module/crate layout, rustfmt + clippy (pedantic) gates, no unwrap/panic in library code, visibility discipline, Result-first error flow, and the common-beginner-mistake catalog. Use whenever editing or creating any `.rs` file (presence of `Cargo.toml`).
---

# Rust Conventions

The source-of-truth rulebook for any Rust code in this project. Pair with [[rust-error-handling]] for `Result`/error-type design and [[rust-ownership]] for borrow-checker and lifetime decisions. `reviewing-changes` checks a diff against *these* rules — keep them concrete.

## Detect first

Run once per session and cache the result; do not assume:

- `Cargo.toml` → the `[package] edition` (2015/2018/2021/2024) caps available syntax; the `[dependencies]` list tells you what is already in the tree (never hand-roll what a listed crate provides — see [[reviewing-changes]]).
- `Cargo.toml` workspace → is this a single crate or a `[workspace]` with members? New code lands in the crate that already owns the domain.
- `rust-toolchain.toml` / `rust-toolchain` → the pinned toolchain version and components. Write to that version, not to the newest Rust you know.
- `clippy.toml`, `rustfmt.toml`, and `#![deny(...)]` / `#![warn(...)]` in `lib.rs`/`main.rs` → the lint level the project already enforces. Honor it; don't loosen it.
- `deny.toml` (cargo-deny) → license/advisory policy for dependencies.

If any of these are ambiguous, ask before assuming a default.

## The opinionated stack (this user's default)

Unless the project's `Cargo.toml` says otherwise, assume and steer toward:

- **Errors** — `thiserror` for library error enums, `anyhow` for application/binary top-level. See [[rust-error-handling]].
- **Async runtime** — `tokio` (multi-threaded runtime). See [[rust-async]] once it lands.
- **Web** — `axum` for HTTP services.
- **Serialization** — `serde` + `serde_json`.

Before introducing any *other* crate for these roles, say so and give the reason. Don't silently pull in `actix-web` when the project is on `axum`, or `error-chain` when `thiserror` is the house style.

## Formatting & lints are not optional

These are the gate. A change is not "done" until all pass clean:

```sh
cargo fmt --all -- --check      # formatting: zero diffs
cargo clippy --all-targets --all-features -- -D warnings   # lints: zero warnings
cargo test --all-features        # tests green
```

- **`rustfmt` is law.** Never hand-format against it, never sprinkle `#[rustfmt::skip]` to dodge it. If output looks bad, the code structure is the problem.
- **Clippy at `-D warnings`.** A clippy warning is a build failure here. Do not `#[allow(...)]` a lint to silence it without a one-line `// reason:` and a genuine justification — an unexplained `#[allow]` is itself a review finding.
- **Recommend pedantic for new crates.** For greenfield code add `#![warn(clippy::pedantic)]` at the crate root; selectively `allow` the few pedantic lints that fight the project's style, each with a reason.
- **Starter config templates** ship with this skill — copy them to the repo root as a baseline (`<skills>` = this plugin's `skills/` directory): `cp <skills>/rust-conventions/templates/{clippy.toml,rustfmt.toml,deny.toml} .`. `clippy.toml`/`rustfmt.toml` tune thresholds and formatting; `deny.toml` drives `cargo deny` (advisories + license policy). For a new crate, also enforce the no-unwrap rule in code: `#![deny(clippy::unwrap_used, clippy::expect_used)]` (relaxed in tests).

## Naming (RFC 430, enforced by clippy)

- Types, traits, enum variants: `PascalCase`. Modules, functions, methods, fields, locals, macros: `snake_case`. Constants & statics: `SCREAMING_SNAKE_CASE`.
- Acronyms are one word in a name: `HttpClient`, `parse_url`, `user_id` — never `HTTPClient` or `parseURL`.
- Conversions follow the standard verbs: `as_x` (cheap borrow), `to_x` (expensive/owned clone), `into_x` (consuming). Don't name a consuming method `to_`.
- Getters are the bare field name (`fn name(&self) -> &str`), not `get_name`. Setters `set_name`.
- Booleans read as predicates: `is_empty`, `has_capacity`, `should_retry`.
- Iterator-returning methods: `iter` (`&`), `iter_mut` (`&mut`), `into_iter` (owned).
- No Hungarian notation, no type suffixes (`user_str`, `count_i32`) — the type system already carries that.

## Comments

Comments explain **why**, never **what**. The code says what.

- A comment earns its place only when it states something the code cannot: an invariant, a non-obvious *why*, a `// SAFETY:` justification on `unsafe`, a magic-number derivation, or a link to a spec/issue.
- `// SAFETY:` on every `unsafe` block is **mandatory** — it documents the invariant that makes the block sound. An `unsafe` block with no safety comment is a review finding.
- Delete commented-out code; git remembers it. Don't leave `// old:` tombstones.
- Public API items (`pub fn`, `pub struct`, `pub trait`, and the crate root) get `///` doc comments **with runnable `# Examples`** where they clarify usage; internal (`pub(crate)`/private) items usually don't need doc comments — a good name beats a doc.
- `//!` module-level docs at the top of a `lib.rs`/`mod.rs` when the module's purpose isn't obvious from its name.

## Module & file layout

- One responsibility per module. A `mod foo` is a `foo.rs` (or `foo/mod.rs` with submodules). Prefer the flat `foo.rs` + `foo/` sibling-directory form (2018+ style) over `foo/mod.rs`.
- Keep `main.rs` a thin entry point: parse args/config, build the app, run it. Domain logic lives in `lib.rs`-rooted modules so it is testable and reusable.
- Split a file before it sprawls. A single `.rs` past ~400–500 lines is a smell — look for a second responsibility to extract.
- `use` grouping: `std` first, then external crates, then `crate::`/`super::`/`self::`, each block separated by a blank line (this is what `rustfmt`'s `group_imports` does — enable it if the project uses nightly rustfmt).
- Avoid glob imports (`use foo::*`) except for preludes (`use std::prelude`, a crate's documented `prelude`) and inside a test module (`use super::*`).

## Visibility discipline

- Default to **private**. Add `pub(crate)` only when another module needs it; `pub` only for the crate's intended public API.
- Don't make a field `pub` for convenience — expose a method or constructor. A `pub` field is a permanent API commitment and lets callers break your invariants.
- Prefer constructors (`fn new(...) -> Self`, or a builder) that validate inputs over `pub` fields that let anyone build an invalid value. Push validation to the type's boundary (parse, don't validate — make illegal states unrepresentable).

## Error flow (summary — full rules in [[rust-error-handling]])

- **`Result<T, E>` at every fallible boundary.** Panicking is for *bugs* (broken invariants), not for *expected* failures like bad input, missing files, or network errors.
- **`.unwrap()` / `.expect()` are banned in library and production paths.** They are acceptable only in tests, examples, prototypes, and `build.rs`. In `main` prefer returning `anyhow::Result<()>` and using `?`. Every surviving `.unwrap()` in shipping code is a review finding — see [[rust-error-handling]].
- **`?` over `match` for propagation.** Reserve `match`/`if let` for when you actually handle the error here.
- **No `panic!`, `todo!`, `unimplemented!`, `unreachable!` on a live code path.** `unreachable!` is allowed only when you can prove the branch is impossible, with a comment saying why.

## Types & data modeling

- **Make illegal states unrepresentable.** Model with enums and newtypes instead of stringly-typed data and boolean flags. A `Status` enum beats a `String`; a `UserId(u64)` newtype beats a bare `u64` you might swap with an `OrderId`.
- **Borrow in function signatures.** Take `&str` not `&String`, `&[T]` not `&Vec<T>`, `&T` not `&Box<T>` — accept the widest set of callers. Take ownership (`String`, `Vec<T>`) only when the function genuinely needs to keep or consume the value.
- **Derive the obvious traits**: `#[derive(Debug)]` on nearly everything; add `Clone`, `PartialEq`, `Eq`, `Hash`, `Default`, `Copy` when the semantics warrant — don't derive `Copy` on something expensive, don't derive `Clone` just to escape the borrow checker (that's a [[rust-ownership]] smell).
- Implement `From`/`TryFrom` for conversions rather than ad-hoc `to_x` free functions; then `?` and `.into()` work for free.
- Prefer `impl Trait` in argument position for simple generic bounds and in return position for "returns some iterator/future" — but name the type when it's part of your public contract.

## Iterators over index loops

- Prefer iterator adapters (`map`, `filter`, `find`, `fold`, `collect`) to manual `for i in 0..len` indexing — it's clearer and eludes off-by-one and bounds panics.
- But don't build a baroque adapter chain that a plain `for` loop would express more readably. Readability wins; clippy's `needless_range_loop` catches the clear cases.
- `collect::<Result<Vec<_>, _>>()` to turn an iterator of `Result`s into a `Result` of a `Vec` — idiomatic short-circuit.

## Forbidden / smell patterns (flag on sight)

- `.unwrap()` / `.expect()` in non-test shipping code (see above).
- `.clone()` sprinkled to silence the borrow checker — fix the borrow instead ([[rust-ownership]]).
- `Rc<RefCell<T>>` / `Arc<Mutex<T>>` reached for reflexively to model graphs or shared mutation before simpler ownership was tried — often a design smell in a beginner's code. Justify it.
- `unsafe` without a `// SAFETY:` comment, or used to dodge the borrow checker rather than for a real FFI/perf reason.
- `String` allocation where a `&str` slice would do; `.to_string()` / `format!` in hot loops.
- Stringly-typed APIs (functions taking `&str` for what should be an enum), boolean parameters that should be an enum (`resize(true)` — true what?).
- `mod.rs` files stuffed with logic instead of just re-exports.
- `pub` fields exposing internal invariants; `pub` on items that don't need to be public.
- Blanket `#[allow(...)]` at crate or module scope to mute clippy wholesale.
- Deeply nested `match`/`if let` where `?`, `let ... else`, or a combinator (`map`, `and_then`, `unwrap_or_else`) flattens it.
- Functions doing five things (parse + validate + fetch + transform + persist in one body) — the classic beginner "spaghetti" function. Extract.

## Verification checklist (every change)

- [ ] `cargo fmt --all -- --check` — zero diffs.
- [ ] `cargo clippy --all-targets --all-features -- -D warnings` — zero warnings.
- [ ] `cargo test --all-features` — green.
- [ ] No new `.unwrap()`/`.expect()`/`panic!`/`todo!` on a shipping path.
- [ ] No new `.clone()` added only to satisfy the borrow checker.
- [ ] Every new `unsafe` block has a `// SAFETY:` comment.
- [ ] Function signatures borrow (`&str`, `&[T]`) unless ownership is genuinely needed.
- [ ] New public items are minimally `pub` and carry `///` docs; nothing is `pub` that didn't need to be.
- [ ] No comments that restate the code; comments explain *why* only.
- [ ] No file grew a second responsibility; no function does five things.

## Cross-references

- [[rust-error-handling]] — `Result`, `?`, `thiserror`/`anyhow`, when panicking is correct.
- [[rust-ownership]] — borrow checker, lifetimes, when `clone`/`Rc`/`Arc` is right vs a crutch.
- `reviewing-changes` — the five-pass audit checks a diff against these rules.
- `running-tdd-cycles` — `cargo test` / `cargo nextest` framework cues.
- `engineering-philosophy` — KISS, YAGNI, DRY, Fail-Fast weights behind these rules.