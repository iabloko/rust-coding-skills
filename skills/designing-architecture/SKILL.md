---
name: designing-architecture
description: "Design pre-implementation Rust architecture: crate/module structure, crate selection from crates.io, trait boundaries, data flow, error strategy, data schema. Opinionated backend defaults (tokio/axum/thiserror)."
allowed-tools: Read, Grep, Glob, WebSearch, WebFetch, Bash(gh search repos *), Bash(gh repo view *), Bash(gh search code *), Bash(cargo search *), Bash(cargo info *), Bash(cargo tree *)
---

## Methodology

### Phase 1 — Requirements

1. Parse the feature into functional and non-functional requirements (latency, throughput, availability, consistency, failure modes).
2. Identify constraints: edition, MSRV, existing crates in `Cargo.toml`, `sync` vs `async`, deployment target.
3. Read the project's architecture map (often `docs/architecture.md`). Identify integration points with existing modules/crates.

### Phase 2 — Crate landscape scan

4. **Discover candidates.** Search crates.io (`cargo search`, https://crates.io, https://lib.rs), `awesome-rust`, `blessed.rs` (curated recommendations), and GitHub by topic. Check what the project already depends on first (`cargo tree`) — don't add a second crate for a role one already fills.
5. **Evaluate each candidate** with consistent dimensions:
   - Downloads/recent trend, GitHub stars, **last release date and commit cadence** (a crate untouched for 2+ years is a risk).
   - Maintenance signal: open/closed issue ratio, is there a `1.0`?, RUSTSEC advisories (`cargo audit`).
   - `#![no_std]` support if relevant; feature-flag surface; MSRV.
   - **Dependency footprint** — `cargo tree` transitive count and compile-time cost; a heavy dep for a small job is a real cost in Rust.
   - License (MIT/Apache-2.0/BSD safe; GPL/AGPL needs a deliberate decision — most of the ecosystem is MIT/Apache dual).
6. **Cross-check the docs.** Read docs.rs for the crate — verify it supports the exact use case; a download count doesn't.
7. **Compare alternatives** in a table with explicit trade-offs.

### Phase 3 — Pattern & boundary selection

8. Identify the shape:
   - **Traits as interfaces** — define behavior contracts; small, focused traits (ISP). Use them for dependency inversion (the repository pattern: a `UserRepo` trait, a `PgUserRepo` impl) so the domain doesn't depend on the driver.
   - **Static vs dynamic dispatch** — generics (`fn f<R: UserRepo>`) for zero-cost monomorphization; `Box<dyn Trait>`/`&dyn Trait` when you need heterogeneity or to cut compile time/binary size. Default to generics; reach for `dyn` when it earns its keep.
   - **Enums for closed sets / state machines** — model finite states as an enum; make illegal states unrepresentable ([[rust-conventions]]).
   - **Newtypes** for domain identifiers and validated values (`UserId(u64)`, `Email(String)`).
   - **Architectural** — hexagonal / ports-and-adapters maps cleanly onto Rust traits; layered crates in a workspace; the actor model (`tokio` tasks + channels) for concurrent state.
9. Select the **minimum** patterns the problem needs. No trait tourism, no generics for a single concrete type.
10. Map selections to the project's conventions; don't introduce a new pattern where an existing one fits.

### Phase 4 — Design

11. **Crate/module structure.** Single crate with modules, or a `[workspace]` with member crates by layer/domain (`domain`, `api`, `infra`)? Draw the dependency arrows — they must point inward (infra → domain, never the reverse).
12. **Data flow:** inputs → processing → outputs, including failure paths.
13. **Error strategy** ([[rust-error-handling]]) — the `thiserror` enum(s) for library layers, `anyhow` at the binary boundary, where errors are mapped/wrapped, what maps to which HTTP status (for a web service).
14. **Concurrency model** — sync or `async` (tokio)? Shared state via `Arc<...>` (which lock?), or message-passing via channels? Decide ownership up front ([[rust-ownership]]) — don't discover `Arc<Mutex<T>>` mid-implementation.
15. **Config, secrets, DI** — config via `serde` + a `Config` struct; secrets via env/`secrecy`; "DI" in Rust is usually constructor injection of trait objects/generics, not a framework.
16. Produce an ASCII diagram showing crates/modules, dependencies, and data direction.

### Phase 5 — Implementation plan

17. Decompose into TDD-ready steps, each sized for one red-green-refactor cycle, independently testable, delivering incremental value.
18. Order by dependency (what must exist before what).
19. Hand off to `running-tdd-cycles` for execution. Do not implement here.

## Database overlay (backend services)

When the design includes a data layer:

1. **Pick the technology family** via CAP framing (which two of consistency/availability/partition-tolerance does the workload force?): relational (PostgreSQL — the backend default), document, key-value (Redis for cache/session), time-series, graph, search.
2. **Pick the Rust access layer.** `sqlx` (compile-time-checked raw SQL, async — the opinionated default), `sea-orm`/`diesel` (ORM) if the project wants one. Prefer compile-checked queries over string-built SQL (injection safety).
3. **Schema design.** Conceptual (ER) → logical (3NF or deliberate denormalization) → physical (types, indexes). State trade-offs.
4. **Migrations.** `sqlx migrate` / `refinery` / the ORM's tool. Expand → backfill → contract for zero-downtime.
5. **Security.** Bound params only (never `format!` into SQL), least-privilege DB roles, at-rest + in-transit encryption, audit logging for sensitive ops.

## Output

A single self-contained Markdown document that feeds directly into `running-tdd-cycles`:

```markdown
---
purpose: Architecture design for <feature>
---

# Architecture — <feature>

## 1. Requirements
Functional + non-functional (SLA targets if relevant), constraints (edition, MSRV, sync/async).

## 2. Crate selection

### Selected
| Crate | Purpose | Downloads | Last release | Why |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

### Rejected
| Crate | Reason |
|---|---|
| ... | ... |

### Sources
- [1] crates.io / lib.rs / blessed.rs entry
- [2] docs.rs page
- [3] GitHub repo (activity, issues)

## 3. Patterns & boundaries
Traits chosen, static vs dynamic dispatch, enums/newtypes, and the concrete reason each fits.

## 4. Architecture
ASCII diagram (crates/modules + dependency direction) + per-component description.

## 5. Error strategy
Error enums per layer, anyhow boundary, error→status mapping.

## 6. Data layer (if applicable)
Technology, access crate, schema, indexes, migration plan.

## 7. TDD-ready implementation plan
1. **Step 1: <title>** — <what to implement>; depends on: none; test: <what the failing test pins down>.
2. **Step 2: <title>** — ...

## 8. Open questions
Decisions that need user input before implementation begins.
```

## Behavioural traits

- **Research before recommending.** Never propose a crate without checking last-release date, docs.rs, RUSTSEC, and at least one alternative.
- **Minimum viable architecture.** Design only what the feature needs. No speculative generics, traits, or workspace splits.
- **Ecosystem first.** Prefer a mature crate to custom code. Check crates.io/lib.rs/blessed.rs and docs.rs before writing anything bespoke.
- **Explicit trade-offs.** State what's gained and lost between alternatives (compile time, binary size, flexibility).
- **Ownership up front.** Decide who owns what and where the `async`/lock boundaries are during design, not during implementation.
- **No pattern tourism.** Apply a trait/generic/`dyn` only when it solves a concrete problem in this feature.
- **Recency matters.** Prefer crates with releases in the last ~12 months.

## Cross-references

- `running-tdd-cycles` — receives the implementation plan from this skill.
- `reviewing-changes` — verifies the implementation against this design.
- [[rust-conventions]] / [[rust-error-handling]] / [[rust-ownership]] — the idioms and decisions this design feeds on.
- `engineering-philosophy` — KISS, YAGNI, Use Libraries, No Magic dominate during design.