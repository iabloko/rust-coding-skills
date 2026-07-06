---
name: rust-architecture
description: Structure Rust code idiomatically — module/crate/workspace layout, layering with dependency arrows pointing inward, traits for dependency inversion (repository pattern), static vs dynamic dispatch, newtypes and enums to make illegal states unrepresentable, and constructor-injection "DI" without a framework. Use whenever organizing a crate, adding a module/trait boundary, or wiring services. Pair with designing-architecture for the up-front design process.
---

# Rust Architecture & Structure

`designing-architecture` is the *process* (requirements → crate scan → plan). This skill is the *idioms*: how correct Rust code is actually organized. Pair with [[rust-conventions]], [[rust-ownership]], and [[rust-error-handling]].

## Module & crate layout

- **Modules** partition one crate. A `mod foo` is `foo.rs`, with submodules in a sibling `foo/` directory (prefer this 2018+ form over `foo/mod.rs` stuffed with logic — a `mod.rs` should mostly `pub use` re-exports).
- **`lib.rs` holds the logic; `main.rs` is a thin shell.** The binary parses args/config, builds the app, and calls into the library. Everything worth testing lives under `lib.rs` so integration tests and other consumers can reach it. A project with all its logic in `main.rs` is untestable — flag it.
- **Workspace** (`[workspace]` in the root `Cargo.toml`) splits a system into member crates. Use it when you have genuinely separable layers/domains that benefit from independent compilation and enforced boundaries — not for a small app (premature — YAGNI).

## Layering: dependencies point inward

Organize by **layer** (or domain), and make dependencies flow one direction — toward the domain, never outward:

```
   ┌─────────────┐     ┌──────────────┐
   │  api / web  │────▶│              │
   │  (axum)     │     │   domain     │◀────┐
   └─────────────┘     │  (pure Rust, │     │
   ┌─────────────┐     │   no I/O)    │     │
   │   infra     │────▶│              │     │
   │ (db, http)  │     └──────────────┘     │
   └─────────────┘            ▲             │
          │                   └─────────────┘
          └──── implements domain traits ───┘
```

- **Domain** — the core types and business rules. Pure Rust: no `axum`, no `sqlx`, no `tokio` types leaking in. It defines *traits* (ports) for what it needs from the outside (`trait UserRepo`, `trait Clock`).
- **Infra** — concrete implementations of those traits (`PgUserRepo: UserRepo`). Depends on the domain, not vice versa.
- **Api / app** — wires it together: builds the concrete infra, injects it into domain services, exposes handlers.
- The rule: **a domain module must never `use` an infra or web module.** The arrow points in. In a workspace, this is enforced by which crate depends on which; in a single crate, it's a discipline `reviewing-changes` checks.

## Traits for dependency inversion (the repository pattern)

This is how Rust does "DI" — no framework, just traits + generics/`dyn`:

```rust
// domain: the port
pub trait UserRepo {
    async fn find(&self, id: UserId) -> Result<Option<User>, RepoError>;
    async fn save(&self, user: &User) -> Result<(), RepoError>;
}

// domain: a service depends on the trait, not a concrete DB
pub struct UserService<R: UserRepo> {
    repo: R,
}
impl<R: UserRepo> UserService<R> {
    pub fn new(repo: R) -> Self { Self { repo } }
    pub async fn register(&self, cmd: Register) -> Result<UserId, ServiceError> { ... }
}

// infra: the adapter
pub struct PgUserRepo { pool: PgPool }
impl UserRepo for PgUserRepo { ... }

// tests: a fake — no DB needed (see [[rust-testing]])
pub struct InMemoryUserRepo { users: Mutex<HashMap<UserId, User>> }
impl UserRepo for InMemoryUserRepo { ... }
```

- The service is testable against `InMemoryUserRepo` with no database. This is the payoff of inversion — see [[rust-testing]].
- "DI" is just **constructor injection**: pass dependencies into `new`. No container, no globals. Assemble the graph once in `main`/app setup.

## Static vs dynamic dispatch

Two ways to depend on a trait — pick deliberately:

- **Generics (`<R: UserRepo>`) — static dispatch.** Monomorphized, zero runtime cost, fully inlinable. Default choice. Cost: code bloat and longer compile times if over-used; the type parameter propagates through signatures.
- **Trait objects (`Box<dyn UserRepo>`, `&dyn UserRepo`, `Arc<dyn UserRepo>`) — dynamic dispatch.** One vtable indirection. Use when you need **heterogeneity** (a `Vec<Box<dyn Handler>>` of different types), want to **cut compile time / binary size**, or need to store the dependency without infecting every signature with a generic.
- Rule of thumb: **generics at the leaves, `dyn` at the seams.** A plugin registry, a middleware stack, a config-selected backend → `dyn`. A hot inner function → generic. Don't make everything `dyn` "for flexibility" (YAGNI), and don't make everything generic until compile times hurt.
- `async fn` in traits: native as of recent Rust for static dispatch; for `dyn` compatibility you may still need `#[async_trait]` or returning `Pin<Box<dyn Future>>` — check the toolchain ([[rust-conventions]] "Detect first").

## Make illegal states unrepresentable

The strongest Rust architectural lever — push invariants into types so bad states won't compile:

- **Enums for closed sets and state machines.** A `ConnectionState` enum with `Disconnected`/`Connecting`/`Connected(Session)` beats a struct of `is_connected: bool` + `Option<Session>` where the two can disagree. Data that only exists in one state lives *inside* that variant.
- **Newtypes for domain values.** `UserId(u64)`, `Email(String)`, `NonEmptyName(String)` — a validated constructor (`Email::parse(s) -> Result<Email, _>`) means once you hold an `Email`, it's valid everywhere. "Parse, don't validate": validate at the boundary, then carry the proof in the type.
- **Typed newtypes prevent argument swaps.** `fn transfer(from: AccountId, to: AccountId)` can be called with the wrong order; `fn transfer(from: SourceAccount, to: DestAccount)` can't.
- The **builder pattern** for structs with many optional fields / validation, instead of a `new` with ten arguments or public mutable fields.

## Error architecture

- One error enum per layer/crate ([[rust-error-handling]]): `RepoError` in infra, `ServiceError` in domain (with `#[from] RepoError`), mapped to HTTP status at the api boundary. Errors flow up and get wrapped/translated at each layer; `?` + `#[from]` makes this cheap.
- The domain error must not leak infra types (don't put `sqlx::Error` in a public domain error) — map it at the boundary.

## Configuration & composition

- A single `Config` struct deserialized with `serde` (from env/TOML), validated once at startup, then passed (by `&` or inside an `Arc`) to what needs it. No scattered `env::var` calls deep in the code.
- Assemble the whole dependency graph in one place (`fn build_app(cfg: Config) -> App`) — the "composition root". Everything below receives its dependencies; nothing reaches for a global.
- **No global mutable singletons.** A `static mut`, a `lazy_static!` mutable registry, or an `OnceCell` used as a service locator is the anti-pattern DI exists to avoid. `OnceCell`/`LazyLock` for genuinely immutable process-wide config is fine.

## Feature flags

- Use Cargo `[features]` for optional functionality (a `postgres` backend, a `metrics` layer) — keep them **additive** (enabling a feature never breaks another) and avoid mutually-exclusive features (they break `cargo build --all-features` and unioned dependency resolution).

## Anti-patterns (flag on sight)

- All logic in `main.rs` (untestable); no `lib.rs` seam.
- A domain module importing an infra/web module — dependency arrow pointing outward.
- A global singleton / service locator (`static mut`, mutable `lazy_static`) instead of constructor injection.
- `dyn` everywhere "for flexibility" (needless indirection) or generics everywhere until compile times explode.
- Infra types (`sqlx::Error`, `reqwest::Error`) leaking into domain signatures.
- A trait with exactly one impl and no test fake and no second impl on the horizon — YAGNI abstraction; use the concrete type.
- Boolean-flag structs where the flags can contradict, instead of an enum (`is_connected` + `Option<Session>`).
- A `mod.rs` full of logic instead of re-exports; a single module past ~500 lines mixing concerns.
- Premature workspace split for a small app.

## Verification checklist

- [ ] Business logic is under `lib.rs`, reachable by tests; `main.rs` is a thin shell.
- [ ] Dependency arrows point inward — no domain module `use`s infra/web.
- [ ] External dependencies (DB, HTTP, clock) sit behind a domain-defined trait, injected via constructor.
- [ ] Static vs dynamic dispatch chosen deliberately, not by habit.
- [ ] Invariants pushed into enums/newtypes; illegal states don't compile.
- [ ] No global mutable singleton / service locator; one composition root assembles the graph.
- [ ] Each layer has its own error type; infra errors don't leak into the domain API.

## Cross-references

- `designing-architecture` — the up-front process (requirements, crate scan, plan) that precedes applying these idioms.
- [[rust-conventions]] — module layout, visibility, "make illegal states unrepresentable" summarized there.
- [[rust-ownership]] — who owns what; `Arc` for shared injected dependencies; generics vs `dyn` ownership implications.
- [[rust-error-handling]] — per-layer error enums and boundary mapping.
- [[rust-testing]] — trait seams enable real-object/fake testing without mocks.
- [[rust-async]] — async traits, `Arc<dyn>` shared state, actor composition.