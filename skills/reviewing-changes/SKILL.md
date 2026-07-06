---
name: reviewing-changes
description: "Strict five-pass review of a Rust diff: code quality, security, architecture, acceptance, AI-native. Harsh, specific, teaches. Source of rules is rust-conventions/rust-error-handling/rust-ownership."
allowed-tools: Read, Grep, Glob, Bash(git diff *), Bash(git log *), Bash(git show *), Bash(git status *), Bash(git rev-parse *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh pr list *), Bash(cargo fmt *), Bash(cargo clippy *), Bash(cargo test *), Bash(cargo audit *), Bash(cargo deny *), WebSearch, WebFetch
---

## Stance

Review hard. This user is learning Rust and backend, and explicitly wants blunt, thorough feedback that does **not** let sloppy or spaghetti code through. Do not soften findings to be polite; do not wave through "it compiles" or "the test passed". Every finding names the rule, the severity, the location, and the concrete fix — teach *why*, don't just flag. But calibrate severity honestly (below): harshness is in the *coverage and directness*, not in inflating every nit to Critical.

Run the five passes in order. Findings flow into one combined verdict.

## 1. Read the rules

Before any pass, internalise the rule skills the diff touches — they are the **source of truth**, don't invent new standards:

- [[rust-conventions]] — naming, layout, fmt/clippy gates, forbidden patterns, the beginner-smell catalog.
- [[rust-error-handling]] — `Result`/`?`, `thiserror`/`anyhow`, banned `.unwrap()`/`panic!` on shipping paths.
- [[rust-ownership]] — clone-spam, reflexive `Rc<RefCell>`, lifetime/borrow smells.
- [[rust-security]] — the full Pass 2 checklist: unsafe soundness, overflow, panic-as-DoS, injection, secrets, deps.
- `engineering-philosophy` — KISS/YAGNI/DRY/SOLID/Fail-Fast weights.
- Plus `reference/beginner-antipatterns.md` — the fast checklist of the mistakes a Rust newcomer makes most.

## 2. See the change

```
git diff <base>...HEAD
git log <base>..HEAD --oneline
```

For a GitHub PR:

```
gh pr view <N>
gh pr diff <N>
```

## 3. Pass 1 — Code quality

Check, in order:

- **Tooling gate (run it, don't assume).** `cargo fmt --all -- --check` (zero diffs), `cargo clippy --all-targets --all-features -- -D warnings` (zero warnings), `cargo test --all-features` (green). A failing gate is at least Major; a silenced lint (`#[allow]` with no reason) is a finding.
- **Error-handling violations** ([[rust-error-handling]]) — `.unwrap()`/`.expect()`/`panic!`/`todo!` on a shipping path (Critical→Major); `Result<T, String>` or `Box<dyn Error>` as a public error type; `anyhow` leaking from a library API; `?` with no `.context()` in app code; swallowed errors (`let _ =`, dropped `Err`).
- **Ownership violations** ([[rust-ownership]]) — `.clone()`/`.to_string()` added only to satisfy the borrow checker; reflexive `Rc<RefCell<T>>`/`Arc<Mutex<T>>`; a lock/`RefCell` guard held across `.await`; `&Vec`/`&String` params instead of `&[T]`/`&str`.
- **Philosophy violations** — over-engineering (KISS/YAGNI: speculative generics, premature traits, macro machinery), duplication (DRY), magic behaviour (No Magic: `Deref` abuse, control-flow-hiding macros).
- **SOLID / SRP** — a module or function that grew a second responsibility; the "does five things" spaghetti function (parse+validate+fetch+transform+persist in one body).
- **Naming, readability, complexity** — non-idiomatic names (clippy's `wrong_self_convention`, acronym casing), function length, parameter lists (a `bool` param that should be an enum), deeply nested `match`/`if let` that `?`/`let ... else`/combinators would flatten, clever one-liners hiding intent.
- **Test coverage** — was the change tested? If TDD applied, was the failing test committed first? Are error paths tested, not just the happy path?
- **`unsafe` hygiene** — every `unsafe` block has a `// SAFETY:` comment justifying the invariant; `unsafe` isn't used to dodge the borrow checker.

## 4. Pass 2 — Security audit

Rust removes memory-safety bugs in safe code but not logic/security bugs. [[rust-security]] is the full source of truth for this pass (the `security-auditor` agent reads it); the summary below is the fast checklist. Check, in order:

- **`unsafe` soundness** — data races, aliasing violations, invalid pointer derefs, uninitialised memory, breaking an invariant a safe API relies on. Any `unsafe` in the diff gets scrutiny.
- **Integer overflow / truncation** — release builds *wrap* on overflow silently. Use `checked_*`/`saturating_*`/`wrapping_*` deliberately; flag `as` casts that truncate (`u64 as u32`, `usize as i32`) — clippy's `cast_possible_truncation`.
- **Panics as DoS** — a reachable `.unwrap()`/`panic!`/array index/`unwrap`-on-parse on attacker-controlled input can crash a server thread/task. Treat as a security finding, not just style.
- **Injection** — SQL via string-formatted queries (use `sqlx` bound params / query macros, never `format!` into SQL); command injection via `std::process::Command` with unsanitised args; path traversal from user input into `Path`.
- **Secrets** — hardcoded keys/tokens, secrets in logs (`tracing`/`log`) or error `Display`, `Debug` on a struct that prints a password. Prefer `secrecy` / redacted `Debug`.
- **Deserialization** — untrusted input into `serde` with unbounded size/recursion; `bincode`/`rmp` from untrusted sources without limits.
- **Vulnerable dependencies** — `cargo audit` / `cargo deny check advisories` for RUSTSEC advisories; unmaintained crates; yanked versions.
- **AuthZ / access control** — missing authorization checks, IDOR, privilege escalation in handler logic.
- **Crypto** — weak/rolled-own primitives (hand-rolled crypto is Critical — use `ring`/`RustCrypto`), predictable RNG (`rand` vs a CSPRNG for tokens), timing-unsafe comparisons for secrets (use `subtle`).

## 5. Pass 3 — Architecture consistency

- **Architecture map** — does the diff respect `docs/architecture.md` (or equivalent) module/crate responsibilities?
- **Layer/crate violations** — dependencies pointing the wrong way (domain crate importing the web/infra crate); a workspace member reaching past its boundary.
- **Boundary erosion** — items made `pub` that should be `pub(crate)`/private; a public API surface growing without need; circular module dependencies.
- **Custom code where a crate exists** — **presumptive Critical** when the diff reinvents what the ecosystem solved (serialization, async runtime, HTTP, crypto, encoding, retry/backoff, connection pooling, arg parsing). Three sub-checks:
  - **Already in tree** — if `Cargo.lock` already pulls a crate exporting this, the hand-rolled version is Critical regardless of size. Don't `use serde` for one type and hand-roll the rest.
  - **Justification still valid** — a comment that justified hand-rolling earlier ("avoid the dep", "smaller binary") must still hold for *this* diff. Once the dep is in the tree, the reason expired.
  - **What to grep for** — custom encoders for standard formats, hand-rolled retry loops, bespoke connection pools, hand-written token verification, custom crypto.
- **Trait design** — one god-trait where several small ones fit (ISP); a trait with one impl and no reason to be a trait (YAGNI); `dyn` dispatch where a generic or enum was simpler.

## 6. Pass 4 — Acceptance / intent alignment

Does the diff actually solve the contract — linked issue, PR description, or task spec? Cover three axes:

- **Drift** — implements something related but not the asked feature.
- **Partial** — covers some required behaviours, misses others (often the error/edge paths).
- **Overreach** — includes changes the issue didn't request (off-scope refactors, a `cargo fmt` sweep of untouched files, speculative abstraction).

## 7. Pass 5 — AI-Native-Coding practices

- **R1** — Comments explain WHY not WHAT; `// SAFETY:` on `unsafe`; no tombstoned/commented-out code.
- **R2** — Durable agent context lives in an instruction file: at least one of `AGENTS.md` / `CLAUDE.md` / `.cursor/rules/` at repo root.
- **R3** — Tests prefer real objects over mocks; mock only at I/O boundaries (DB, network). Rust makes real objects cheap — favor them.
- **R5** — Small commits, decomposed PRs (see `committing-changes`); the diff is reviewable.
- **R7** — Minimize always-loaded context: delete dead code, don't `#[allow(dead_code)]`-tombstone it.
- **R8** — Mechanical checks (fmt, clippy, test, audit) belong in CI.

## Output

```
## Quality Gate Summary

| Review              | Verdict        | Critical | Major | Minor |
|---------------------|----------------|----------|-------|-------|
| Code                | pass/warn/fail | N        | N     | N     |
| Security            | pass/warn/fail | N        | N     | N     |
| Architecture        | pass/warn/fail | N        | N     | N     |
| Acceptance          | pass/warn/fail | N        | N     | N     |
| AI-Native Practices | pass/warn/fail | N        | N     | N     |

**Overall**: PASS / NEEDS WORK / FAIL

### Action items
1. <Critical/Major items, ordered>
```

For each individual finding:

- **Rule** — which rule was violated (cite the skill: `rust-error-handling` "unwrap banned", etc.) or "best practice" if uncodified.
- **Severity** — Critical / Major / Minor.
- **Location** — `file:line`.
- **Issue** — what's wrong and (for security) the attack vector or the panic trigger.
- **Fix** — concrete suggestion, with a short corrected code snippet when it clarifies.

## Severity calibration

- **Critical** — could ship a bug, a panic-on-input DoS, a CVE, or data loss *today*: `.unwrap()` on request data, SQL string-interpolation, unsound `unsafe`, hand-rolled crypto, a hand-rolled primitive already in the lockfile.
- **Major** — will hurt within months: an SRP-violating god-function, clone-spam in a hot path, a stringly-typed public error, missing error-path tests, a silenced clippy lint.
- **Minor** — style and polish: naming nits, a comment that restates code, an import grouping, a slightly-too-long function that's still clear.

## Behavioural traits

- Blunt and thorough, but constructive and educational — teach the rule, don't just flag it. The user asked for harsh; harsh means *complete coverage and directness*, not inflated severities or insults.
- Specific and actionable. "This is too complex" without a fix is useless.
- Severity matches reality (above). Don't cry Critical on a naming nit; don't bury a panic-on-input as Minor.
- Practical over theoretical. If an attack needs three impossible preconditions, mark it Minor.
- Read-only. This skill never edits the diff; it reports.

## Cross-references

- `running-tdd-cycles` — preceding workflow; review confirms TDD discipline and error-path coverage.
- `committing-changes` — commit-message + branch hygiene fold into the code-quality pass.
- [[rust-conventions]] / [[rust-error-handling]] / [[rust-ownership]] / [[rust-security]] / [[rust-architecture]] — the rules the diff is checked against.
- `engineering-philosophy` — KISS/YAGNI/DRY/SOLID weights for the code-quality and architecture passes.

## Reference

- [reference/beginner-antipatterns.md](reference/beginner-antipatterns.md) — the fast checklist of the Rust/backend mistakes a newcomer makes most, with the fix for each.