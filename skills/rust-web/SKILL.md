---
name: rust-web
description: "Build HTTP services with axum — routing, extractors, State, error-to-response mapping, tower middleware, request validation, JSON with serde, and keeping handlers thin over a testable service layer. Use whenever adding an endpoint, handler, middleware, or wiring an axum app. Opinionated default web stack: axum + tower + serde + tokio."
---

# Rust Web (axum)

The house web framework is **axum** (on `tokio` + `tower`). This skill is the idioms for building an HTTP service correctly. Pair with [[rust-async]] (runtime rules), [[rust-error-handling]] (error types), [[rust-architecture]] (layering), and [[rust-security]] (input/authz).

## Detect first

- `Cargo.toml` → confirm `axum` (and its version — the extractor/`Router` API shifted across 0.6→0.7→0.8). If the project is on `actix-web`/`warp`/`rocket` instead, follow *that* framework — don't rewrite to axum. Check `tower`, `tower-http`, `serde`, `validator`.

## The shape: thin handler over a service

The single most important rule: **handlers are glue, not logic.** A handler extracts inputs, calls a plain service function, and maps the result to a response. Business logic lives in framework-free functions so it's unit-testable without spinning an HTTP server ([[rust-architecture]], [[rust-testing]]).

```rust
async fn create_user(
    State(state): State<AppState>,
    Json(body): Json<CreateUser>,       // extractor: deserialize + validate
) -> Result<(StatusCode, Json<UserView>), AppError> {
    let user = state.users.register(body.into_command()).await?;  // service does the work
    Ok((StatusCode::CREATED, Json(user.into())))
}
```

A handler with a DB query, business rules, and validation inline is the "does five things" smell ([[rust-conventions]]) — extract the service.

## Routing

- Build a `Router`, attach handlers per method (`get`, `post`, …), nest sub-routers with `Router::nest`, share cross-cutting behavior with `.layer(...)`.
- Group routes by resource into their own `Router`-returning functions (`fn user_routes() -> Router<AppState>`) and `nest` them — don't build one 300-line router.
- Path params via typed extractors (`Path<Uuid>`), not string parsing.

## Extractors

Extractors run in argument order and pull typed data out of the request:

- `Path<T>` (URL segments), `Query<T>` (query string), `Json<T>` (JSON body), `State<S>` (shared state), `Extension<T>`, typed headers via `TypedHeader`.
- **Order matters:** a body-consuming extractor (`Json`, `Form`, `Bytes`) must be **last** — it takes ownership of the request body; anything after it won't compile.
- Deserialization failures return 4xx automatically, but the default message is terse — for good errors, validate explicitly (below).
- Write a custom extractor (`impl FromRequestParts`) for cross-cutting concerns like an authenticated `CurrentUser` — do the auth once, inject the typed principal, and every handler that needs auth just takes `CurrentUser` as a parameter.

## Shared state

- `State<AppState>` is the idiomatic way to inject dependencies (DB pool, config, service handles). `AppState` is typically `#[derive(Clone)]` and holds `Arc`-wrapped or already-cheap-to-clone things (a `sqlx::Pool` is already an `Arc` inside — clone it freely).
- Clone the `Arc`/pool, never the underlying data ([[rust-ownership]]). Don't reach for `Extension` for app-wide deps when `State` is typed and checked at compile time.
- Assemble `AppState` once in the composition root (`fn build_app(cfg) -> Router`), inject the concrete repos/services ([[rust-architecture]]).

## Errors → responses (one place decides status)

Define an app error and **one** `IntoResponse` impl that maps each variant to a status + body. Then handlers just `?` and the mapping is automatic and consistent.

```rust
pub enum AppError {
    NotFound,
    Validation(String),
    Unauthorized,
    Internal(anyhow::Error),   // catch-all; log it, return 500 with no detail
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, msg) = match self {
            AppError::NotFound      => (StatusCode::NOT_FOUND, "not found".into()),
            AppError::Validation(m) => (StatusCode::BAD_REQUEST, m),
            AppError::Unauthorized  => (StatusCode::UNAUTHORIZED, "unauthorized".into()),
            AppError::Internal(e)   => {
                tracing::error!(error = ?e, "internal error");   // log the detail
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".into())  // don't leak it
            }
        };
        (status, Json(json!({ "error": msg }))).into_response()
    }
}
```

- Implement `From<ServiceError> for AppError` (and `From<sqlx::Error>` etc.) so `?` converts at the boundary ([[rust-error-handling]]).
- **Never leak internal error detail to the client** — log it server-side, return a generic message. A DB error string in a 500 body is an info leak ([[rust-security]]).

## Middleware (tower / tower-http)

- Cross-cutting behavior is a `tower` layer applied with `.layer(...)`: `TraceLayer` (request logging — see [[rust-observability]]), `TimeoutLayer`, `CorsLayer`, `CompressionLayer`, `RequestBodyLimitLayer`, a custom auth layer.
- **Layer ordering wraps outermost-first** — the last `.layer()` added is the outermost. Put tracing outermost so it sees everything; put auth so it actually wraps the protected routes ([[rust-security]] — a misordered auth layer that doesn't cover the routes is a Critical hole).
- Prefer existing `tower-http` layers over hand-rolling middleware.

## Request validation

- `serde` gives you a well-typed value, not a *valid* one. Validate domain rules after deserializing — with the `validator` crate (`#[derive(Validate)]` + `body.validate()?`) or by parsing into newtypes with validating constructors ([[rust-architecture]] "parse, don't validate").
- Bound the body size (`RequestBodyLimitLayer` or `DefaultBodyLimit`) — unbounded bodies are a memory-DoS ([[rust-security]]).
- Return 422/400 with a useful message on validation failure, not a panic.

## Don't block the runtime

Handlers run on the tokio runtime — every [[rust-async]] rule applies: no blocking I/O, no `std::fs`, no CPU-heavy work inline (`spawn_blocking`), no lock held across `.await`, timeouts on outbound calls.

## Testing

- Test the **service layer** directly — plain async functions, no HTTP (fast, most of your coverage).
- For handler/routing/middleware behavior, drive the `Router` in-process: build the app, send a `Request` via `tower::ServiceExt::oneshot`, assert on the `Response` — no real socket needed. Use `#[tokio::test]`.
- End-to-end against a real server only for a few smoke tests. See [[rust-testing]].

## Anti-patterns (flag on sight)

- Business logic, DB queries, or validation inline in the handler instead of a service function.
- A body-consuming extractor not last in the argument list.
- Cloning the underlying state instead of the `Arc`/pool.
- No unified `IntoResponse` error mapping — each handler hand-rolls status codes (inconsistent, duplicated).
- Internal error detail (DB messages, `anyhow` chains) leaked into the response body.
- Auth done per-handler ad hoc instead of a custom extractor / layer; a middleware layer ordered so it doesn't actually wrap protected routes.
- No body-size limit, no request timeout.
- Blocking work in a handler; a lock held across `.await`.
- `.unwrap()` on an extractor/parse result on the request path (panic-as-DoS — [[rust-security]]).

## Verification checklist

- [ ] Handler is thin: extract → call service → map result; no business logic inline.
- [ ] One `IntoResponse` maps app errors to statuses; `?` converts via `From` at the boundary.
- [ ] No internal error detail leaks to the client; 500s are logged server-side.
- [ ] Body-consuming extractor is last; inputs validated after deserialization.
- [ ] Body-size limit and request timeout layers present; auth layer actually wraps protected routes.
- [ ] State injected via typed `State<_>`; only `Arc`/pool cloned.
- [ ] No blocking/`.await`-held-lock in handlers; service layer unit-tested without HTTP.

## Cross-references

- [[rust-async]] — the runtime rules every handler obeys (no blocking, timeouts, bounded concurrency).
- [[rust-error-handling]] — the app error type behind `IntoResponse`; `thiserror` per layer, `anyhow` catch-all.
- [[rust-architecture]] — thin handler over injected services; composition root builds the `Router`.
- [[rust-database]] — the `sqlx::Pool` in `AppState`; transactions in the service layer.
- [[rust-security]] — input validation, body limits, authz layer ordering, no error-detail leaks.
- [[rust-observability]] — `TraceLayer`, request spans, structured error logging.