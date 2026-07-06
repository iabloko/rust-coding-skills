# Rust / backend beginner anti-pattern checklist

A fast scan list for `reviewing-changes`. Each entry: the smell → why it's wrong → the fix. Grep the diff for these before the detailed passes. Ordered roughly by how often a Rust newcomer hits them.

## Error handling

| Smell | Why it's wrong | Fix |
|---|---|---|
| `.unwrap()` / `.expect()` on shipping path | Panics on `Err`/`None`; on request data it crashes the server task (DoS). | Return `Result`, propagate with `?`; or provide a fallback with `unwrap_or_else`. See [[rust-error-handling]]. |
| `Result<T, String>` / `Err("msg".into())` | Unmatchable, unconvertible error. Caller can't branch on it. | `thiserror` enum (lib) or `anyhow` (bin). |
| `Box<dyn Error>` as the house error type | No context, no backtrace, awkward downcasting. | `anyhow::Error` (bin) or a typed enum (lib). |
| `?` everywhere with no `.context()` | Prod log says "No such file (os error 2)" with no clue which file. | `.with_context(\|\| format!("reading {path}"))?` at each boundary. |
| `let _ = fallible();` / dropped `Err` | Silently swallows failure — Investigate-Don't-Mask violation. | Handle or propagate; at minimum log it. |
| `panic!`/`todo!`/`unimplemented!` on a "done" path | Ships an abort or an unfinished stub. | Implement it, or return an error. |

## Ownership & borrowing

| Smell | Why it's wrong | Fix |
|---|---|---|
| `.clone()` / `.to_string()` to silence the borrow checker | Masks a design/scope problem; can be a perf hit. | Restructure scopes, borrow, `mem::take`, split the fn. See [[rust-ownership]]. |
| Reflexive `Rc<RefCell<T>>` / `Arc<Mutex<T>>` | Runtime borrow panics; usually the ownership wasn't thought through. | Try single-owner borrowing, arena+indices, pass-in/return-out first. |
| Lock/`RefCell` guard held across `.await` | Deadlocks or blocks the async runtime. | Shorten the critical section; `tokio::sync::Mutex`; drop the guard before awaiting. |
| `&Vec<T>` / `&String` / `&Box<T>` params | Forces the container; refuses slice/`&str` callers. | `&[T]` / `&str` / `&T` (clippy `ptr_arg`). |
| `'static` bolted on to silence a lifetime error | Forces owned/leaked data without understanding why. | Understand the borrow; own at the boundary if needed. |
| Returning `&` to a local | "does not live long enough". | Return owned (`String`/`Vec`). |

## Structure / "spaghetti"

| Smell | Why it's wrong | Fix |
|---|---|---|
| One function doing five things (parse+validate+fetch+transform+persist) | Untestable, unreadable, SRP violation. | Extract each responsibility into its own function/type. |
| File past ~400–500 lines with mixed concerns | Second responsibility crept in. | Split the module. |
| Deeply nested `match`/`if let` pyramids | Hides the happy path. | `?`, `let ... else`, combinators (`map`/`and_then`/`ok_or`). |
| Stringly-typed data (`&str` for a fixed set) | Illegal states representable; typos compile. | Enum. Make illegal states unrepresentable. |
| `bool` parameters (`resize(true)`) | Call site is unreadable — true what? | Two-variant enum. |
| `pub` fields exposing invariants | Callers can build invalid values; permanent API commitment. | Private fields + validating constructor/builder. |
| Copy-pasted block modified slightly | DRY violation; fixes must be made N times. | Extract shared fn / trait default. |

## Async / backend

| Smell | Why it's wrong | Fix |
|---|---|---|
| Blocking call (`std::fs`, `std::thread::sleep`, heavy CPU) in an async fn | Stalls the whole runtime thread. | `tokio::fs`, `tokio::time::sleep`, `spawn_blocking` for CPU. |
| `.await` in a loop that could be concurrent | Serial latency where parallel was free. | `futures::join!` / `JoinSet` / `buffer_unordered`. |
| Spawned task whose `Result`/panic is ignored | Silent failure; lost work. | Await the `JoinHandle`, handle `JoinError`. |
| SQL built with `format!` | SQL injection. | `sqlx` bind params / `query!` macro. |
| Unbounded channel / unbounded request body | Memory-exhaustion DoS. | Bounded channels; body size limits. |

## Tooling / hygiene

| Smell | Why it's wrong | Fix |
|---|---|---|
| `#[allow(...)]` with no reason | Silences a real signal wholesale. | Fix the lint, or `// reason:` + a narrow, justified allow. |
| `#[allow(dead_code)]` on unused code | Tombstones instead of deleting. | Delete it; git remembers. |
| `unsafe` with no `// SAFETY:` | The soundness invariant is undocumented/unchecked. | Add the safety comment, or remove the `unsafe`. |
| Integer `as` cast that can truncate (`u64 as u32`) | Silent data loss. | `try_into()` + handle the error, or a `checked_*` path. |
| Hand-rolled crypto / retry / connection pool | Reinvents a battle-tested crate; likely buggy/insecure. | Use `ring`/`RustCrypto`, `backoff`, the pool the driver ships. |
| `format!`/`.to_string()`/`.clone()` in a hot loop | Needless allocations. | Borrow; reuse a buffer; measure with `criterion`. |