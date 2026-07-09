---
name: rust-cli
description: Build Rust command-line tools the disciplined way — clap's derive API for parsing (never hand-rolled `env::args`), a thin `main` over testable library functions, `Result`/`ExitCode` for exit status, config precedence (flags > env > file > default), and output hygiene (data to stdout, logs/errors to stderr). Use whenever writing a binary that parses arguments, subcommands, or flags.
---

# Rust CLI

A CLI is just a thin shell around library code. The parsing layer (clap) belongs at the very edge; everything worth testing lives in plain functions underneath. Treat `main` like an axum handler: parse, delegate, map the result to an exit status — no business logic. Pair with [[rust-architecture]] (thin edge over a library), [[rust-error-handling]] (how `main` returns), and [[rust-testing]] (test the functions, not the parser).

## Parse with clap's derive API — never hand-roll

Don't parse `std::env::args()` by hand. `clap` (derive feature) gives you `--help`, validation, error messages, and exit codes for free.

```rust
use clap::{Parser, Subcommand};

/// What the tool does — this doc comment becomes the help text.
#[derive(Parser)]
#[command(name = "mytool", version, about)]
struct Cli {
    /// Increase logging verbosity (-v, -vv).
    #[arg(short, long, action = clap::ArgAction::Count)]
    verbose: u8,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Import a file.
    Import {
        /// Path to the input file.
        path: std::path::PathBuf,
        /// Overwrite an existing target.
        #[arg(long)]
        force: bool,
    },
}
```

- **Doc comments are the help text.** Write them; they're the UI.
- **Subcommands are an enum** — model the tool's verbs as variants, and let `match` in `main` dispatch. Illegal combinations become unrepresentable (see [[rust-architecture]]).
- **Validate at the boundary** with `value_parser` (ranges, custom `FromStr`, `PathBuf`) so the rest of the code receives already-valid types, not raw strings.
- **`#[arg(env = "MYTOOL_TOKEN")]`** wires an env-var fallback; `default_value_t` sets a default. Precedence is flag > env > default — clap handles it.

## Thin `main`, testable core

The single most important CLI rule: **`main` parses and delegates; the logic lives in functions that take plain arguments and return `Result`.** You can't unit-test argument parsing meaningfully, but you *can* test `import(path, force)`.

```rust
fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Import { path, force } => import(&path, force),
    }
}

// Testable — no clap, no process exit, just inputs and a Result.
fn import(path: &Path, force: bool) -> anyhow::Result<()> { /* ... */ }
```

## Exit status and error output

- **Return `Result` from `main`.** `fn main() -> anyhow::Result<()>` prints the error's `Debug` (the full `.context()` chain) to **stderr** and exits non-zero. Don't `unwrap`/`panic!` for expected failures — a panic prints a scary backtrace and exits 101 ([[rust-error-handling]]).
- **Need specific exit codes?** Return `std::process::ExitCode` (e.g. `ExitCode::from(2)` for "no matches", grep-style), or call `std::process::exit(code)` at the top level only.
- **`anyhow` for binaries, `thiserror` for the library** underneath — the app layer wants `.context()`, the library wants typed errors ([[rust-error-handling]]).
- Use `anyhow::Context` to add "what were we doing" at each layer, so the stderr message reads like a trace back to the failing operation.

## Output hygiene

- **Data on stdout, everything else on stderr.** A tool whose output feeds a pipe (`mytool list | grep x`) must keep progress bars, logs, and errors *off* stdout. Mixing them corrupts the pipe.
- **No `println!` for logs.** Use `tracing` for diagnostics, gated by `--verbose`, written to stderr ([[rust-observability]]). Reserve `println!`/`print!` for the tool's actual data output.
- **Respect `--quiet`/`--verbose`** and honor `NO_COLOR` / non-TTY (don't emit ANSI colors into a pipe). `clap` + `anstream`/`termcolor` detect a TTY.
- For structured output, offer `--format json` and print machine-readable data — don't make callers scrape human text.

## Config precedence

When a value can come from several places, apply a clear order: **command-line flag > environment variable > config file > built-in default.** Resolve it once, early, into a plain config struct the rest of the code reads. Don't scatter `env::var` lookups through the logic.

## Testing

- **Test the logic functions directly** — call `import(path, force)` with a `tempfile::tempdir()`, assert on the result and side effects ([[rust-testing]]). This is where coverage belongs.
- **Assert the CLI definition is valid** with a single `#[test]` calling `Cli::command().debug_assert()` — it catches conflicting args/duplicate names at test time.
- **End-to-end** only for the wiring: `assert_cmd` + `predicates` run the built binary and assert on exit code / stdout / stderr. Keep these few; they're slow and coarse.

## Anti-patterns (flag on sight)

- Hand-parsing `std::env::args()` with manual `if arg == "--flag"` chains instead of `clap`.
- Business logic inside `main` or inside the parse layer — nothing left to unit-test.
- `unwrap`/`expect`/`panic!` on bad user input (missing file, bad flag) instead of a `Result` and a clean stderr message.
- Writing logs, progress, or errors to **stdout**, corrupting downstream pipes.
- `println!` used as a logger instead of `tracing` to stderr ([[rust-observability]]).
- Emitting ANSI color unconditionally, ignoring `NO_COLOR` / non-TTY.
- Scattered `env::var` reads instead of one resolved config with a defined precedence.
- Only end-to-end `assert_cmd` tests, with the core logic never unit-tested directly.

## Verification checklist

- [ ] Arguments parsed via `clap` derive, not hand-rolled — `--help`/`--version` work.
- [ ] `main` only parses and delegates; logic is in functions returning `Result`.
- [ ] `main` returns `Result`/`ExitCode`; no `unwrap`/`panic!` on expected failures.
- [ ] Data goes to stdout; logs and errors go to stderr.
- [ ] Logs use `tracing` gated by verbosity, not `println!`.
- [ ] Config precedence (flag > env > file > default) is explicit and resolved once.
- [ ] Core logic has direct unit tests; `Cli::command().debug_assert()` guards the CLI shape.

## Cross-references

- [[rust-architecture]] — thin edge over a testable library; subcommand enum makes illegal states unrepresentable.
- [[rust-error-handling]] — `anyhow` in `main` (bin) vs `thiserror` (lib); `?` and `.context()`; exit codes.
- [[rust-testing]] — test the logic functions; `debug_assert()` and sparing `assert_cmd` e2e tests.
- [[rust-observability]] — `tracing` to stderr for logs, not `println!`; verbosity flags.
- `engineering-philosophy` — KISS: `main` stays thin; YAGNI: don't add flags nobody asked for.
- [[rust-conventions]] — `Result`-first, no `unwrap` on shipping paths applies to binaries too.