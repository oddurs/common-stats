# Working in this repository

<!-- standard:begin about -->
Common Stats is a native macOS menu bar system monitor written in Swift (AppKit plus SwiftUI) with no package dependencies.
<!-- standard:end about -->

## The seam

Do all automation through `scripts/task`. CI and the git hooks call nothing else.

```sh
scripts/task fmt          # format in place
scripts/task fmt:check    # swift format lint --strict
scripts/task lint         # fmt:check, then a debug build with warnings as errors
scripts/task test [name]  # the Swift Testing suites; a name filters them
scripts/task build        # universal "build/Common Stats.app", signed (see scripts/dev-cert)
scripts/task package      # dist/CommonStats.zip and checksums, as a release publishes them
scripts/task run          # build, quit the running copy, open the new one
scripts/task check        # lint + test + build: what CI runs
```

## Workflow

- Never commit to `main`. It only moves forward when a pull request is merged; the `pre-push` hook and branch protection both enforce this.
- One unit of work gets one worktree, one branch, and one pull request: `scripts/agent start <type>/<slug>`, then work in the printed path and finish with `scripts/agent ship "<type>(scope): subject" "<why>" --body-file <pr.md>`, where the body states the problem, the approach, and where a reviewer should be sceptical. It commits, checks, opens the pull request with auto-merge, keeps it rebased while CI runs, and cleans up after the merge. If it stops on a failed check or a conflict, fix the cause and run it again.
- Branch types: `feat fix chore docs perf refactor test`. The branch's first commit names the pull request and the squash commit on `main`.
- Never use `--no-verify`.
- User-facing changes go under `## [Unreleased]` in `CHANGELOG.md` in the same pull request. The site shows each release's section as "What's new".
- Release with `scripts/release <version>`. Never tag by hand.
- This repository follows the Common Tools app standard (`standard/` in oddurs/common-tools). Change shared files there and apply them to every app; only the regions between `standard:begin` and `standard:end` belong to this app.

## Commits

Conventional Commits: `type(scope): subject`. Write the subject in the imperative, at most 72 characters, with no trailing period. The body says why. Never add assistant or tool attribution: no co-author trailers, no "generated with" footers. The `commit-msg` hook rejects them.

## Code

<!-- standard:begin code -->
- `Sources/StatKit` holds samplers, history, the layout model, and the menu bar renderer, and contains no UI state. `Sources/StatBar` holds the app shell: status item, menu, and Settings.
- Accuracy comes first. Every reading comes from a public, unprivileged kernel or IOKit source. If a value can't be read, show `Format.missing`; never show a made-up zero. Don't add private APIs.
- A bug fix comes with the test that would have caught it. Sampler changes need an accuracy test against a system tool where one exists (`vm_stat`, `netstat`).
- Performance budgets are enforced in `PerformanceTests`. Don't loosen a budget to make a change pass.
- The menu bar image must stay a template image so macOS tints it. Widths come from the layout pass and never from values.
- For visual review, use `swift build && .build/debug/StatBar --snapshot out.png` and inspect `out.png` and `out-menu.png`. It renders offscreen, so no windows open.
<!-- standard:end code -->
