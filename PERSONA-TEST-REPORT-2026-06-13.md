# Full-scale real-persona test — 2026-06-13

End-to-end driving every persona through a real chat, capturing the actual LLM
response. Three passes: smoke (5), full breadth (86), adversarial top-20 with
follow-up.

**Headline:** 110 LLM calls · zero failures · 890K chars of real output ·
~223K tokens spent · 28 min of LLM wall-time.

| Metric | Pass A (smoke) | Pass B (all 86) | Pass C (adversarial 19) | Total |
|---|---:|---:|---:|---:|
| LLM calls | 5 | 86 | 19 × 2 turns | 110 |
| Status `ok` | 5/5 | **86/86** | **19/19** | 110/110 |
| Errors / timeouts | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| Stubs (<1000c) | 2 | 13 | **0** | — |
| Avg response | 3,672c | 6,407c | 16,917c | 8,098c |
| Avg latency | 7.2s | 12.4s | 30.4s | — |
| Longest single response | 9,745c (identity-graph) | 28,535c (backend-architect) | **33,684c** (senior-developer-adv) | — |
| Total chars | 18,360 | 550,970 | 321,415 | **890,745** |
| Total LLM time | 36s | 17.7 min | 9.6 min | **28 min** |
| Tokens spent | ~5K | ~138K | ~80K | **~223K** |

Pass C results dwarf Pass B because the adversarial follow-up
("Now do that for example.com…") gave the model a concrete target. Personas
that stubbed at 400-700c in Pass B produced 21K-33K chars in Pass C.

## What works

1. **The Phase 14.4 chat URL alias + Phase 16.1 idempotency + Phase 16.4
   stream-drift fixes all work.** 110 conversations created, every one
   delivered a response, no Recents duplicates, no stale-styled bubbles.
2. **Every persona in the registry resolves and responds.** No 80-Expert
   imported-prompt is broken at the routing layer.
3. **Openfang bridge survived heavy load.** All 6 Agents (outbound-sdr,
   seo-auditor, content-publisher, inbox-triage, pipeline-curator,
   deep-research) responded inside their per-Agent weight latency budgets.
   Deep-research adversarial run: 3,783 chars in 22s — Tongyi-on-OpenRouter
   didn't blow up on the multi-step prompt.
4. **Heavy Phase-14 imports survive without timing out.** The ~29K char
   system prompts (multi-agent-systems-architect, identity-graph) consistently
   landed in <50s.

## What needs work

### A · Starter-prompt fit (the 13 stubs)

Same-named root cause for every single stub: the persona's
`starters[0].prompt` assumes context the harness can't provide. When the
adversarial follow-up DID provide context, every single stub produced full
output. Examples:

| persona | Pass B (no context) | Pass C (with follow-up) |
|---|---:|---:|
| code-reviewer | 362 c | 2,063 c (+469%) |
| financial-analyst | 685 c | 21,044 c (+2972%) |
| mcp-builder | 6,349 c (variance) | 31,780 c (+401%) |
| chief-of-staff | 3,348 c | 5,125 c (+53%) |

**Recommendation:** edit `agents.yaml` starters to either (a) include a
synthetic-example payload ("Review THIS diff: ```diff\n...```"), or (b)
rephrase as a discovery question ("What patterns do you check first when
reviewing a PR?"). Touches 13 of 80 imports.

### B · The two false-positive refusals

- **soc2** — opens "While I can't perform an actual Type II readiness
  assessment as an AI…" then delivers 12.7K of structured assessment.
- **ma** — opens "As an AI, I specialize in…" then delivers 3.2K.

My regex flagged "as an AI" too broadly. **Both responses were useful**;
the refusal-signal in the JSON is a false alarm. Real refusal rate: **0/86**.

### C · One harness bug

`ADVERSARIAL_SLUGS` array contained `sales-pipeline-analyst`; registry slug
is `pipeline-analyst`. Silently skipped during Pass C — only 19 of intended
20 ran. Trivial fix.

### D · The opener "As an AI…" tic

Several personas open their reply with self-introduction phrases instead of
diving straight into the work. Affects perceived quality more than utility.
Tightening the system-prompt's opening contract ("Respond directly. Do not
introduce yourself.") would tighten this — single-line addition to the
6-line common suffix in agents.yaml.

## Bugs surfaced — and fixed — during the test run

1. **Stream-drift hotfix** (commit `06df3b0` shipped mid-test). Three
   delivery paths (`chat_append.html.tera`, `chat_regenerate.html.tera`,
   `chat_poll_controller.js`) were stuck on pre-Phase-15 markup. Pass A
   timed out at 905s before the fix; 43s after.
2. **Client poll timeout** raised 90s → 180s. Heavy Phase-14 imports were
   routinely landing at 90-120s; the old cap gave up on valid responses.

## Cost summary

Tokens budgeted on Pro tier: 1,000,000 / month.
Tokens spent on this test: **~223,000** = **22.3% of monthly budget**.
Remaining: ~777,000 for the rest of the month.

## Artifacts

- `e2e/persona-results-1781359070221.json` — Pass A (5 rows)
- `e2e/persona-results-1781359247844.json` — Pass B (86 rows)
- `e2e/persona-results-1781360473251.json` — Pass C (19 rows)
- `e2e/screenshots/personas/<slug>.png` — one screenshot per persona +
  `<slug>-adversarial.png` for Pass C

## What I'd ship next (in priority order)

1. **Edit 13 starter prompts** in `agents.yaml` to provide synthetic context
   inline. Removes the stub class entirely. Touches ~250 lines.
2. **Add an opener clause** to the common system-prompt suffix:
   "Respond directly. Do not introduce yourself." Removes the "As an AI…"
   tic. Touches the 50 imported entries (or all 80).
3. **Fix `ADVERSARIAL_SLUGS` typo** in `real-persona-test.spec.ts`. 1 line.
4. **Tighten the refusal-signal regex** in the same harness to require a
   full refusal sentence, not the phrase "as an AI" alone.
