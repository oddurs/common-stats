# Contributing

Thanks for helping. Common Stats stays small on purpose, so open an issue before starting anything large.

## Setup

```sh
scripts/setup          # wire the git hooks, once
scripts/agent doctor   # check tools and repository state
```

You need macOS 14 or later and Swift 6 or later. The Command Line Tools are enough.

## Workflow

Every change goes through a pull request, and pull requests merge themselves. `main` only moves forward when a pull request is merged; branch protection and the `pre-push` hook both enforce this.

Each change gets its own worktree, branch, and pull request:

```sh
scripts/agent start fix/cpu-wraparound   # creates ../.worktrees/statbar/fix/cpu-wraparound
cd ../.worktrees/statbar/fix/cpu-wraparound
# ... make the change ...
scripts/agent ship "fix(cpu): handle tick counter wraparound"   # commit, check, open the PR, merge it when CI passes, clean up
```

`ship` turns on auto-merge, so the pull request squash-merges itself once the `required` check passes. While it waits, it rebases onto `main` whenever `main` moves and checks again. If a check fails or the rebase conflicts, it stops and says so: fix it, then run `scripts/agent ship` again. `commit`, `pr`, and `done` still work one step at a time.

Branch names are `<type>/<slug>`, where type is one of `feat fix chore docs perf refactor test`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`. Write the subject in the imperative, keep it to 72 characters, and leave off the trailing period. The body explains why; the diff already shows what. The `commit-msg` hook checks this.

Don't add tool or assistant attribution lines (co-author trailers, "generated with" footers). The hook rejects them.

## Checks

```sh
scripts/task check   # lint + test + build, the same thing CI runs
```

A branch must pass this before it becomes a pull request. A bug fix comes with the test that would have caught it. Changes to a sampler need an accuracy argument: explain what the kernel reports and why your reading matches it.

## Review

This is a solo-maintained project, so branch protection requires zero approvals and pull requests merge themselves once CI is green. The `required` status check and up-to-date branches are still enforced.
