---
name: rust-observability
description: Instrument Rust services with tracing — structured logging over println!, spans for request context, #[instrument], log levels, metrics, and OpenTelemetry export. Use whenever adding logging, diagnosing a production issue, or wiring observability into a service. Opinionated default: the tracing crate ecosystem.
---

# Rust Observability (tracing)

A service you can't see into is a service you can't operate. The house observability stack is the **`tracing`** ecosystem (`tracing` + `tracing-subscriber`, `metrics` for metrics, OpenTelemetry for export). Beginners under-instrument — this skill sets the baseline. Pair with [[rust-web]], [[rust-async]], and [[rust-error-handling]].

## Structured logging over `println!`

- **Never `println!`/`eprintln!`/`dbg!` for production logging.** Use `tracing`'s macros: `tracing::info!`, `warn!`, `error!`, `debug!`, `trace!`. They carry structured fields, respect levels, and route through a subscriber you configure once.
- **Log structured fields, not interpolated strings.** `tracing::info!(user_id = %id, order_id = %oid, "order placed")` — the fields are queryable/filterable in a log aggregator; a `format!("order {oid} for {id}")` string is not.
  - `%value` = log via `Display`, `?value` = log via `Debug`, bare `value` = the field's typed value.
- Initialize a subscriber **once** at startup (`tracing_subscriber::fmt()` for dev, JSON output for prod), with an `EnvFilter` so levels are env-controlled (`RUST_LOG=info,my_app=debug`). Don't hardcode the level.

## Levels — use them deliberately

- `error!` — something failed that needs attention (a request errored, a dependency is down). Pair with returning the error, don't just log-and-swallow ([[rust-error-handling]] "Investigate, Don't Mask").
- `warn!` — recoverable/degraded (a retry, a fallback taken, approaching a limit).
- `info!` — significant business events (request handled, job completed) — the default operational signal.
- `debug!`/`trace!` — developer detail, off in production by default.
- Don't log at `info` inside a hot loop (log spam + cost) — guard or lower the level ([[rust-performance]]).

## Spans give context

A **span** attaches context to everything logged within it — the killer feature over flat logs. A request span carries the request id / user id, and every log line inside inherits those fields automatically.

- `#[tracing::instrument]` on a function creates a span for each call, auto-recording the arguments as fields:
  ```rust
  #[tracing::instrument(skip(db), fields(user_id = %cmd.user_id))]
  async fn register(db: &PgPool, cmd: Register) -> Result<UserId, ServiceError> { ... }
  ```
- **`skip` big/sensitive/non-`Debug` args** (`skip(db)`, `skip(password)`) — don't record a whole DB pool or a secret as a span field ([[rust-security]] — secrets in logs is a leak).
- Spans work **across `.await`** — tracing is async-aware, so a span correctly follows a task through suspension points ([[rust-async]]). This is why it beats thread-local logging in async code.
- In [[rust-web]], add `tower_http::trace::TraceLayer` as the outermost layer so every request gets a span with method/path/status/latency, and generate/propagate a request id.

## Errors and observability

- Log the *full* error chain server-side at the boundary (`tracing::error!(error = ?e, "…")` captures the `anyhow`/`thiserror` source chain via `Debug`), while returning a generic message to the client ([[rust-web]], [[rust-security]]).
- Don't double-log: log an error once, where it's handled, not at every `?` on the way up.

## Metrics

- For counters/gauges/histograms (request rate, error rate, latency percentiles, queue depth), use the `metrics` facade (`metrics::counter!`, `histogram!`) with an exporter (Prometheus via `metrics-exporter-prometheus`), or the OpenTelemetry metrics API.
- The RED method for a service: **R**ate, **E**rrors, **D**uration per endpoint — instrument those first.
- Metrics are aggregates (cheap, always-on); traces/logs are per-event (richer, sampled in high volume). Use both.

## OpenTelemetry export

- For distributed tracing across services, bridge tracing to OpenTelemetry (`tracing-opentelemetry` + an OTLP exporter) so spans propagate across service boundaries with a shared trace id.
- Propagate the trace context on outbound HTTP/gRPC calls (inject headers) so a request is traceable end-to-end.

## Anti-patterns (flag on sight)

- `println!`/`eprintln!`/`dbg!` used for logging in shipping code.
- String-interpolated log messages instead of structured fields.
- No span/request context — flat logs you can't correlate to a request.
- A secret, password, token, or a whole DB pool / large struct recorded as a span/log field (`#[instrument]` without `skip`).
- Logging at `info`+ inside a hot loop (spam + cost).
- Log-and-swallow: `error!(...)` then dropping the error instead of propagating ([[rust-error-handling]]).
- Double-logging the same error at every layer.
- Hardcoded log level instead of `EnvFilter`/`RUST_LOG`.
- No metrics on request rate/errors/latency for a service that has an SLA.

## Verification checklist

- [ ] No `println!`/`dbg!` for logging; `tracing` macros used with structured fields.
- [ ] Subscriber initialized once at startup with an env-controlled `EnvFilter`.
- [ ] Requests/handlers carry a span (request id, key context); `#[instrument]` skips big/secret args.
- [ ] No secrets or large values recorded as log/span fields.
- [ ] Errors logged once at the boundary with the full chain; generic message to the client.
- [ ] Hot paths don't log at `info`+ unguarded.
- [ ] Service exposes RED metrics (rate/errors/duration) if it has operational requirements.

## Cross-references

- [[rust-web]] — `TraceLayer` request spans, request-id propagation, log-not-leak on errors.
- [[rust-async]] — tracing spans are async-aware and follow tasks across `.await`.
- [[rust-error-handling]] — log the error chain once at the boundary; don't log-and-swallow.
- [[rust-security]] — never record secrets/tokens as log or span fields.
- [[rust-performance]] — don't log in hot loops; metrics are cheap aggregates, traces are sampled.