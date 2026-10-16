# Working in this repository

Common Stats is a native macOS menu bar system monitor written in Swift (AppKit plus SwiftUI) with no package dependencies.

## The seam

Do all automation through `scripts/task`. CI and the git hooks call nothing else.

```sh
scripts/task fmt       # format in place
scripts/task fmt:check # swift format lint --strict, format only
scripts/task lint      # fmt:check, then a debug build with warnings as errors
scripts/task test      # unit, accuracy, and performance tests
scripts/task build     # universal build/Common Stats.app
scripts/task check     # lint + test + build
```

## Workflow

- Never commit to `main`. It only moves forward when a pull request is merged; the `pre-push` hook and branch protection both enforce this.
- One unit of work gets one worktree, one branch, and one pull request: `scripts/agent start <type>/<slug>`, then work in the printed path, `scripts/agent commit`, `scripts/agent pr`, and `scripts/agent done` after the merge.
- Branch types: `feat fix chore docs perf refactor test`.
- Run `scripts/task check` until it is green before opening a pull request. Never use `--no-verify`.
- In the pull request description, state the problem, the approach, and where a reviewer should be sceptical.

## Commits

Conventional Commits: `type(scope): subject`. Write the subject in the imperative, at most 72 characters, with no trailing period. The body says why. Never add assistant or tool attribution: no co-author trailers, no "generated with" footers. The `commit-msg` hook rejects them.

## Code

- `Sources/StatKit` holds samplers, history, the layout model, and the menu bar renderer, and contains no UI state. `Sources/StatBar` holds the app shell: status item, menu, and Settings.
- Accuracy comes first. Every reading comes from a public, unprivileged kernel or IOKit source. If a value can't be read, show `Format.missing`; never show a made-up zero. Don't add private APIs.
- A bug fix comes with the test that would have caught it. Sampler changes need an accuracy test against a system tool where one exists (`vm_stat`, `netstat`).
- Performance budgets are enforced in `PerformanceTests`. Don't loosen a budget to make a change pass.
- The menu bar image must stay a template image so macOS tints it. Widths come from the layout pass and never from values.
- For visual review, use `swift build && .build/debug/StatBar --snapshot out.png` and inspect `out.png` and `out-menu.png`. It renders offscreen, so no windows open.
