---
description: Strict five-pass Rust quality gate (code, security, architecture, acceptance, AI-native).
allowed-tools: Read, Bash(git diff *), Bash(git log *), Bash(git rev-parse *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh issue view *)
---

Scope: $ARGUMENTS

If `$ARGUMENTS` is empty, default the scope to `git diff master...HEAD` (or `main...HEAD` if the repo's default branch is `main`). If it looks like a PR number, resolve it via `gh pr diff <N>`. Otherwise pass it through verbatim as the diff range.

Launch the five review agents **in parallel** — a single message with five Agent tool calls:

1. `@code-reviewer` — Pass 1, code quality (unwrap/panic on shipping paths, clone-spam, SRP, clippy/fmt gate)
2. `@security-auditor` — Pass 2, security audit (`unsafe` soundness, integer overflow, panic-as-DoS, SQL injection, secrets, `cargo audit`/`deny`)
3. `@architect-review` — Pass 3, architecture consistency (layer boundaries, trait/DI, reinvented crates)
4. `@acceptance-auditor` — Pass 4, intent / spec alignment (does the diff solve the linked issue?)
5. `@ai-native-reviewer` — Pass 5, AI-native-coding practices (comments WHY not WHAT, instruction files, real objects over mocks, delete-don't-tombstone)

Each agent returns a verdict line (`PASS / NEEDS WORK / FAIL`) plus its findings.

Aggregate the five reports into one Quality Gate Summary table:

```
## Quality Gate Summary

| Review             | Verdict        | Critical | Major | Minor |
|--------------------|----------------|----------|-------|-------|
| Code               | pass/warn/fail | N        | N     | N     |
| Security           | pass/warn/fail | N        | N     | N     |
| Architecture       | pass/warn/fail | N        | N     | N     |
| Acceptance         | pass/warn/fail | N        | N     | N     |
| AI-Native Practices| pass/warn/fail | N        | N     | N     |

**Overall**: PASS / NEEDS WORK / FAIL

### Action items
1. <Critical/Major items, ordered>
```

Then list every Critical and Major finding from all five passes with `Rule / Severity / Location / Issue / Fix`. Skip Minor unless the overall verdict is PASS (then include them as polish).

The review is **strict** by design — this user asked for blunt, thorough feedback that does not wave through sloppy or spaghetti code. Do not soften findings; do teach the *why* of each. Calibrate severity honestly per the `reviewing-changes` skill's severity table.

## When to use the inline skill instead

If parallel agents are unavailable in the current harness, fall back to invoking the `reviewing-changes` skill directly — it runs the same five passes in a single inline pass. The trade-off is no parallelism, but the procedure is identical.