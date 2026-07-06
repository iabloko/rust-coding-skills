---
name: committing-changes
description: Commit via feature branch + PR + git hooks; never push main, never merge. Pre-commit runs cargo fmt/clippy/test.
allowed-tools: Read, Edit, Write, Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git checkout *), Bash(git branch *), Bash(git merge *), Bash(git fetch *), Bash(git rev-parse *), Bash(gh pr *), Bash(gh repo *), Bash(cargo fmt *), Bash(cargo clippy *), Bash(cargo test *), Bash(bash scripts/install-hooks.sh), Bash(bash scripts/install-pr-size-workflow.sh)
---

## Workflow

1. **Install hooks** (once per repo). From inside the repo (`<skills>` = this plugin's `skills/` directory — the folder holding this skill's own folder; `./skills/` in the source repo):
   ```
   bash <skills>/committing-changes/scripts/install-hooks.sh
   ```
   Copies `pre-commit`, `commit-msg`, `pre-push` into `.git/hooks/` and makes them executable. Idempotent.

   Then install the CI workflow (fmt + clippy + test + `cargo audit`):
   ```
   bash <skills>/committing-changes/scripts/install-ci-workflow.sh
   ```
   Drops `.github/workflows/ci.yml`. This is the mechanical half of the quality gate — the same checks the pre-commit hook runs, enforced on every push/PR. Idempotent.

   And the PR-size CI workflow:
   ```
   bash <skills>/committing-changes/scripts/install-pr-size-workflow.sh
   ```
   Drops `.github/workflows/pr-size.yml` and appends `.gitattributes` exclusions. Idempotent.

2. **Branch check.** If on `main`/`master`, switch to a feature branch:
   ```
   git checkout -b <type>/<description>
   ```
   Valid `type` prefixes: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `infra`, `perf`, `ai-native`.

3. **Auto-fix before commit.** Run the project's formatter/linter:
   ```
   cargo fmt --all
   cargo clippy --all-targets --all-features -- -D warnings
   ```
   The pre-commit hook (if installed) runs the full quality gate — `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`. Fix, don't bypass.

4. **Commit & push.**
   ```
   git add <specific paths>
   git commit -m "<subject conforming to rules below>"
   git push -u origin <branch>
   ```
   Stage specific paths — don't `git add -A` a `cargo fmt` sweep of files your change didn't touch (off-scope diff; see [[engineering-philosophy]] "Stay In Scope"). Never commit `target/` (it's in `.gitignore`); **do** commit `Cargo.lock` for binaries/apps, and for libraries too by current convention.

5. **Sync with main.**
   ```
   git fetch origin main
   git merge origin/main
   ```
   Resolve conflicts (including `Cargo.lock` — re-run `cargo build` to regenerate it cleanly rather than hand-merging the lock); commit the merge; push.

6. **PR creation** (first push only).
   ```
   gh pr list --head <branch>
   gh pr create --fill   # if no PR exists yet
   ```

7. **Branch cleanup** (after the user has merged).
   ```
   git fetch --prune
   git branch --merged main | grep -v '^\*\|main\|master' | xargs -r git branch -d
   ```

## Rules

- **Never push directly to `main`/`master`.** Always feature branches + PRs. The `pre-push` hook blocks this.
- **Never merge branches or PRs.** Always let the user merge.
- **Never force-push.** No `--force`, no `--force-with-lease`. Create new commits instead.
- **One logical change per commit.**
- **PR size**: ≤1000 changed lines per PR (excluding tests, docs, lockfiles, generated). Enforced by `.github/workflows/pr-size.yml`.
- **Never bypass a failing hook** with `--no-verify`. A red hook is a real problem — fix it. See [[engineering-philosophy]] "Investigate, Don't Mask".
- **Commit-message subject** (enforced by the `commit-msg` hook):
  - Capital start, imperative mood ("Add", "Fix", "Refactor" — not "added"/"adds").
  - ≤ 72 chars.
  - No trailing period.
  - No `Co-Authored-By:` lines.

## Why this discipline

- *No direct push to main* → `main` never breaks; every change is reviewable.
- *No agent-side merge* → the human keeps the merge decision.
- *No force-push* → history is preserved; reviewers can trust hashes.
- *One logical change per commit* → `git bisect` works; reverts are surgical.
- *No `--no-verify`* → the quality gate actually gates.
- *Subject rules* → consistent, readable log; no noisy attribution.

## Cross-references

- `shell-discipline` — issue these `git`/`gh` commands one per call, no `&&` chains.
- `engineering-philosophy` — "Small Steps" and "Investigate, Don't Mask" map to one-logical-change-per-commit and don't-bypass-hooks.
- [[rust-conventions]] — the fmt/clippy/test gate the pre-commit hook runs.

## Reference

- [scripts/commit-msg](scripts/commit-msg) — subject-line rules enforcer.
- [scripts/pre-commit](scripts/pre-commit) — runs `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` before commit.
- [scripts/pre-push](scripts/pre-push) — blocks direct push to `main`/`master`.
- [scripts/install-hooks.sh](scripts/install-hooks.sh) — idempotent installer.
- [templates/ci.yml](templates/ci.yml) — GitHub Actions workflow: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`, `cargo audit`.
- [scripts/install-ci-workflow.sh](scripts/install-ci-workflow.sh) — idempotent installer for `ci.yml`.
- [templates/pr-size.yml](templates/pr-size.yml) — GitHub Actions workflow that labels PR size and fails when >1000 changed lines.
- [templates/gitattributes.example](templates/gitattributes.example) — `linguist-generated`/`linguist-vendored` entries so GitHub collapses generated files in diffs.
- [scripts/install-pr-size-workflow.sh](scripts/install-pr-size-workflow.sh) — idempotent installer for the workflow + `.gitattributes` block.