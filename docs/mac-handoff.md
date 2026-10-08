# Mac handoff — October 8, 2026

This repository carries the app source and project decisions. A new Codex chat on
the Mac does **not** inherit the Windows-local chat history. Read `AGENTS.md`,
`docs/product-brief.md`, this handoff, and the top of `docs/status.md` before work.

## Current state

- The app is native SwiftUI, built from `project.yml` with XcodeGen. The five tabs
  are Plates, Training, Attempts, Competition, and Bar path.
- GitHub Run 20 (`37773690035`, revision `cb26556`) built the unsigned simulator
  app and passed one five-tab UI smoke test. A redundant `simctl list --json`
  prerequisite then timed out, so the non-UI simulator tests did not start. The
  exact evidence is in `docs/native-run20-evidence.md`.
- The source now removes that prerequisite, reserves time for unit tests, and
  exports successful UI and unit evidence independently. Windows verification:
  18 injected Python orchestration tests, Bash syntax, and Git whitespace checks
  passed. These edits have **not** had an Apple build/test run.
- Lifter search results are now tied to the current query and dataset version so
  old rows disappear when either changes. This source edit is also uncompiled on
  Apple.
- The automatic video path still lacks proof of accurate tracking on real user
  clips. Simulator launch does not establish real-video accuracy or device
  readiness. The broader requirements remain in `docs/product-brief.md`.

## Usage and work direction

The Windows worker and five-minute leader automation are paused. Do not dispatch
the GitHub Actions native workflow, repeat paid hosted macOS runs, or turn the
automation back on. Build and test locally on the Mac, recording exact commands,
versions, results, and first failure. Start with the current source at the repo
head; check `git status` before editing. Avoid uploading private lifter videos.

The native workflow has only `workflow_dispatch`, so ordinary Git pushes do not
start it. The GitHub Actions allowance was exhausted by previous hosted runs.
Mac local builds avoid those Actions minutes but still consume the user's Codex
allowance while Codex is working.

## First Mac steps

Follow the direct Mac commands in `README.md` (starting near its `Build on a Mac`
section). Install Xcode and a suitable iOS Simulator runtime, select Xcode's
command-line tools, install XcodeGen, generate `PowerliftingApp.xcodeproj`, and
attempt one local build on an explicit simulator. Record the installed toolchain
and first actual compiler/test result before changing code to address it. Use the
focused validation guidance in `docs/native-validation.md`; keep each retry tied
to a concrete diagnostic. No Apple signing account is needed for an unsigned
Simulator build. A physical iPhone and representative clips are later gates.

## Suggested first Codex message on the Mac

> Read AGENTS.md, docs/product-brief.md, docs/mac-handoff.md, and the top of
> docs/status.md. Work locally in this repository. Do not trigger GitHub Actions
> or restart the old automation. Check git status and the current toolchain,
> generate the project, then run one local unsigned Simulator build. Report the
> exact result and fix the first concrete diagnostic. Keep real-video accuracy
> and physical-device validation claims separate from a successful build.
