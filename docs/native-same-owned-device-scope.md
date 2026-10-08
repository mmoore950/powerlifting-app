# Same owned warm simulator experiment: scope only

October 8, 2026, 07:03 ET. No orchestration implementation, push or new CI.

## Evidence and recommendation

Run17 at47b406b successfully compiled on the preexisting destination, booted and
verified the new owned UI simulator, and passed UI on it in380.280s. Switching
non-UI to the original destination left a158.434s child budget.42 core methods
passed but app-host installation/launch did not complete; CoreSimulator405 and
Mach-308 appeared near termination. This does not establish the switching as
the cause, and those logs cannot prove a fixed root cause.

Recommend a bounded experiment: keep original compile destination and create/
boot/readiness procedure, then execute UI **and non-UI on the same verified new
owned device**, retaining two commands and two independent result bundles. It
removes the second destination transition while keeping the prior startup
evidence. The benefit is plausible, unmeasured; passing on one run would prove
that execution only, not the cause of previous failures.

## Minimal source changes if approved

- Keep `verified_record` binding the new device to run/attempt, original selected
  UDID, matching runtime/name/device type and preexisting inventory exclusion.
  Do not weaken its `owned != original` check. Change command construction so
  both test destinations use **that verified owned UDID**; remove the separate
  test planner's assumption that UI/non-UI destinations must differ. A plain
  caller-supplied equal UUID cannot bypass fresh-device ownership verification.
- Retain UI-first and `-only-testing:PowerliftingAppUITests`; retain non-UI
  `-skip-testing:PowerliftingAppUITests`, no method filtering/skip relaxation.
- Recheck immutable ownership record and `bootVerified` before non-UI. Recommend
  one bounded live inventory observation requiring the same available Booted
  UDID/runtime/name/type. Refuse changed/unavailable/shutdown state rather than
  reboot, reset or retry. This observation is inside the same560s budget: child
  cap10s plus existing20s cleanup reserve; UI reserves those30s for the following
  observation. No polling loop or separate readiness step with a new budget.
- Retain existing cancellation forwarding, owned command cleanup, overwritten
  progress receipts, nonzero/timeout refusal and final exact inventory gate.
  Add meaningful planner/changed identity/Booted-state/budget/failure regressions.
  Do not rewrite the successful source inventory to accommodate missing tests.

## Contamination and reset assessment

`ToolkitSmokeTests` launches and terminates `XCUIApplication` using defer; it
opens the five tabs without changing equipment/settings, connecting data or
importing media. It supplies no capture or synthetic tracking state. App-host
media/export tests construct separate UUID temporary roots, explicit stores,
and remove their owned roots. UI app termination plus a separate app-host test
launch is the minimal isolation boundary for this diagnostic experiment.

Do not erase/recreate/reboot the simulator or clear global services between
phases: those actions discard the warm state and alter the experiment. Do not
claim a new process resets every persistent app preference or OS service. A
same-device pass is sequential shared-device acceptance, not independent clean
state for both phases. If retained logs reveal contaminated state or failed
launch/termination, report it and propose a separately reviewed narrow reset.
Provider/device/private-data acceptance is still absent; UI never selects Files.

## Inventory, attachments and bounds

Require all source IDs exactly once across both logs:63 expected at6f4da95 if
no other methods change, one UI/42 core/20 app-host. This is an expected count,
not a pass. Keep `test-ui.xcresult` and `test-unit.xcresult`, their separate
`screenshots/ui` and `screenshots/unit` exports and existing exact named group
selection. A shared device does not merge attachment ownership; retain exact
job/revision/test/manifest provenance and require both exports/full job success.
Actual generated suggested names remain unobserved; no raw result substitution.

One monotonic560s shared test budget remains authoritative, each subprocess
retains20s cleanup reserve; all observations consume that budget. Workflow
test10min/job30min/build8min/prepare2min/cleanup2min unchanged. Run17 UI duration
would leave roughly178s before the extra inventory observation; its actual cost
reduces the unit allowance further. Warm installation savings are unmeasured,
so do not guarantee completion or expand the budget to hide a failure.

## Decision and estimate

Leader review is the next decision. Scope target5–10min from07:01ET, provisional,
no hard deadline. If approved, bounded source/regression implementation estimated
15–25min; actual native diagnostic result15–22min after runner start provisionally,
with queue/boot/UI/installation scheduling uncertainty and unchanged hard limits.
Re-estimate from actual phase progress, separately from app/provider/realaccuracy
or release readiness. Continue the generated local annotation walkthrough while
review is pending. No paid services or new CI authorized by this proposal.
