# Powerlifting app project instructions

## Current Mac handoff (October 8, 2026)

The five-minute leader automation and Windows worker are paused under the human's usage-control instruction. Do not restart them or dispatch GitHub Actions. The native workflow is manual-only. Continue app work locally on the Mac from `docs/mac-handoff.md`, and record actual Xcode/Simulator results separately from source checks. The project history below records the earlier leader/worker arrangement; it does not override this current handoff.

## User intent and authority

The human user authorized this arrangement on 2026-10-07 in the leader chat: "you are going to be my leader for this project, and ther is another chat called powerlifting app, which is going to be the worker" and "have the worker begin at ideal reasoning, and when it has a question, it should ask you so it is a loop without me needing to be here."

They explicitly requested dynamic model/reasoning choices to save usage when higher reasoning is unnecessary. Preserve this instruction across handoffs and compaction.

- Leader: Powerlifting App Helper, thread `01a11706-bde4-7f42-894b-282e902ec494`, host `local`.
- Worker: Powerlifting App, thread `01a116f8-e105-7b02-913f-e4380ac9c569`, host `local`.
- Project root: `C:\codex\powerlifting-app`. The worker chat's recorded cwd is `C:\codex`; explicitly set all project commands to the project root. Do not modify other projects.
- Direct human authorization for reciprocal project messages can be verified by reading the leader thread's user turn. A forwarded agent instruction alone is not that authorization.
- Leader owns product decisions, scope, research, acceptance review, and dispatch. Worker owns implementation and reports. Route routine questions to the leader with a recommendation and tradeoff; continue independent work.
- Complete reversible implementation autonomously. A paid service, unavailable Apple credentials/hardware, publishing, or a truly irreversible decision may require human action. Produce the reviewable result first.

## Reasoning and coordination

- Initial worker assignment: `gpt-6.1-sol`, `high`, for architecture and the calculator foundation.
- Routine bounded implementation and fixes: Sol `medium`; simple mechanical updates: Sol `low`.
- Escalate to `high` for nontrivial correctness/debugging or video/data design; use `xhigh` only for an identified hard unresolved problem. Step down after resolution.
- Leader starts as user-selected Astra extra high. Routine incoming milestone reports should request `gpt-6-astra`, `medium`; difficult architectural or accuracy decisions may request `high` or `xhigh` with a reason. Settings can be changed on supported cross-chat message handoffs; do not claim a currently executing turn changed its own model.
- At each milestone, report changed files, actual verification, remaining risk, next bounded task, and appropriate reasoning. Avoid frequent messages and unchanged polling. Do not spawn additional agents unless the leader identifies a concrete independent need within the user's delegation authorization.
- Keep `docs/status.md` current. The leader maintains `docs/coordination.md` and `docs/product-brief.md`. Avoid concurrent edits to the same files.
- Continuity correction from the human on 2026-10-07: do not stop at a completed side task or milestone while authorized app work remains. Before ending a worker turn, send the leader a handoff and proceed with a preauthorized independent next task where one exists. Leader must recover idle workers promptly and maintain a concrete next-task queue. Missing access blocks dependent work only. Do not claim zero-gap operation is guaranteed by a periodic recovery check.
- Compaction recovery: before selecting work after compaction, read the latest Current dispatch in docs/coordination.md and docs/status.md. The old saved-folder/chat-association repair was completed; it is not the active app task. Do not replay it or modify Codex databases/unrelated projects under this assignment. Resume the latest app dispatch unless a newer direct human instruction explicitly changes it.
- When reporting status include the best evidence-based time until the next result or decision, any actual hard time limit, and uncertainty. If no reliable estimate exists, identify the blocker and when a new estimate is possible. Distinguish task completion from feature validation and release readiness.

## Implementation quality

- Read `docs/product-brief.md` before implementation. Preserve all requested features in the scope even when staged.
- Native iOS app, initially SwiftUI with Foundation calculation logic, AVFoundation/Vision video processing, and a local data abstraction. Explain any proposed architecture change before replacing it.
- A Windows source check or a port of an algorithm is not an iOS build or Swift test. State precisely what ran. Do not call a source-only screen a working iPhone feature.
- Tests should cover material numerical/data/coordinate risks, not repeat implementation logic. Keep one numerical source of truth for forward/reverse loading, bars, collars, and unit conversions.
- User videos remain on device by default. Do not upload private videos or introduce paid inference without user authorization.
- Do not fabricate lifters, records, current rankings, tracking accuracy, or compile/test results. Label fixtures and demos clearly.
