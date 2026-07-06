---
name: shell-discipline
description: Shell discipline — one command per call, no inline env vars, gh auth login.
---

## Shell Commands

- **One command per call** — keep commands small, readable, and atomic. Don't chain with `&&`, `;`, or `cd dir && command`. Use separate calls — first `cd`, then the command.
- **No inline env vars** — don't use `VAR=value command`. Set env separately or use proper tooling. (Cargo reads `RUSTFLAGS`, `CARGO_*` — set them in `.cargo/config.toml` or the environment, not inline on the command line.)
- **Shell-agnostic** — the same rules apply in PowerShell: no `;` chaining, no `$env:VAR = 'x'; command` one-liners.

## Git Auth

- Use `gh auth login` / `gh auth switch` to switch GitHub accounts — never prefix with `GH_TOKEN=...`.

## Why

Each chained command is one opaque action to the permission layer; splitting them gives one auditable tool call per intent. Inline env vars hide configuration in the command line and leak secrets into shell history; explicit auth tools (`gh auth login`) keep credentials in the keyring where they belong.

## Prerequisites

- Any shell — bash/zsh or PowerShell; the rules above are shell-agnostic.
- On Windows, the `*.sh` helper scripts bundled with these skills (git hooks, installers) run under Git Bash, which ships with Git for Windows — invoke them as `bash <script>`.
- For the Git Auth rule: `gh` CLI installed and authenticated.
- Cargo toolchain (`rustc`, `cargo`, `clippy`, `rustfmt`) on `PATH` — installed via `rustup`.

## Failure modes

- **`gh auth login` fails or token expired.** Re-run `gh auth login -h github.com` interactively, then `gh auth status` to verify. Don't paste the token into a shell command.
- **Account switch needed.** `gh auth switch -u <user>`. If that user's token is invalid, re-auth that account before switching.
- **Command needs elevated privileges.** Set up the privilege out-of-band rather than prefixing with `sudo` inline; an unattended agent shouldn't be entering passwords.
- **Shell aliases that hide what runs.** Avoid invoking aliases in agent procedures; spell out the real command so it's auditable.
- **Wrong toolchain.** If a project pins a toolchain via `rust-toolchain.toml`, `cargo`/`rustc` auto-select it — don't override with `+nightly` unless the project asks.