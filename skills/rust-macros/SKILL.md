---
name: rust-macros
description: Write Rust macros only when a function, generic, or trait genuinely can't do the job — then do it correctly. Covers `macro_rules!` (fragment specifiers, repetition, hygiene, `$crate`), procedural macros (derive/attribute/function-like in a `proc-macro` crate with syn/quote), good compile-error spans, and `trybuild` tests. Use whenever you're tempted to reach for a macro, or reviewing one.
---

# Rust Macros

Macros are the heaviest tool in Rust — they run at compile time, are harder to read, debug, and test than ordinary code, and they fight editor/IDE support. **The first job of this skill is to talk you out of one.** Reach for a function, generic, or trait first; a macro is justified only when those genuinely can't express the pattern. Pair with [[engineering-philosophy]] (YAGNI/KISS — a macro is rarely the simple choice) and [[rust-architecture]] (generics and traits are the usual right answer).

## Do you actually need a macro?

Ask in order — stop at the first "yes":

- **A generic function or method?** Parameterizing over types → generics, not a macro.
- **A trait (with a default impl or blanket impl)?** Shared behavior across types → a trait.
- **A `const` / builder / plain function?** Compile-time values and construction rarely need macros.

A macro earns its place only for things ordinary code can't do:
- **Variadic** call shapes (`vec![1, 2, 3]`, `println!` with N args).
- **Eliminating real, repetitive boilerplate** that no generic/trait can factor out (e.g. implementing a trait across many concrete types, generating test cases).
- **A small DSL** or compile-time-checked literal.
- **Deriving** code from a type's structure (`#[derive(...)]`).

If a helper function or generic gets you 90% there, use it and stop. "It'd be neat as a macro" is not a reason.

## `macro_rules!` — the declarative kind

Prefer `macro_rules!` over a proc macro when it suffices; it's simpler and needs no extra crate.

```rust
/// Build a HashMap from key => value pairs.
macro_rules! map {
    ($($key:expr => $val:expr),* $(,)?) => {{
        let mut m = ::std::collections::HashMap::new();
        $( m.insert($key, $val); )*
        m
    }};
}
```

- **Fragment specifiers** match different syntax: `expr`, `ty`, `ident`, `pat`, `path`, `block`, `literal`, `tt` (token tree). Pick the *narrowest* one that fits — `expr` over `tt` — for better errors.
- **Repetition** `$( ... )*` / `,*` / `?` handles variadics; support a trailing comma with `$(,)?`.
- **Hygiene:** identifiers a macro introduces don't collide with the caller's. Don't try to "leak" a variable name into the caller's scope — that's a smell.
- **`$crate`** — reference your own crate's items as `$crate::foo`, never bare `foo`, so the macro works when called from another crate. Reference std as `::std::...` (leading `::`).
- **Export** with `#[macro_export]` (puts it at crate root); document it with `/// ...` like any public item.

## Procedural macros — the compiled kind

Needed for `#[derive(...)]`, custom attributes (`#[route(...)]`), and function-like macros that inspect token *structure*. They live in a **separate crate** with `proc-macro = true` in `Cargo.toml`, and can't be used in the same crate that defines them.

- **Toolchain:** `syn` (parse tokens into an AST), `quote!` (generate tokens), `proc-macro2` (testable token types). `darling` parses attribute arguments ergonomically.
- **Three kinds:** `#[proc_macro_derive(Name)]`, `#[proc_macro_attribute]`, `#[proc_macro]` (function-like).
- **Never `panic!` / `.unwrap()` on malformed input.** Emit a real compile error pointing at the offending span: `syn::Error::new_spanned(tokens, "message").to_compile_error()`. The user should see a caret under *their* code, not a proc-macro backtrace ([[rust-error-handling]] — surface the error, don't crash).
- **Preserve spans** so errors and go-to-definition land on the caller's tokens.
- Keep the generated code readable and minimal — it's still code someone will debug via `cargo expand`.

## Testing macros

Macros need tests like any other logic ([[rust-testing]]):

- **Behavior:** call the macro in a normal `#[test]` and assert on what it produced (`map! {}` builds the right `HashMap`).
- **Compile-fail:** `trybuild` asserts that *misuse* fails to compile with the expected message — this is how you test a macro's error handling and its input validation.
- **Expansion:** `cargo expand` (and `macrotest`) to eyeball/snapshot the generated code.

## Anti-patterns (flag on sight)

- A macro where a **generic function, trait, or plain fn** would do — the default mistake ([[engineering-philosophy]]).
- `macro_rules!` referencing crate items as bare `foo` instead of `$crate::foo` — breaks for external callers.
- A macro that **captures or introduces caller-visible identifiers** (fighting hygiene), or one that hides `return`/`?`/control flow so call sites don't read honestly.
- Proc macros that `panic!`/`unwrap` on bad input instead of emitting a spanned `compile_error!`.
- Over-broad `tt` matchers where `expr`/`ty` would give better errors.
- Undocumented, un-`trybuild`-tested public macros.
- Reaching for a proc macro (heavy: extra crate, syn/quote, compile cost) when `macro_rules!` — or no macro at all — suffices.

## Verification checklist

- [ ] A function/generic/trait was ruled out first, with a real reason a macro is needed.
- [ ] `macro_rules!` chosen over a proc macro unless token-structure inspection is genuinely required.
- [ ] Crate items referenced via `$crate::`; std via `::std::`; hygiene not fought.
- [ ] Proc macros emit spanned `compile_error!` on bad input — no `panic!`/`unwrap`.
- [ ] The macro is documented and has behavior tests plus `trybuild` compile-fail tests.
- [ ] Generated code stays minimal and readable (checked via `cargo expand`).

## Cross-references

- `engineering-philosophy` — YAGNI/KISS: a macro is almost never the simplest thing that works; justify it.
- [[rust-architecture]] — generics and traits are the usual answer; macros are a last resort at the edges.
- [[rust-error-handling]] — proc macros surface errors as spanned compile errors, not panics.
- [[rust-testing]] — `trybuild` compile-fail tests plus behavior tests; `cargo expand` to inspect output.
- [[rust-conventions]] — document and name macros like any public API; no `unwrap` in proc-macro logic.