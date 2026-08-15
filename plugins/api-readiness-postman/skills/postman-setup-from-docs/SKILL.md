---
name: postman-setup-from-docs
description: Scan an API documentation site, discover its OpenAPI spec, and create or update Postman spec, collection, and environment. Triggers on 'set up Postman from this API docs', 'import API docs to Postman', 'fill out Postman from doc site', 'bootstrap Postman from OpenAPI URL'.
---

# Postman setup from API docs

Goal: operator gives an **API documentation site URL** (or direct OpenAPI URL). You discover the spec, optionally score it, then **fill out Postman** - Spec Hub entry, collection with folders/requests, and environment - for documentation and testing. This is **not** a runtime API pass-through; Postman is the catalog and test harness.

Requires **Postman MCP** connected (`POSTMAN_API_KEY` set) and **minimal** toolset or better.

## Metra boundary

- Do not route portfolio work or write iSupport tickets.
- Operator names target **Postman workspace** (or confirm default).
- **Confirm before any Postman write** unless operator explicitly said `-Yes` / "go ahead without prompts".

## Prerequisites check

1. Call `getAuthenticatedUser` - fail closed with setup instructions if 401.
2. Call `getWorkspaces` - list workspaces; ask which to use if unclear.
3. Confirm doc site URL and environment name (default: `{API title} - Dev`).

## Workflow

### Step 1: Resolve the OpenAPI spec

**If input is already a spec file path or `.json`/`.yaml` URL:** fetch or read it.

**If input is a doc site URL:** follow [doc-site-patterns.md](doc-site-patterns.md):

- Try common spec paths on the same origin.
- Parse Swagger UI / Redoc / Stoplight HTML for embedded spec URL.
- Fetch the resolved spec; validate it parses as OpenAPI 2.x or 3.x.

Record: spec URL, OpenAPI version, title, version, server URLs, security schemes, path count.

If discovery fails, stop with tried paths and ask for a direct spec URL or file.

### Step 2: Normalize (when needed)

- OpenAPI **2.0 (Swagger):** note that `syncCollectionWithSpec` needs 3.0; prefer `generateCollection` from spec or decomposed collection build. Optionally convert 2.0 to 3.0 locally only if operator asks.
- Large specs (**>50KB**): avoid single-shot `createSpec`; use decomposed collection build (Step 4B) and/or local file + `updateSpecFile` in chunks.
- Save a project copy only when operator wants repo tracking (e.g. `postman/specs/openapi.yaml`).

### Step 3: Optional readiness scan

If operator wants quality feedback first, run **api-readiness-scan** on the spec. Summarize score and critical gaps. Offer to fix spec locally before Postman push.

### Step 4: Postman setup (operator confirmed)

Target artifacts:

| Artifact | Purpose |
|----------|---------|
| **Spec** (Spec Hub) | Source of truth in Postman |
| **Collection** | Documented requests grouped by tags |
| **Environment** | `baseUrl`, auth secrets, common variables |

**4A - Spec already clean and <=50KB (preferred when supported)**

1. `getAllSpecs` - check for existing spec by title; ask update vs create.
2. `createSpec` or `updateSpecFile` with spec content.
3. `generateCollection` from spec (returns **HTTP 202** - async).
4. Poll `getGeneratedCollectionSpecs` every 2-3s, timeout 60s.
5. `createEnvironment` with:
   - `baseUrl` from `servers[0].url` (strip trailing slash)
   - Auth vars from `components.securitySchemes` (mark secrets as `secret` type)
   - Placeholder values; operator fills real tokens in Postman UI

**4B - Large spec, nested folders, or async failures (decomposed)**

From Postman MCP limitations - required when `createCollection` cannot nest in one call:

1. Parse spec: tags, paths, methods, parameters, request bodies, response schemas.
2. `createCollection` - shell with name, description, one placeholder request, collection variable `baseUrl`.
3. `createCollectionFolder` per tag/resource (parallelize).
4. `createCollectionRequest` per endpoint (batches of 25-30):
   - Method + `{{baseUrl}}/path` with path params
   - Headers (`Content-Type: application/json` on body methods)
   - Bodies from schema when present
   - Query params from spec
5. `createCollectionResponse` for documented examples when spec includes them.
6. `createEnvironment` as in 4A.
7. Optionally `createSpec` if size allows, for Spec Hub parity.

**4C - Update existing collection**

1. `getCollections` / `searchPostmanElements` - match by API title.
2. `getCollection` with **full** model.
3. `updateSpecFile` + `syncCollectionWithSpec` (OpenAPI 3.0 only, async - poll `getCollectionUpdatesTasks`).

### Step 5: Testing hook (documentation + test use case)

After collection exists:

- Summarize request count, folders, environment variables.
- Offer `runCollection` smoke run if operator provides a runnable `baseUrl` and auth (or a dedicated test environment).
- Do **not** run destructive requests (DELETE production, etc.) without explicit operator approval.

### Step 6: Handoff report

```
Postman setup complete

Workspace:   {name}
Spec:        {title} ({created|updated})
Collection:  {name} ({N} requests, {M} folders)
Environment: {name} (baseUrl + {K} variables)

Doc source:  {original URL}
Spec:        {resolved spec URL or file path}

Next:
- Open collection in Postman; fill secret env vars
- Run collection tests (/postman:test or runCollection)
- Re-scan readiness after spec improvements
```

## Error handling

| Situation | Action |
|-----------|--------|
| Doc site has no OpenAPI | Fail closed; ask for spec URL or export |
| 401 on Postman | Regenerate API key; check User env var |
| Async task timeout | Tell operator to check Postman web UI; offer 4B decomposed path |
| OpenAPI 2.0 only | Use generateCollection or 4B; do not claim syncCollectionWithSpec works |
| Operator skipped MCP | Stop at local spec save + readiness scan only |

## Hard offs

- No inventing endpoints from marketing HTML without a spec
- No auto-run against production without confirm
- No Metra routing or ticket writes
- No Full `/mcp` toolset required - **minimal** MCP is enough for this workflow

## Related skills

- [agent-ready-apis](../agent-ready-apis/SKILL.md) - scoring vocabulary
- [api-readiness-scan](../api-readiness-scan/SKILL.md) - pre-push quality gate
