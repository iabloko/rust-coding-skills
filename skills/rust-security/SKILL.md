---
name: rust-security
description: "Security-review Rust code — unsafe soundness, integer overflow/truncation, panic-as-DoS, injection (SQL/command/path), deserialization limits, secret handling, dependency advisories (cargo audit/deny), crypto, authz, and resource exhaustion. Use whenever reviewing a diff for security, hardening a handler, or adding unsafe/crypto/untrusted-input handling. Backend defaults: sqlx, axum, tokio."
---

# Rust Security Review

Rust's type system eliminates memory-safety bugs *in safe code* — use-after-free, data races, buffer overflows are gone by construction. It does **not** eliminate logic bugs, injection, unsound `unsafe`, panics-as-DoS, secret leaks, or vulnerable dependencies. This skill is the Rust-specific security checklist. It is the source of truth for the `security-auditor` agent and for Pass 2 of [[reviewing-changes]]. Pair with [[rust-error-handling]] and [[rust-async]].

## Threat-model framing

For each finding name the **attack vector**: which actor, which precondition, which impact. A theoretical issue behind three impossible preconditions is Minor; a `.unwrap()` on a request body is Critical (any client crashes the task). Practical over theoretical.

## 1. `unsafe` soundness (highest scrutiny)

Any `unsafe` in the diff gets the hardest look — it's where Rust's guarantees are suspended and you reassume responsibility.

- **Every `unsafe` block needs a `// SAFETY:` comment** stating the invariant that makes it sound. No comment → finding (Major minimum).
- Check for: dangling/invalid pointer derefs, aliasing violations (two `&mut` to the same data), out-of-bounds via `get_unchecked`, uninitialized memory (`MaybeUninit` misuse, `mem::zeroed` on non-zeroable types), breaking an invariant that safe code downstream relies on, `transmute` between incompatible layouts.
- **Data races**: `unsafe impl Send`/`Sync` on a type that isn't actually thread-safe is Critical — it lets safe code trigger UB.
- **FFI**: a panic unwinding across an `extern "C"` boundary is UB — wrap Rust callbacks in `catch_unwind`. Validate all pointers/lengths coming from C. Assume C gives you lies.
- Tools: `cargo miri test` detects many UB classes at runtime; `cargo geiger` counts `unsafe` usage across the tree.
- Best fix is often **delete the `unsafe`** — most `unsafe` in application code is avoidable (it was a perf hack or a borrow-checker dodge). Only keep it for genuine FFI or a measured, proven hot path.

## 2. Integer overflow & truncation

- **Release builds wrap silently.** `a + b` that overflows panics in debug, wraps in release — a silent wrong value (e.g. a length, an index, a balance). For values where overflow is a security concern, use `checked_add`/`checked_mul` (→ `Option`, handle `None`), `saturating_*`, or `wrapping_*` **deliberately** and visibly.
- **Truncating `as` casts** (`u64 as u32`, `usize as i32`, `i64 as u8`) silently drop bits — a size/length/offset can wrap to a small or negative value. Use `u32::try_from(x)?` and handle the error. Flag every narrowing `as` on a value derived from input (clippy `cast_possible_truncation`, `cast_sign_loss`).
- Allocation sized by untrusted input (`Vec::with_capacity(n)` where `n` is attacker-controlled) → validate the bound first; an attacker-chosen huge `n` is a memory-exhaustion DoS.

## 3. Panic = availability bug

A reachable panic on attacker-controlled input crashes the current task/thread — on a server that's a DoS. Treat panics on the request path as **security** findings, not style.

- `.unwrap()` / `.expect()` on parsed input, headers, path params, JSON bodies, DB rows.
- Slice indexing `xs[i]` / `s[a..b]` with an index/range derived from input → use `.get(i)` / `.get(a..b)`. String slicing on a non-char-boundary byte index panics.
- Integer division / remainder by an input-derived zero.
- `unreachable!`/`todo!`/`assert!` reachable from input.
- In `tokio`, a panicking task aborts silently and its work is lost — see [[rust-async]]; prefer `Result` from tasks.

## 4. Injection

- **SQL** — never `format!`/string-concatenate untrusted values into a query. Use `sqlx` bind parameters (`query!("... WHERE id = $1", id)`) or the ORM's parameterization. A `format!("... WHERE name = '{name}'")` is Critical. Note: table/column *names* can't be bound — if they're dynamic, allowlist them, never interpolate raw.
- **Command** — `std::process::Command` with untrusted args: pass args as separate `.arg(x)` items (no shell), never `sh -c "cmd {input}"`. Avoid a shell entirely; if unavoidable, allowlist.
- **Path traversal** — untrusted input joined into a `Path` can escape the intended dir (`../../etc/passwd`). Canonicalize and verify the result is under the allowed root; reject `..` components. Relevant for file-download/upload handlers.
- **Header/response splitting, log injection** — untrusted data into HTTP headers or log lines without sanitization (CRLF injection).

## 5. Deserialization & untrusted input size

- `serde` from untrusted input: bound the input size *before* parsing (axum `DefaultBodyLimit` / a `content-length` check). Unbounded body → memory DoS.
- Deeply nested JSON/recursive structures can blow the stack — limit depth where the format allows.
- `bincode`/`rmp`/other binary formats from untrusted sources: enable size limits; a length prefix an attacker controls can pre-allocate gigabytes.
- Validate *after* deserializing — `serde` gives you a well-typed value, not a *valid* one. Enforce domain invariants (ranges, non-empty, allowed enum) via newtypes/`TryFrom` ([[rust-architecture]]).

## 6. Secrets & sensitive data

- No hardcoded keys/tokens/passwords/connection strings in source. Load from env/secret manager; keep them out of the repo.
- **`Debug`/`Display` leaks**: a `#[derive(Debug)]` struct holding a password/token will print it in logs and error messages. Use the `secrecy` crate (`Secret<String>`) or a manual redacting `Debug` impl. An error enum that embeds a secret in its `Display` leaks it up the `?` chain into logs.
- No secrets in `tracing`/`log` output, in error responses returned to clients, or in URLs (query strings get logged).
- Constant-time comparison for secrets/tokens/MACs — `==` on a `&[u8]` short-circuits and leaks length/prefix via timing. Use `subtle::ConstantTimeEq` or `ring`'s verify.
- Zeroize sensitive buffers after use where it matters (`zeroize` crate) — Rust won't scrub freed memory for you.

## 7. Cryptography

- **Never hand-roll crypto** — rolling your own cipher, hash-based auth, or RNG is Critical. Use `ring`, the `RustCrypto` suite, `rustls` (not raw OpenSSL bindings unless required).
- Password hashing: `argon2`/`scrypt`/`bcrypt` (via `RustCrypto`), never a bare SHA/MD5.
- Randomness for tokens/keys/nonces: a CSPRNG (`rand::rngs::OsRng`, `getrandom`), **not** `rand::thread_rng` for security-critical values, never a seeded/`SmallRng`. Predictable nonce/IV reuse breaks the cipher.
- TLS: verify certificates (don't disable verification "to make it work" — that's Critical); pin/validate as the threat model requires.

## 8. Dependency & supply-chain

- **`cargo audit`** — RUSTSEC advisories against `Cargo.lock`. Any advisory on a dependency in the diff is at least Major.
- **`cargo deny check`** — advisories + license policy + banned/duplicate crates + untrusted sources, driven by `deny.toml`. Recommend it in CI.
- Yanked versions, unmaintained crates (RUSTSEC-*-unmaintained), a suspicious new transitive dep introduced by the change.
- `build.rs` and proc-macros run arbitrary code at build time — scrutinize a new dependency that ships either, especially from an untrusted source.
- Pin/commit `Cargo.lock` for reproducible builds (apps and libs by current convention).

## 9. AuthZ / access control

- Missing authorization checks in a handler (authentication ≠ authorization); IDOR — an object id from the request used to fetch data without verifying the caller owns it.
- Privilege escalation via a role/flag taken from client-controlled input.
- Middleware ordering in axum — an auth layer that doesn't actually wrap the protected routes.

## 10. Resource exhaustion / DoS

- Unbounded channels/queues/spawns under load-bearing traffic ([[rust-async]]) — no backpressure → OOM.
- Missing timeouts on outbound calls (a hung upstream ties up a task forever) and on inbound request handling. `tokio::time::timeout` everything that talks to the network.
- Missing rate limiting on expensive/auth endpoints.
- Regex from untrusted input (ReDoS) — bound it, or use the `regex` crate (linear-time, safe) rather than a backtracking engine.
- SSRF — a URL from user input fetched server-side; allowlist hosts, block internal ranges.

## Tooling

```sh
cargo audit                 # RUSTSEC advisories against Cargo.lock
cargo deny check            # advisories + licenses + bans (needs deny.toml)
cargo clippy -- -D warnings # catches many cast/overflow/panic lints
cargo miri test             # detects UB in unsafe code at runtime
cargo geiger                # counts unsafe usage across the dependency tree
```

## Output (when used as a review pass)

Standard `reviewing-changes` finding format, with the attack vector spelled out:

- **Rule** — the category above (e.g. "Injection — SQL", "Panic-as-DoS", "unsafe soundness").
- **Severity** — Critical / Major / Minor (see the framing at top; practical over theoretical).
- **Location** — `file:line`.
- **Issue** — what's wrong **and the attack vector** (actor → precondition → impact).
- **Fix** — concrete remediation with a short corrected snippet.

## Verification checklist

- [ ] Every `unsafe` block has a `// SAFETY:` comment; no `unsafe impl Send/Sync` on a non-thread-safe type.
- [ ] No `.unwrap()`/index/slice/`as`-truncation on attacker-controlled input on the request path.
- [ ] Overflow-sensitive arithmetic uses `checked_*`/`try_from`, not silent wrap/truncation.
- [ ] SQL uses bind params; `Command` uses separate args; paths are canonicalized and root-checked.
- [ ] Untrusted input is size-bounded before deserialization and validated after.
- [ ] No secrets in source, `Debug`/`Display`, logs, or error responses; secret compares are constant-time.
- [ ] No hand-rolled crypto; CSPRNG for tokens; TLS verification on.
- [ ] `cargo audit` / `cargo deny check` clean for deps the diff touches.
- [ ] Handlers enforce authorization (not just authentication); no IDOR.
- [ ] Bounded channels/concurrency, timeouts on network I/O, rate limits on expensive endpoints.

## Cross-references

- [[reviewing-changes]] — Pass 2 (Security) defers to this skill; the `security-auditor` agent reads it.
- [[rust-error-handling]] — panic-as-DoS and swallowed errors; `Result` over `.unwrap()`.
- [[rust-async]] — unbounded concurrency, missing timeouts, blocking-the-runtime as availability risks.
- [[rust-conventions]] — the `unsafe`/`// SAFETY:` and cast-lint rules summarized there.