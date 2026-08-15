# API doc site - OpenAPI discovery patterns

Use when the operator gives a **documentation site URL**, not a direct spec file.

## Direct spec URLs (use immediately)

If the URL already ends with or clearly is a spec file, fetch it:

- `openapi.json`, `openapi.yaml`, `openapi.yml`
- `swagger.json`, `swagger.yaml`
- `api-docs`, `v1/swagger.json`, `v2/openapi.json`
- `openapi/v3/api-docs` (Spring Boot)
- `swagger/v1/swagger.json` (.NET Swashbuckle)

## Common paths to try (same origin as doc site)

Append or probe relative to the doc site origin:

| Pattern | Typical stack |
|---------|----------------|
| `/openapi.json` | Generic |
| `/openapi.yaml` | Generic |
| `/swagger/v1/swagger.json` | ASP.NET |
| `/swagger/doc.json` | Legacy Swagger |
| `/v3/api-docs` | Spring Boot 3 |
| `/v2/api-docs` | Spring Boot 2 |
| `/api/openapi.json` | Custom |
| `/docs/openapi.json` | Custom |
| `/.well-known/openapi.json` | Emerging convention |

## HTML doc UIs (parse the page)

When the URL is a human doc site (Swagger UI, Redoc, Stoplight, ReadMe, etc.):

1. Fetch the HTML (browser or HTTP GET).
2. Search for:
   - `url: "` or `url:"` pointing to `.json` / `.yaml`
   - `spec-url`, `data-url`, `openapi`, `swagger`
   - `<link rel="openapi">` or embedded `swagger-ui` config
   - Redoc: `spec-url=` query param on script tag
3. Resolve relative URLs against the doc page origin.
4. Prefer OpenAPI 3.x over Swagger 2.0 when both exist.

## Auth and access walls

- **Public docs:** fetch spec directly after discovery.
- **Login / SSO:** stop and ask the operator for a direct spec URL or exported file path.
- **API key on spec endpoint:** ask operator for header or a downloaded copy in the repo.

Do not bypass login walls or scrape credentials.

## After discovery

1. Save a copy under the project when appropriate (e.g. `postman/specs/openapi.yaml`) - ask first.
2. Continue with **postman-setup-from-docs** Step 3 (readiness optional) and Step 4 (Postman writes).

## Fail closed

If no machine-readable spec is found:

- Report what was tried.
- Ask for: direct OpenAPI URL, exported YAML/JSON path, or vendor export (Stoplight, etc.).
- Do not invent endpoints from HTML prose alone.
