# Native SDK-matched installed runtime proposal

Scope only, October 8, 2026, 07:38 ET. No selector modification or CI retry.

## Retained facts

Run18's verified diagnostic archive records Xcode16.4/build16F6, selected developer
directory `/Applications/Xcode_16.4.app/Contents/Developer`, Apple Swift6.1.2 and
`xcrun --sdk iphonesimulator --show-sdk-version` output18.5 in setup.log.
Apple's [Xcode16.4 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16_4-release-notes)
identify the iOS18.5 SDK. This supports the SDK observation; it does not establish
that every later runtime is incompatible or explain run18's migration wait.

Actual saved simulators.json, not an assumed runner image inventory:

| Available iOS runtime | Build | Available iPhones |
| --- | --- | --- |
| 18.5 | 22F77 | 6 |
| 18.6 | 22G86 | 6 |
| 26.0.1 | 23A8464 | 10 |
| 26.1 | 23B86 | 10 |
| 26.2 | 23C54 | 10 |

The installed18.5 runtime identifier is
`com.apple.CoreSimulator.SimRuntime.iOS-18-5`; its iPhone16 device type is present.
Deterministically first available iPhone under the existing name/UUID ordering:
`565DED02-59D6-4021-88CA-21B8BEF5F415`, iPhone16, Shutdown.
This is a preexisting provenance/compile candidate, not an owned test device.

Current `tools/ci/select-simulator.py` selects the highest available iOS17+
version regardless of the active SDK. Actual Windows replay against the retained
inventory selected26.2/`841E0288-2704-4A18-A304-BF477CA384A8`. A second replay
restricted only the in-memory runtime list to recorded18.5 and selected the
candidate above. Neither replay boots, creates or modifies a simulator.

## Recommended bounded experiment

If approved, record the active simulator SDK in a separate setup receipt, validate
its numerical version, and pass it explicitly to the existing selector. Require
an available installed iOS17+ runtime matching that SDK's major/minor version and
an available valid-UUID iPhone in that runtime. Retain deterministic device
selection. Record requested SDK and chosen runtime in the selection receipt.
Fail with a clear missing-match error rather than silently choosing a newer
runtime or downloading components. Reinspect live inventory on each future run;
the retained candidate is not a fixed hardcoded UDID.

Preserve distinct original versus newly created owned device, runtime/device-type
identity checks, same-owned UI/non-UI experiment and readiness gate. Keep every
existing process/phase/job budget and separate exports/exact67-method source gate.
No cleanup bypass, global service reset, runtime download, repeated run or claim
that SDK matching fixes migration. Selecting18.5 still creates a fresh owned
device and may require slow migration; the expected benefit is unmeasured.

Focused source checks: actual retained inventory replay, valid numerical SDK with
patch normalization, absent/unavailable matching runtime, missing/invalid iPhone,
deterministic ties, and refusal to fall back to26.2 when18.5 is absent. Preserve
current selector call compatibility only if callers explicitly need it; the
workflow should always supply the measured SDK. This proposal does not change
Xcode, deployment target or application APIs.

## Decision and time

Scope complete; leader decision next, no reliable review ETA before response.
If approved, source/checkpoint estimated10–20 minutes with no hard deadline and
uncertainty in existing selector test coverage and shell receipt plumbing.
Re-estimate after implementation sizing. A later separately authorized native
run remains provisionally15–22 minutes after actual runner start, with existing
build8/test10/job30 minute limits. No native-readiness date can be inferred before
actual boot/readiness/test/export/cleanup receipts. Production refresh, private
video accuracy and release remain separate gates.
