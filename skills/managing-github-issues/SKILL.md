---
name: managing-github-issues
description: Plan and track work as GitHub Issues — decompose a feature into dependency-linked task issues, label conventions (ready/blocked/epic/in-progress), the "Blocked by #N" convention, and a strict read-vs-write tool boundary. Use whenever planning a feature, breaking down work, or tracking task state via gh issues.
allowed-tools: Read, Bash(gh issue *), Bash(gh label *), Bash(gh pr list *), Bash(gh pr view *), Bash(git checkout -b *), Bash(git status *), Bash(git rev-parse *)
---

# Managing Work via GitHub Issues

Lightweight project management using GitHub Issues as the source of truth — no external tracker. Pair with `committing-changes` (branch/PR flow) and `designing-architecture` (a design hands off a task list this skill turns into issues).

## Label conventions

Create these labels once per repo (`gh label create <name> --color <hex>`):

- `epic` — a parent feature spanning multiple task issues.
- `ready` — unblocked, can be started now.
- `blocked` — waiting on another issue (see the linking convention).
- `in-progress` — actively being worked (has an assignee + a branch).
- Optional type labels reuse the branch prefixes from `committing-changes`: `feat`, `fix`, `refactor`, `test`, `chore`, `infra`, `perf`.

## Dependency linking

- A blocked issue names its blockers in the body: `Blocked by: #12, #15`. When those close, it becomes `ready`.
- An epic lists its children as a task list (`- [ ] #21`) so GitHub renders progress.
- "Ready" = no open `Blocked by` issue. `next` computes this.

## Subcommands

- **`plan <feature>`** — decompose a feature (or a `designing-architecture` output) into small, independently-testable task issues, each sized for one red-green-refactor cycle ([[running-tdd-cycles]]). Set `Blocked by` links to encode order; label the parent `epic`, leaves `ready`/`blocked`. Present the plan and the issues you *would* create, then create them on confirmation.
- **`start <number>`** — read the issue, label it `in-progress`, and create the feature branch per `committing-changes` (`git checkout -b <type>/<slug>-<number>`). Don't start a `blocked` issue.
- **`next`** — list `ready` issues (open, not `blocked`, no open blocker), most-unblocking first. Default when no subcommand is given.
- **`advance`** — after a PR merges, close the completed issue and re-label downstream issues whose last blocker just cleared from `blocked` → `ready`.
- **`status`** — a dashboard: open epics with child progress, in-progress issues + their branches/PRs, ready count, blocked count.
- **`create-issues`** — batch-create from a confirmed plan file/list.

## Writing good task issues

- Title: imperative, specific (`Add email-uniqueness check to register()`), not vague (`user stuff`).
- Body: the acceptance contract (`acceptance-auditor` will check the diff against it) — what "done" looks like, the test that proves it, and any `Blocked by` links.
- One issue = one logical change = one PR = one red-green-refactor-sized chunk. If an issue needs more than one PR, it's an epic; split it.

## Tool boundary (read vs write)

- **Read freely:** `gh issue list/view`, `gh label list`, `gh pr list/view`, `git status`.
- **Write actions — echo the command to the user first:** `gh issue create/edit/close`, `gh label create`, `git checkout -b`.
- **Never:** merge or close a PR on the user's behalf, force-push, delete a repo/branch, or bulk-close issues without confirmation. Mirrors `committing-changes` — the human keeps the destructive/merge decisions.

## Cross-references

- `committing-changes` — branch naming, the PR flow an issue's work lands through, the no-merge boundary.
- `designing-architecture` — its TDD-ready implementation plan is the input to `plan`.
- `running-tdd-cycles` — each task issue is sized for one red-green-refactor cycle.
- `reviewing-changes` (`acceptance-auditor`) — checks a diff against the issue's acceptance contract.