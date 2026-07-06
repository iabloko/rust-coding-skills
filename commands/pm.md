---
description: PM via GitHub issues (plan / start / next / advance / status / create-issues).
allowed-tools: Bash(gh issue *), Bash(gh label *), Bash(gh pr list *), Bash(gh pr view *), Bash(git checkout -b *), Bash(git status *), Bash(git rev-parse *), Read
---

Scope: $ARGUMENTS

Invoke the `managing-github-issues` skill. Interpret `$ARGUMENTS` as one of:

- `plan <feature>` — decompose the feature into dependency-linked task issues.
- `start <number>` — pick up an issue and start the task (label `in-progress`, create the branch).
- `next` — show ready (unblocked) issues.
- `advance` — close completed tasks and unblock downstream work.
- `status` — print the project dashboard.
- `create-issues` — batch-create issues from a confirmed plan.

If `$ARGUMENTS` is empty, default to `next`.

The skill is the single source of truth for label conventions (`ready` / `blocked` / `epic` / `in-progress`), the "Blocked by: #N" linking convention, and the read-vs-write tool boundary (no force-push, no repo/branch deletions, never merge a PR on the user's behalf).

Echo any state-changing `gh`/`git` command back to the user before running it.