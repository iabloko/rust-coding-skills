---
name: rust-performance
description: Make Rust fast the disciplined way — measure first with criterion/flamegraph, cut needless allocations and clones, borrow over own, choose generics vs dyn deliberately, set the release profile (lto/codegen-units/opt-level), and bound async concurrency. Use whenever a change is in a hot path, or throughput/latency/memory is a stated goal. Measure before and after; no unmeasured claims.
---

# Rust Performance

Rust is fast by default — most code needs *no* optimization, and premature optimization costs readability for nothing. This skill is for when performance is a **measured, stated goal**. The rule above all: **measure first, measure after, keep the numbers.** Pair with [[rust-ownership]] and [[engineering-philosophy]] ("No Number Without Measurement").

## Measure first — always

Never optimize on a hunch. Profile to find the actual hot spot; the bottleneck is rarely where you'd guess.

- **`criterion`** — statistical microbenchmarks in `benches/`. Bench the function before and after a change; commit the delta. `cargo bench`. It handles warmup, outliers, and regression detection.
- **`cargo flamegraph`** (Linux `perf` / DTrace) — where wall-clock time actually goes across a whole run. Start here for "the service is slow".
- **`cargo llvm-cov` / instrumentation** — for finding hot lines.
- **Allocation profiling** — `dhat` (heap profiler) or `valgrind --tool=massif` to find allocation hot spots.
- **Bench a release build** (`--release`) — debug builds are 10–100× slower and meaningless for perf. And bench a *representative workload*, not a toy input.

An unmeasured "this is faster" is a `reviewing-changes` finding. So is a doc/comment quoting a latency/throughput number with no benchmark behind it.

## Allocations are the usual culprit

Heap allocations (and the `clone`s that cause them) dominate most Rust hot paths. Cut the needless ones:

- **Borrow instead of own/clone.** `&str` over `String`, `&[T]` over `Vec<T>` in signatures ([[rust-ownership]]). A `.clone()` or `.to_string()` in a hot loop is the first thing to remove — but confirm with a profile, not a guess.
- **`format!` / string building in hot loops** allocates every iteration. Reuse a `String` with `write!`, or build once outside the loop. Prefer `push_str`/`write!` over `a + &b` chains.
- **Reserve capacity** when the size is known: `Vec::with_capacity(n)` / `String::with_capacity(n)` avoids repeated grow-and-copy reallocations.
- **Avoid intermediate collections.** Chain iterator adapters and `collect` once at the end, rather than `collect`ing between each step. Iterators are lazy and usually allocation-free until the final `collect`.
- **`collect` into the right type.** `collect::<Result<Vec<_>, _>>()` short-circuits; collecting into a `HashSet`/`HashMap` when you need lookups beats a `Vec` + linear scan.
- **Small-size optimizations** where measured: `SmallVec`/`arrayvec` (stack storage for small collections), `Box<str>` over `String` for immutable strings, `Cow<str>` when you *sometimes* need owned. Don't add these speculatively — only where a profile shows the allocation matters.
- **`Arc::clone` is cheap** (an atomic increment), a deep clone is not. Sharing via `Arc` to avoid a deep clone is a legitimate optimization; cloning the inner data is what hurts.

## Dispatch, generics, and inlining

- **Static dispatch (generics)** monomorphizes and inlines — zero-cost at runtime. **Dynamic dispatch (`dyn`)** costs a vtable indirection and blocks inlining. In a hot inner loop, prefer generics; at cold seams, `dyn` is fine (see [[rust-architecture]]).
- **`#[inline]`** only where a profile/bench shows it helps (small hot functions crossing a crate boundary — the compiler inlines within a crate freely). Sprinkling `#[inline(always)]` everywhere can *hurt* (i-cache pressure, code bloat). Measure.
- **Bounds checks** — the compiler elides most; iterator-based code avoids them entirely. Don't reach for `unsafe { get_unchecked }` to skip bounds checks unless a profile proves it's the bottleneck *and* you can prove the index is in range (`// SAFETY:`). Idiomatic iterators usually match hand-unsafe speed.

## The release profile

Debug is unoptimized; `--release` turns on `opt-level = 3`. For a shipping binary, tune `[profile.release]` in `Cargo.toml` — but **benchmark each change**, they trade compile time (and sometimes each other) for runtime:

```toml
[profile.release]
lto = "thin"          # link-time optimization across crates ("fat" = more, slower build)
codegen-units = 1     # less parallelism, better optimization (slower build)
panic = "abort"       # smaller/faster if you don't need unwinding (changes semantics!)
strip = true          # drop symbols → smaller binary
```

- `lto` and `codegen-units = 1` are the big runtime wins; they cost build time. Worth it for release/CI artifacts, painful for iteration.
- `panic = "abort"` removes unwinding tables — but then `catch_unwind` and unwind-based tests don't work; only if the app genuinely aborts on panic.
- A `[profile.bench]`/`[profile.release]` mismatch makes benches lie — bench with the profile you ship.

## Async performance

- **Bound concurrency.** Unbounded spawning / unbounded channels look fast until they OOM under load. `buffer_unordered(n)`, a `Semaphore`, or a bounded `mpsc` caps in-flight work — see [[rust-async]].
- **Don't block the runtime** — a blocking call in an async task stalls a whole worker thread; that's a throughput cliff, not a micro-cost ([[rust-async]]).
- **Batch I/O.** One query fetching 100 rows beats 100 queries (the N+1 problem); one buffered write beats 100 syscalls (`BufWriter`/`BufReader`).
- Lock contention: a hot `Mutex` serializes threads. Shorten critical sections, shard the lock, use `RwLock` for read-heavy, or switch to message-passing.

## Data structure & algorithm sanity

- Right container: `HashMap` for keyed lookup (O(1)) vs `Vec` linear scan (O(n)); `HashMap`/`HashSet` when you're doing `contains` in a loop. `BTreeMap` when you need ordering. A faster hasher (`ahash`, `fxhash`) when the default SipHash (DoS-resistant, slower) isn't needed for untrusted keys.
- Fix the **algorithmic** complexity before micro-optimizing constants — an O(n²) loop that should be O(n) dwarfs any allocation tuning.

## Anti-patterns (flag on sight)

- Optimizing without a profile/benchmark; "this should be faster" with no measurement.
- A perf claim in a comment/doc/PR with no `criterion` number behind it ([[engineering-philosophy]] "No Number Without Measurement").
- `unsafe` / `get_unchecked` to skip bounds checks with no profile proving it matters (and no `// SAFETY:`).
- `#[inline(always)]` sprayed across the codebase.
- Micro-optimizing a cold path (startup, config parsing, error path) — wasted effort and readability.
- Benchmarking a debug build, or a toy input unrepresentative of production.
- Chasing allocation nano-optimizations while an O(n²) algorithm or an N+1 query sits unfixed.
- `clone`/`format!`/`collect` in a hot loop left because "it's easier" — but only after a profile confirms it's hot.
- Tuning `[profile.release]` flags without benchmarking the effect (they trade build time and can regress).

## Verification checklist

- [ ] The hot path was identified by a profile/benchmark, not a guess.
- [ ] A `criterion` bench (or equivalent) exists showing before/after; the number is committed.
- [ ] The benchmark used a `--release` build and a representative workload.
- [ ] Removed clones/allocations are in a path a profile flagged as hot, not cold code.
- [ ] No `unsafe` added for perf without a profile justifying it and a `// SAFETY:` comment.
- [ ] Async hot paths bound their concurrency and don't block the runtime.
- [ ] Algorithmic complexity checked before constant-factor tuning.
- [ ] Any `[profile.release]` change was benchmarked, not assumed.

## Cross-references

- [[rust-ownership]] — borrow-vs-clone is the first allocation lever; `Arc` clone (cheap) vs deep clone (not).
- [[rust-async]] — bounded concurrency, not blocking the runtime, batching I/O.
- [[rust-architecture]] — generics vs `dyn` dispatch cost at seams vs leaves.
- `engineering-philosophy` — "No Number Without Measurement"; KISS/YAGNI over premature optimization.
- `reviewing-changes` — unmeasured perf claims and premature `unsafe` are findings.
- [[rust-testing]] — `criterion` benches live alongside tests; regressions caught in CI.