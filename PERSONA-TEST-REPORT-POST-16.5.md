# Persona test — post-16.5 comparison

Re-run of full Pass B (all 86 personas) on the 16.5 build, compared against
the pre-16.5 baseline from `PERSONA-TEST-REPORT-2026-06-13.md`.

## Headline numbers

| Metric | Pre-16.5 | Post-16.5 | Delta |
|---|---:|---:|---:|
| Personas tested | 86 | 86 | — |
| Status `ok` | 86/86 | **86/86** | unchanged |
| Errors / timeouts | 0 / 0 | 0 / 0 | unchanged |
| Stubs (<1000c) | 13 | **8** | **−5** |
| `refusal_signal` flagged | 2 (false +) | **0** | **−2** |
| Total chars produced | 550,970 | **581,917** | +30,947 (+5.6%) |
| Total LLM time | 17.7 min | 17.5 min | similar |
| Avg response | 6,407 c | **6,766 c** | +359 (+5.6%) |

**16.5 is a net win.** Stub count dropped from 13 to 8 (−38%), false-positive
refusals eliminated, total output volume up 5.6%.

## 7 rewritten starters — all stuck their gains

| persona | pre | post | × |
|---|---:|---:|---:|
| **aeo** | 556 | 2,858 | 5.1× |
| **code-reviewer** | 362 | 2,478 | 6.8× |
| **api-tester** | 486 | 2,921 | 6.0× |
| **sprint-prioritizer** | 450 | 3,645 | 8.1× |
| **senior-project-manager** | 640 | 3,445 | 5.4× |
| **experiment-tracker** | 518 | 3,201 | 6.2× |
| prompt-engineer | 498 | 830 | 1.7× ⚠ |

6 of 7 hold their 5-8× gains in the full Pass B. `prompt-engineer` regressed
to 830c — still up from 498c but well below the 5,911c verification result.
Either variance or the rewritten starter needs another pass.

## Two sharp gains without a rewrite

| persona | pre | post | × | likely cause |
|---|---:|---:|---:|---|
| marketing | 691 | 4,075 | 5.9× | model variance + opener clause helped framing |
| mcp-builder | 6,349 | 29,860 | 4.7× | opener clause unlocked longer-form output |

The opener clause ("Respond directly. Do not introduce yourself…") is
helping more than just the false-positive refusals.

## Five sharp regressions — the opener-clause cost

| persona | pre | post | Δ | analysis |
|---|---:|---:|---:|---|
| **designer** | 13,783 | 1,384 | −12,399 | original Expert; the verbose framing was the reply |
| **accessibility-auditor** | 12,263 | 519 | −11,744 | imported persona; opener clipped its structured walk-through |
| **product** | 9,558 | 1,754 | −7,804 | original; same pattern as designer |
| **feedback-synthesizer** | 6,971 | 737 | −6,234 | imported; clipped |
| project-shepherd | 2,340 | 1,059 | −1,281 | minor; still above stub |

**Root cause:** the opener clause's "skip preamble — get to the work" line
is being interpreted as "be brief" by Gemini Flash for personas whose
deliverables literally ARE structured analyses (audits, deep evaluations).
Their pre-16.5 verbosity wasn't preamble — it was the substance.

## 8 remaining stubs after 16.5

| persona | post | status |
|---|---:|---|
| sales | 980 | deferred starter (already specific) |
| **prompt-engineer** | 830 | rewritten but variance — re-rewrite candidate |
| **accessibility-auditor** | 519 | opener-clause regression — exclude from clause |
| **feedback-synthesizer** | 737 | opener-clause regression — exclude from clause |
| financial-analyst | 424 | deferred starter — needs rewrite (was wrong call) |
| outbound-sdr | 975 | openfang Agent — scheduled-input design |
| pipeline-curator | 943 | openfang Agent — same |
| deep-research | 898 | openfang Agent — same |

## Recommendations for 16.6 (small)

1. **Exclude 2 personas from the opener clause:** `accessibility-auditor`,
   `feedback-synthesizer` — their deliverables ARE the verbose walk-through.
   Add a per-persona `omit_directness_clause: true` flag in experts.ts.
2. **Rewrite 2 more starters that I deferred wrongly:** `sales`,
   `financial-analyst` — Pass B post-16.5 confirms they're starter-prompt-fit
   issues, not variance.
3. **Re-rewrite prompt-engineer's starter** with even more concrete payload
   (the eval-harness one didn't stick).
4. **Leave openfang Agents alone** — they're designed for scheduled CRM/inbox
   inputs; cold-chat stubs are by design.

## Two-pass aggregate

| Pass | Date | Stubs | Refusals | Total chars | Avg |
|---|---|---:|---:|---:|---:|
| Pre-16.5 baseline | earlier today | 13 | 2 | 550,970 | 6,407 |
| Post-16.5 | now | **8** | **0** | **581,917** | **6,766** |

Net: **−38% stubs**, **−100% false refusals**, **+5.6% total output**, with
the cost of 5 regressions in the originally-verbose personas.

## Artifacts

- `e2e/persona-results-1781359247844.json` — pre-16.5 Pass B
- `e2e/persona-results-1781380016365.json` — post-16.5 Pass B
- `e2e/persona-results-1781362854787.json` — post-16.5 smoke verification
- `e2e/screenshots/personas/<slug>.png` — overwritten with post-16.5 frames
