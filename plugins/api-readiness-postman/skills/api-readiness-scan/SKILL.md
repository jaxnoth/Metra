---
name: api-readiness-scan
description: Analyze any API for AI agent compatibility. Scans OpenAPI specs across 8 pillars (48 checks), scores agent-readiness, and provides fix recommendations. Triggers on 'Is my API agent-ready?', 'Scan my API', 'Analyze my spec'.
---

# API Readiness Scan

Evaluate OpenAPI specs for AI agent compatibility: 48 checks across 8 pillars. Answer one question: **Can an AI agent reliably use this API?**

Read [../agent-ready-apis/pillars.md](../agent-ready-apis/pillars.md) for check definitions. Load [../agent-ready-apis/SKILL.md](../agent-ready-apis/SKILL.md) for scoring rules.

## Metra boundary

- Do not route portfolio work or write iSupport tickets from this skill.
- Operator chooses which spec or repo to analyze.
- Postman MCP is optional (local file analysis works without it).

## Workflow

### Step 1: Discover the spec

**Local files (preferred for smoke test):**

- Search for `**/openapi.{json,yaml,yml}`, `**/swagger.{json,yaml,yml}`, `**/*-api.{json,yaml,yml}`
- Plugin sample: `examples/sample-openapi.yaml`

**From Postman (when MCP connected and `POSTMAN_API_KEY` set):**

- `getAllSpecs` then `getSpecDefinition` for the chosen spec

If multiple specs match, list them and ask which to analyze.

### Step 2: Run checks

For each of the 48 checks in pillars.md, record pass/fail, severity, affected endpoints, and a one-line failure detail.

Use the check IDs and severities from the readiness-analyzer framework (M1-M6, E1-E7, I1-I7, N1-N6, P1-P6, D1-D6, PF1-PF5, DC1-DC5).

### Step 3: Score

```
weight: Critical=4, High=2, Medium=1, Low=0.5
max_score = sum of all weights (65.5 for full set)
percentage = (passing weights / max_score) * 100
Agent Ready = percentage >= 70 AND zero critical failures
```

Performance checks (PF*) may be N/A without live traffic - note N/A, do not count as pass.

### Step 4: Report

Present:

1. Overall score and verdict (Agent Ready / Not Ready)
2. Pillar breakdown (percent per pillar)
3. All critical failures with endpoint list
4. Top 5 priority fixes (impact, why agents care, concrete fix, estimated points)

Tone: direct and specific. Do not flatter a low score.

### Step 5: Next steps (offer, do not auto-run)

- Fix spec issues with operator approval
- Re-scan after edits
- Push improved spec to Postman via MCP (`createSpec` / `updateSpecFile`) only when operator asks

## Smoke test (P1 local gate)

After installing this plugin locally:

1. Confirm Postman MCP shows connected (or skip MCP and use the sample file only).
2. Ask: **Scan `examples/sample-openapi.yaml` for agent readiness.**
3. Pass when the agent returns a scored report with at least one critical failure called out (sample spec is intentionally weak).
