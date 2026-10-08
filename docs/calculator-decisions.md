# Calculator and settings decisions — Milestone 2

## Formula references and reuse

Reviewed the equations in Table 1 of Kunik/Kowal/Patan's [2025 research paper](https://ceur-ws.org/Vol-4073/BEHAIV2025_CRV_5.pdf), which lists Epley `w × (1 + r/30)` and Brzycki `w × 36/(37 − r)`. Reviewed the methods section of [Knutzen et al. (2007)](https://www.jssm.org/volume06/iss4/cap/jssm-06-455.pdf), an original study using Brzycki's rounded-coefficient convention `w / (1.0278 − 0.0278r)`. These conventions differ slightly numerically; this app explicitly uses the rational 36/(37−r) form, not the rounded coefficients.

Located Brzycki's original [1993 paper DOI](https://doi.org/10.1080/07303084.1993.10606684), but its publisher PDF returned 403; the original full text was not reviewed. Epley's original 1985 chart was not obtained. No accuracy percentage is claimed from these sources, and the formulas are not promoted as proof of strength.

Inspected MIT-licensed FineGym `fitness-calc` formula implementation/tests and LICENSE at commit `55d2590a110406de62a10e2896e49f039324afe8`; adapted its named formula selection and single-rep identity. Kept its notice in `THIRD_PARTY_NOTICES.md`. The TypeScript package's wider range and decimal rounding are not imported. We use 1–10 integer reps, positive mass, identity at one rep, and rational scaling down to a nanogram. Floating point is only presentation; nanogram precision is a numerical choice, not an accuracy claim.

Also reviewed MIT `GunnarStrandbergAB/strength_tracker` at `b9cae294f7feed4721730230c1a24f77509f0f93`, README and `E1RMConsolidationTests.swift`. Its shared-estimator consistency is useful, but its formula-switching/clamped high-rep behavior differs from the requested two named formulas. No code copied from this project. Our inputs reject unsupported reps instead of silently clamping.

## Warm-ups

Default progression is 40%×5, 55%×4, 70%×3, 85%×2. This is an original editable starter preset, not a universal recommendation. Lift and top-set reps are editable labels; the preset is not claimed to be individualized by lift. Users can change each step's percentage/reps, add/remove steps, and restore the preset.

Determine the greatest positive load at or below the requested top set using the shared finite inventory search. Display any top-target adjustment. Compute warm-up percentages from that actual load, round down to an available load, and when a percentage is below the bar use the minimum positive load below the top. Omit nonascending/repeated loads and expose the omission count. Require 1–8 strictly ascending percentages in 1–99 with 1–20 reps; reject unusable plans. Every shown set shares the plate renderer and exact actual load, with percentage target separately labeled. No zero loads or warm-ups at/above the top are returned.

No inspected open-source candidate supplied a verified native finite-inventory warm-up planner matching these constraints. Adapting the shared solver avoids adding another rounding rule or a large training app dependency.

## Attempts

Start from a desired third, find the greatest available positive load at/below it that is a whole multiple of the selected physical increment, then use opener 80–90% and second 90–97% ranges of that loadable third. Percentages/ranges and manual opener/second loads are editable. Choose automatic suggestions nearest the range midpoint (ties lower) while retaining a valid higher second. Require opener < second < third. All planned loads are actual loadable totals; unavailable combinations fail visibly. Manual overrides may leave preset ranges but must be exact, on increment and increasing. A goal is not evidence of strength.

The [current IPF rulebook](https://www.powerlifting.sport/fileadmin/ipf/data/rules/technical-rules/english/2026_IPF_Technical_Rulebook__effective_01_March_2026__v3.pdf), printed page 33, specifies ordinary multiples/progression of 2.5 kg; record exceptions exist. Default increment is 2.5 kg, independent from display units. Users must verify federation rules; this calculator is not a complete rules engine. The same book, page 9, specifies 25 kg red, 20 kg blue and 15 kg yellow. At 10 kg and under colors are unrestricted; green/white smaller discs are schematic choices. Pound plates use a neutral gym style. Every disc shows weight/unit and the accessible per-side list conveys the load without relying on color.

## Versioned persistence

One shared `LoadingModel` is injected across the Plates/Training/Attempts tabs. UserDefaults stores one JSON envelope under `liftToolkit.preferences` with schemaVersion 1: validated equipment, both finite inventories, independent display/plate units, and canonical physical plate target. Invalid edited target text cannot replace the last valid saved mass. Display switching never reparses rounded text. Input fields for calculators similarly retain canonical mass and update only their presentation on a unit change.

Schema 0 is an explicitly documented nominal-weight migration contract for tests, not a previously released version: top-level `bar`, `collarEach`, `target` WeightAmount objects plus both inventories and display/plate units. A schema-0 fixture proves conversion into canonical mass. Missing/malformed/oversized payloads, mismatched inventory units and unsupported versions fall back to validated starter settings with a notice. Preserve original unknown/corrupt bytes in a separate recovery key before later edits overwrite the active key. Do not reset silently. Validate decoded fields and the maximum available equipment load; limit encoded/decoded settings to 100 KB.

UserDefaults publication is a single value replacement, not a guaranteed durable transaction or cross-device sync. OS disk-write failures and app lifecycle behavior need native validation. Reverse selections and training plans are session-only; saved equipment is shared. No account/cloud storage is introduced.
