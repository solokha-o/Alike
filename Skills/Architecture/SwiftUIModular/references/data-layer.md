# Data Layer, Errors, and Observability

Moved from `SKILL.md` to keep it a thin router. The current Alike way for each
task is in [file-structure.md](file-structure.md) "One way per task"; where this
file is more general, that table wins.

## Data layer & dependencies

- Use a `Repository` or `Client` protocol per domain to isolate data access.
- Alike has no networking package. Persistence lives in `Storage`; photo analysis lives in `PhotoAnalysis`.
- Cache policies (memory/disk) live behind repositories; keep UI unaware of cache details.
- Use DTOs at the network boundary and map to domain models in the data layer.
- Prefer immutable domain models; store mutability in caches/repositories.

## Offline-first & caching guidelines

- Treat cache as the primary read source; network is for refresh.
- Flow: `load cache → show UI → refresh in background → update cache → UI updates`.
- Expose cache age or freshness so UI can show "last updated".
- Use write-through: on successful network fetch, update cache immediately.
- Support a manual refresh path even when cache is available.
- Choose cache policy per feature (stale-while-revalidate, time-based expiry, or size-based eviction).
- If offline, return cached data with an explicit "stale" marker; avoid empty screens.

## Error handling & resiliency

- Model domain errors explicitly; avoid pinpointing UI to raw network errors.
- Handle transient failures with retry/backoff at the data layer.
- Provide user-friendly error states at the view level (empty, loading, error).

## Observability (non-CI)

- Add lightweight logging in data/repository layers for request/response failures.
- Use analytics/telemetry behind a protocol so it can be mocked in tests.
