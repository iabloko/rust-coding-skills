---
name: rust-async
description: "Write correct async Rust on tokio — async/await, the Send/Sync/'static bounds spawning needs, never blocking the runtime, task spawning and JoinSet, cancellation and select!, channels (mpsc/oneshot/broadcast/watch), shared state (Arc + which lock), and axum handler shape. Use whenever writing async fns, spawning tasks, or building a tokio service. Opinionated default runtime: tokio."
---

# Async Rust (tokio)

Async is where backend Rust gets subtle: the borrow checker plus a cooperative scheduler means a single blocking call or a lock held across `.await` can stall or deadlock the whole service. This skill is the rulebook. Pair with [[rust-ownership]] (the `Send`/`'static`/lock rules) and [[rust-error-handling]].

## Mental model

- `async fn` returns a **future** — a state machine that does nothing until polled. Calling it doesn't run it; `.await`ing it (or handing it to the runtime) does.
- **tokio is the runtime** (this user's default). It polls futures on a pool of worker threads. Enter it via `#[tokio::main]` on `main`, or `#[tokio::test]` in tests.
- `.await` is a **yield point**: the task can be suspended here and the worker thread goes off to run other tasks. Everything between two `.await`s runs without yielding — so blocking there blocks the worker.

## The cardinal rule: never block the runtime

A worker thread running your task cannot run any other task while your code is doing synchronous work. Blocking calls starve the whole runtime.

- **Blocking I/O** — use the async equivalent: `tokio::fs` not `std::fs`, `tokio::net` not `std::net`, the async DB driver (`sqlx`, `tokio-postgres`) not a blocking one.
- **Sleeping** — `tokio::time::sleep(d).await`, never `std::thread::sleep`.
- **CPU-bound work** (parsing a huge blob, hashing, compression, image work) — move it off the async workers with `tokio::task::spawn_blocking(|| ...).await`, or a dedicated `rayon` pool. `spawn_blocking` is for *blocking/CPU* code, not for making sync code "async".
- **A blocking call you can't avoid** (a sync-only C library) — wrap it in `spawn_blocking`.

Blocking the runtime is the #1 async production bug; treat any `std::` blocking call inside an `async fn` as a `reviewing-changes` finding.

## Spawning tasks: the Send + 'static bill

`tokio::spawn(future)` runs a future concurrently as a task. The future must be `Send + 'static`:

- **`'static`** — the task may outlive the current scope, so it can't borrow locals. Move owned data in (`move` closure), or share via `Arc`. This is why you clone an `Arc` per task (cheap — just a refcount bump), not the data.
- **`Send`** — the task may move between worker threads, so everything held across an `.await` must be `Send`. A `Rc`, a `RefCell`, or a `MutexGuard` held across `.await` breaks this. See [[rust-ownership]].
- **The return** is a `JoinHandle<T>` — `.await` it to get `Result<T, JoinError>`. **Don't drop it silently:** an unawaited task that panics or errors fails invisibly and you lose its work. Await it, or track it in a `JoinSet`.

```rust
let shared = Arc::new(state);
let mut set = JoinSet::new();
for job in jobs {
    let shared = Arc::clone(&shared);
    set.spawn(async move { process(&shared, job).await });
}
while let Some(res) = set.join_next().await {
    let output = res??;   // JoinError, then your own error
}
```

- `JoinSet` for a dynamic group of tasks — join them as they finish, and dropping the set aborts the stragglers.
- For structured "spawn N, need all/any": `futures::future::join_all` / `try_join_all`, or `tokio::try_join!` for a fixed heterogeneous set.

## Concurrency without spawning

You don't always need `spawn`. To run futures concurrently *on the current task*:

- `tokio::join!(a, b, c)` — await all, concurrently, same task (no `Send`/`'static` bill).
- `tokio::try_join!(a, b)` — same, short-circuits on the first `Err`.
- `tokio::select!` — race several futures/branches, take whichever is ready first (timeouts, cancellation, "first of N"). Beware **cancellation**: the losing branches are dropped mid-flight — don't `select!` over a future that must not be cancelled partway (see below).
- A `.await` in a `for` loop is **serial** — if the iterations are independent, that's needless latency. Use `join_all`, a `JoinSet`, or `stream::iter(...).buffer_unordered(n)` to bound concurrency.

## Cancellation is real

Dropping a future cancels it — execution stops at the last `.await`, and everything is dropped. This is powerful and a footgun:

- Code after a cancelled `.await` **never runs** — don't rely on "cleanup after await" for correctness; use RAII guards (`Drop`) or `finally`-style scope guards instead.
- **`select!` cancels the losing branches.** If a branch was midway through a non-idempotent operation (a half-written DB transaction), that's a bug. Make such operations atomic, or use `tokio::select!` with `biased` / cancellation-safe primitives.
- Propagate shutdown with a `CancellationToken` (`tokio_util`) or a `watch` channel; long-running tasks `select!` on it to exit cleanly.
- `tokio::time::timeout(dur, fut).await` wraps a future with a deadline — returns `Err(Elapsed)` and drops `fut` on timeout.

## Channels — pick by shape

| Channel | Shape | Use |
|---|---|---|
| `mpsc` | many senders → one receiver | work queues, actor inboxes; **bounded** by default for backpressure |
| `oneshot` | one value, once | request/response, returning a result from a spawned task |
| `broadcast` | one → many, each receiver sees every message | fan-out events; slow receivers lag/drop |
| `watch` | one → many, receivers see only the latest | config reload, shutdown signal, current-state broadcast |

- **Prefer bounded `mpsc`** — an unbounded channel is an unbounded memory leak under load (backpressure disappears). `send().await` on a bounded channel applies backpressure naturally.
- Message-passing (an actor owning its state, mutated only via its `mpsc` inbox) is often **cleaner than `Arc<Mutex<T>>`** for shared mutable state — no lock contention, no held-guard-across-await hazard. Reach for it before reaching for locks.

## Shared state: Arc + the right lock

When you genuinely need shared mutable state (not message-passing):

- Read-mostly, cheap to clone → `Arc<T>` with `T` immutable, swap via `arc-swap`.
- Mutable, short critical sections → `Arc<Mutex<T>>` or `Arc<RwLock<T>>`.
- **`std::sync::Mutex` vs `tokio::sync::Mutex`:** default to `std::sync::Mutex` and **never hold its guard across an `.await`** (it's not `Send`-safe across await and can deadlock the scheduler). Only use `tokio::sync::Mutex` when the guard genuinely must live across an await point — and first ask whether you can restructure so it doesn't (compute, drop the guard, then await). See [[rust-ownership]].
- `RwLock` when reads vastly outnumber writes; otherwise `Mutex` is simpler and often faster.

## axum handler shape (the web default)

- Handlers are `async fn` returning `impl IntoResponse` (or `Result<impl IntoResponse, AppError>`).
- Share state via `State<Arc<AppState>>` extractor — clone the `Arc`, not the state.
- Map your error enum to a status with an `impl IntoResponse for AppError` (one place decides error→status; see [[rust-error-handling]]).
- Don't block in a handler (it runs on the runtime); offload CPU work with `spawn_blocking`.
- Keep handlers thin: extract → call a service function (testable, no `axum` types) → map the result. Business logic doesn't belong in the handler.

## Anti-patterns (flag on sight)

- Any `std::` blocking call (`std::fs`, `std::thread::sleep`, blocking DB/HTTP client, heavy CPU) inside an `async fn` without `spawn_blocking`.
- A `std::sync::Mutex`/`RefCell` guard held across an `.await`.
- `tokio::spawn`ing a task and dropping the `JoinHandle`, so panics/errors vanish.
- Unbounded `mpsc`/`broadcast` under load-bearing traffic — no backpressure.
- Serial `.await` in a loop where the iterations are independent.
- `select!` over a non-cancellation-safe future that must complete atomically.
- Reaching for `Arc<Mutex<T>>` before considering an actor/message-passing design.
- `block_on` inside async code (nested runtime panic), or `.await` inside a `spawn_blocking` closure.
- `async fn` that never actually awaits anything — it didn't need to be async.
- Business logic living inside the axum handler instead of a plain testable service fn.

## Verification checklist

- [ ] No blocking call (fs/sleep/CPU/sync driver) on the async path without `spawn_blocking`.
- [ ] No lock/`RefCell` guard held across `.await` (use `std::sync::Mutex` + short scope, or message-passing).
- [ ] Every spawned task's `JoinHandle`/`JoinError` is awaited or tracked (`JoinSet`); panics aren't swallowed.
- [ ] Channels are bounded (backpressure), or unboundedness is justified.
- [ ] Independent awaits run concurrently (`join!`/`JoinSet`/`buffer_unordered`), not serially in a loop.
- [ ] Cancellation-unsafe critical sections aren't inside a `select!` branch; cleanup uses `Drop`, not post-await code.
- [ ] Handlers/services separated: business logic is in plain testable functions, not in `axum` handlers.

## Cross-references

- [[rust-ownership]] — the `Send`/`Sync`/`'static` bounds, `Arc` cloning, and the lock-across-await rule.
- [[rust-error-handling]] — `Result` from tasks, `JoinError`, error→status mapping.
- [[rust-testing]] — `#[tokio::test]`, `tokio::time::pause()` for deterministic time.
- [[rust-performance]] — bounded concurrency, avoiding per-task allocation churn.
- `reviewing-changes` — blocking-the-runtime and held-guard-across-await are security/correctness findings.