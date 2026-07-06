# rust-coding-skills

Rust-focused skills for [Claude Code](https://claude.com/claude-code): idiomatic conventions, error handling, ownership discipline, and the surrounding engineering rigor — a strict five-pass code review, red-green TDD, feature-branch commits, and pre-implementation architecture. Built for a backend/Rust newcomer who wants blunt, thorough review that does **not** let sloppy or spaghetti code through. Distributed as the `rust-skills` plugin via this repo's own marketplace.

## Install

```
/plugin marketplace add iabloko/rust-coding-skills
/plugin install rust-skills@iabloko-rust
```

## What's inside

### Rust skills (the core)

| Skill | Covers |
| --- | --- |
| `rust-conventions` | The rulebook: naming, module/crate layout, `rustfmt` + `clippy -D warnings` gates, `Result`-first flow, visibility, forbidden patterns, and the beginner-smell catalog |
| `rust-error-handling` | `Result`/`?`, `thiserror` enums for libs, `anyhow` + `.context()` for bins, when `unwrap`/`panic!` is actually correct (rarely) |
| `rust-ownership` | Borrow-checker mental model, borrow-vs-own, when `clone`/`Rc`/`Arc`/`RefCell`/`Mutex` is the right tool vs a crutch, lifetimes |
| `rust-testing` | Unit/integration/doc test layout, `#[tokio::test]`, `proptest`, table cases, real objects over mocks, coverage |
| `rust-async` | tokio, never blocking the runtime, `Send`/`'static` spawning bounds, `JoinSet`, cancellation/`select!`, channels, shared state, axum handlers |
| `rust-architecture` | Module/crate/workspace layout, inward-pointing layers, traits for DI (repository pattern), static vs dynamic dispatch, illegal-states-unrepresentable |
| `rust-performance` | Measure-first (`criterion`/flamegraph), cut needless allocations/clones, generics vs `dyn`, release profile tuning, bounded async concurrency |
| `rust-security` | Security review: `unsafe` soundness, integer overflow/truncation, panic-as-DoS, injection (SQL/command/path), secrets, crypto, `cargo audit`/`deny`, authz, resource exhaustion |

Opinionated backend defaults across the pack: **tokio** (async), **axum** (web), **thiserror**/**anyhow** (errors), **serde** (serialization), **sqlx** (DB). Override per project via `Cargo.toml`.

### Engineering skills

| Skill | Covers |
| --- | --- |
| `reviewing-changes` | Strict five-pass review (code, security, architecture, acceptance, AI-native) — the "harsh review" gate, with a Rust beginner anti-pattern checklist |
| `running-tdd-cycles` | Red-green-refactor on `cargo test`/`nextest`, `proptest` for invariants, one requirement per cycle |
| `committing-changes` | Feature branch + PR + git hooks; pre-commit runs `cargo fmt`/`clippy`/`test`; never push `main`, never merge |
| `designing-architecture` | Crate/module structure, crates.io selection, trait boundaries, error strategy — before implementing |
| `engineering-philosophy` | KISS, YAGNI, DRY, SOLID, Fail-Fast weights on every decision |
| `shell-discipline` | One command per call, no inline env vars, `gh auth login` |

### Slash commands

Thin wrappers over the skills (namespaced `/rust-skills:<cmd>`):

| Command | Does |
| --- | --- |
| `/rust-skills:tdd` | Red-green-refactor cycle on the given requirement (`running-tdd-cycles` + `rust-testing`) |
| `/rust-skills:review` | Strict five-pass quality gate — launches the five review agents in parallel |
| `/rust-skills:security-review` | Focused single-pass Rust security audit (`rust-security`) |
| `/rust-skills:commit` | Commit + PR via `committing-changes` (hooks, cargo gate, `gh pr create`) |
| `/rust-skills:design` | Pre-implementation architecture (`designing-architecture`) |

### Review agents

`/rust-skills:review` orchestrates five read-only sub-agents in parallel, one per pass, each reading the matching skill: `code-reviewer` (Pass 1), `security-auditor` (Pass 2 → `rust-security`), `architect-review` (Pass 3), `acceptance-auditor` (Pass 4), `ai-native-reviewer` (Pass 5). If parallel agents aren't available, the `reviewing-changes` skill runs the same five passes inline.

### Recommended pairing: `rust-analyzer-lsp`

The official `rust-analyzer-lsp` plugin (in the `claude-plugins-official` marketplace) gives the agent live diagnostics, go-to-definition, and type info from the running analyzer — a much tighter loop than `cargo check` alone. Install it alongside this pack.

### CLAUDE.md template

[`CLAUDE.md`](CLAUDE.md) is a behavioral-guidelines template to merge into your Rust project's own instructions, plus the active-skills routing table.

## Status

Iterations 1–3 complete: eight Rust skills (`rust-conventions`, `rust-error-handling`, `rust-ownership`, `rust-testing`, `rust-async`, `rust-architecture`, `rust-performance`, `rust-security`), the full engineering set, five slash commands, and five parallel review agents.

## License

[MIT](LICENSE)