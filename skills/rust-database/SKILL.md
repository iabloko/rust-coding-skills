---
name: rust-database
description: "Work with SQL databases in Rust via sqlx — connection pooling, compile-time-checked query!/query_as macros, bind parameters (never string-built SQL), transactions, migrations, mapping rows to types, and avoiding N+1. Use whenever adding a query, a migration, a repository impl, or wiring a DB pool. Opinionated default: sqlx + PostgreSQL."
---

# Rust Database (sqlx)

The house data-access layer is **sqlx** — async, compile-time-checked SQL against PostgreSQL (the default). This skill is the idioms. Pair with [[rust-architecture]] (repository pattern), [[rust-error-handling]], [[rust-async]], and [[rust-security]] (injection).

## Detect first

- `Cargo.toml` → confirm `sqlx` and its features (`runtime-tokio`, `postgres`/`mysql`/`sqlite`, `macros`, `migrate`, `uuid`/`chrono`/`time`). If the project uses `diesel`/`sea-orm` instead, follow that ORM — don't rewrite to sqlx.
- `migrations/` directory and `.sqlx/` (offline query metadata) — see below.
- `DATABASE_URL` — sqlx's compile-time checking needs a reachable DB *or* offline metadata.

## Connection pool — one, shared, injected

- Create **one** `PgPool` at startup (`PgPoolOptions::new().max_connections(n).connect(&url).await?`), store it in `AppState` / inject it into repositories ([[rust-architecture]], [[rust-web]]).
- The pool is cheap to `.clone()` (it's `Arc` inside) — clone it, never rebuild it, never open a raw connection per request.
- Size the pool deliberately (`max_connections`) against the DB's connection limit; set `acquire_timeout` so a starved pool fails fast instead of hanging ([[rust-security]] resource exhaustion). Don't leave it unbounded/default in production without thought.

## Queries: bind parameters, never string-built SQL

**Never** interpolate values into SQL with `format!`/concatenation — that's SQL injection ([[rust-security]], Critical). Always bind:

```rust
// compile-time checked against the live schema — column names/types verified at build time
let user = sqlx::query_as!(
    User,
    "SELECT id, email, created_at FROM users WHERE id = $1",
    id,                    // bound parameter, not interpolated
)
.fetch_optional(&pool)     // Option<User> — None instead of an error on no row
.await?;
```

- **Prefer the `query!` / `query_as!` macros** — they check the SQL against the real schema at compile time (columns exist, types match). A typo or a schema drift becomes a build error, not a runtime surprise. This is sqlx's headline feature; use it.
- Use the non-macro `query`/`query_as` (runtime-checked) only when the query is genuinely dynamic and can't be a string literal.
- Fetch variants, pick by cardinality: `fetch_optional` (0-or-1 → `Option`), `fetch_one` (exactly 1, errors otherwise), `fetch_all` (Vec), `fetch` (a stream for large result sets — don't `fetch_all` a million rows into memory).
- **Table/column names can't be bound.** If they must be dynamic, allowlist them explicitly — never interpolate raw identifiers from input.

## Mapping rows to types

- `query_as!(T, ...)` maps columns to a struct by field name — derive `sqlx::FromRow` or let the macro handle it. Keep DB row structs at the infra boundary; map them to domain types rather than leaking DB-shaped structs through the app ([[rust-architecture]]).
- Nullable columns map to `Option<T>` — a mismatch (non-`Option` field for a nullable column) is a compile error with the macros, which is the point.

## Transactions

For multi-statement atomic work, use a transaction — don't run related writes on separate pool connections:

```rust
let mut tx = pool.begin().await?;
sqlx::query!("UPDATE accounts SET balance = balance - $1 WHERE id = $2", amt, from)
    .execute(&mut *tx).await?;
sqlx::query!("UPDATE accounts SET balance = balance + $1 WHERE id = $2", amt, to)
    .execute(&mut *tx).await?;
tx.commit().await?;        // drop-without-commit rolls back automatically
```

- Pass `&mut *tx` as the executor to run inside the transaction.
- A `Transaction` **rolls back on drop** if not committed — so an early `?` return is safe (no partial commit). This is a correctness feature; rely on it.
- Keep transactions **short** — a long-held transaction holds locks and a pool connection. Never hold one across a slow external call ([[rust-async]]).
- Overflow-sensitive updates (balances, counters) — enforce constraints in the DB (`CHECK balance >= 0`), don't trust application arithmetic alone ([[rust-security]] integer overflow).

## Migrations

- Schema changes are versioned migration files in `migrations/` (`sqlx migrate add <name>` → timestamped `.sql`). Commit them; they're the schema's source of truth.
- Apply with `sqlx migrate run` (CLI) or `sqlx::migrate!().run(&pool).await?` embedded at startup.
- **Migrations are forward-only and immutable once shipped** — never edit a migration that has run in any shared environment; add a new one. Design for zero-downtime (expand → backfill → contract) when the table is live.
- Keep migrations reversible where practical (a paired down migration), but treat production as forward-only.

## Compile-time checking & CI (`.sqlx` offline mode)

- The `query!` macros need either a live `DATABASE_URL` at build time or **offline metadata**. Generate it with `cargo sqlx prepare` — it writes `.sqlx/` (commit it). CI then builds without a database.
- Regenerate `.sqlx` whenever you change a checked query or the schema; a stale `.sqlx` is a build failure or, worse, a check against an old schema. `cargo sqlx prepare --check` in CI catches drift.

## Avoid N+1

- Fetching a list then querying per-item in a loop is the N+1 anti-pattern — one query per row kills latency ([[rust-performance]]). Use a single `JOIN`, or a `WHERE id = ANY($1)` batch fetch, or `IN`-list, then group in memory.
- Don't `.await` a query inside a `for` over another query's results — that's N+1 by construction. See [[rust-async]] for batching.

## Anti-patterns (flag on sight)

- SQL built with `format!`/concatenation of values — injection, Critical.
- Opening a connection per request instead of sharing the pool; rebuilding the pool.
- Using runtime-checked `query()` where the macro `query!` would compile-time-check it.
- `fetch_all` on an unbounded/huge result set (memory blowup) — stream or paginate.
- Related writes not wrapped in a transaction (partial-update bugs).
- A transaction held across a slow external call or long computation.
- Editing an already-shipped migration instead of adding a new one.
- Stale/missing `.sqlx` offline data breaking CI; not committing `migrations/`.
- N+1: a query inside a loop over another query's rows.
- Leaking DB-row structs / `sqlx::Error` through the domain API instead of mapping at the boundary ([[rust-architecture]]).

## Verification checklist

- [ ] All SQL uses bound parameters (`$1`, …); no value interpolation.
- [ ] Queries use the compile-time-checked `query!`/`query_as!` macros where possible.
- [ ] One shared pool, injected; sized with `max_connections` + `acquire_timeout`.
- [ ] Multi-statement atomic work is in a transaction; transactions are short, not held across external calls.
- [ ] Schema changes are new migration files (not edits to shipped ones); `migrations/` committed.
- [ ] `.sqlx` offline metadata regenerated and committed; `cargo sqlx prepare --check` in CI.
- [ ] No N+1 (no query inside a loop over rows); large result sets streamed/paginated.
- [ ] DB rows/errors mapped to domain types at the infra boundary, not leaked upward.

## Cross-references

- [[rust-architecture]] — the repository pattern: a `UserRepo` trait, a `PgUserRepo` sqlx impl, an in-memory fake for tests.
- [[rust-error-handling]] — map `sqlx::Error` to a domain error enum at the boundary; don't leak it.
- [[rust-async]] — short transactions, no query-in-a-loop, don't block the runtime.
- [[rust-security]] — bind params (injection), `acquire_timeout` (DoS), DB-level constraints.
- [[rust-web]] — the pool lives in `AppState`; services own the transactions.
- [[rust-testing]] — an in-memory fake repo for fast tests; a real DB only for a few integration tests.