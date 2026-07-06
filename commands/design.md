---
description: Design architecture for $ARGUMENTS (wraps designing-architecture skill).
allowed-tools: Read, Grep, Glob, WebSearch, WebFetch, Bash(git ls-files), Bash(git log *), Bash(cargo tree *), Bash(cargo search *), Bash(cargo info *)
---

Scope: $ARGUMENTS

Invoke the `designing-architecture` skill on the design question above. That skill is the single source of truth for the crate-research budget, the candidate-comparison rubric, and the output shape (crate/module structure, data flow, ASCII diagram, error strategy, hand-off plan).

Read-only — this command never edits code or implements. The output is a plan that hands off to `running-tdd-cycles` (or `/rust-skills:tdd`) for execution.

Compose with the Rust idiom skills the design touches:
- `rust-architecture` — layering, trait-based DI (repository pattern), static vs dynamic dispatch, illegal-states-unrepresentable.
- `rust-error-handling` — per-layer error enums (`thiserror`) and the `anyhow` boundary.
- `rust-async` — if the design is async: tokio, concurrency model, shared state vs message-passing.
- `engineering-philosophy` — KISS, YAGNI, Use Libraries, No Magic dominate during design.