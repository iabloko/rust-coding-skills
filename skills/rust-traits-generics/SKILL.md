---
name: rust-traits-generics
description: Reason about Rust traits and generics correctly — defining and implementing traits, the common std traits worth knowing (Debug/Display/From/Into/Iterator/Default/Ord/Hash), generic bounds and where-clauses, static (generic) vs dynamic (`dyn`) dispatch, `impl Trait`, associated types, the orphan rule and the newtype workaround, and reading "trait bound not satisfied" errors. Use whenever defining a trait, writing generic code, choosing generics vs `dyn`, or fighting a trait-bound error.
---

# Rust Traits & Generics

Traits are Rust's interfaces — shared behavior a type can implement. Generics are code parameterized over types, constrained by trait *bounds*. Together they're how Rust does polymorphism without inheritance, and they're the second wall a newcomer hits after the borrow checker. The rule: **reach for the simplest tool that fits** — a concrete function first, a generic when you truly have many types, a trait when behavior is genuinely shared. Pair with [[rust-architecture]] (traits for dependency inversion), [[rust-ownership]] (bounds interact with borrowing), and [[rust-conventions]] (which traits to derive).

## Traits: define and implement

```rust
trait Summarize {
    fn summary(&self) -> String;          // required — implementor must provide

    fn preview(&self) -> String {          // default method — override optional
        format!("{}…", &self.summary()[..10.min(self.summary().len())])
    }
}

impl Summarize for Article {
    fn summary(&self) -> String { format!("{} by {}", self.title, self.author) }
}
```

- A trait declares behavior; `impl Trait for Type` provides it. Default methods give shared behavior for free.
- Call trait methods only where the trait is **in scope** — a missing `use some_crate::SomeTrait;` is the usual "method not found" cause for a method you *know* exists.

## Know the standard traits

Most day-to-day trait work is with std traits. Derive the obvious ones ([[rust-conventions]]); implement the rest deliberately:

- **`Debug`** — `{:?}` formatting. Derive on nearly everything. **`Display`** — `{}` user-facing text; implement by hand (no derive).
- **`Clone` / `Copy`** — duplicate. Derive `Clone` widely; `Copy` only for small, cheap, value-like types (never on something owning a heap allocation) — see [[rust-ownership]].
- **`PartialEq`/`Eq`, `PartialOrd`/`Ord`, `Hash`** — equality, ordering, hashing. `Eq`+`Hash` are needed to be a `HashMap`/`HashSet` key; `Ord` to be a `BTreeMap` key or to `sort()`.
- **`Default`** — a zero-arg `T::default()`; derive when every field has a sensible default.
- **`From<T>` / `Into<T>`** — infallible conversion. Implement `From`; you get `Into` for free, plus `?`/`.into()` ergonomics ([[rust-error-handling]] uses this via `#[from]`). Use **`TryFrom`/`TryInto`** when the conversion can fail.
- **`Iterator` / `IntoIterator`** — see [[rust-iterators-closures]].
- **`Deref`** — treat a wrapper like its inner type. Powerful but easy to abuse: use it for smart pointers, **not** to fake inheritance. A `Deref` that hides real behavior is a smell.
- **`Drop`** — custom cleanup at end of scope (RAII). You rarely implement it; you can't call it manually (use `drop(x)`).

## Generics and bounds

A generic function works for any type that satisfies its bounds:

```rust
fn largest<T: PartialOrd>(items: &[T]) -> Option<&T> {
    items.iter().max_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
}

// Multiple/complex bounds read better as a where-clause:
fn print_all<T>(items: &[T]) where T: std::fmt::Display { /* ... */ }
```

- **A bound is a promise**: `<T: Display>` means "T can be formatted", so inside the function you may only use what `Display` provides. That's why the compiler rejects operations the bound doesn't guarantee.
- Prefer `impl Trait` in **argument** position for simple single-use bounds: `fn f(x: impl Display)` is sugar for `fn f<T: Display>(x: T)`.
- Don't over-generify. A function used with exactly one concrete type should take that type ([[engineering-philosophy]], YAGNI). Generics earn their keep with real reuse.

## Static vs dynamic dispatch — the key choice

Two ways to be polymorphic; pick deliberately (this decision also lives in [[rust-architecture]] and [[rust-performance]]):

- **Generics / `impl Trait` = static dispatch.** The compiler monomorphizes one specialized copy per concrete type. Zero runtime cost, inlinable — but no heterogeneous collections and larger code.
- **`dyn Trait` = dynamic dispatch (trait objects).** `Box<dyn Summarize>`, `&dyn Summarize`. One vtable indirection at runtime, blocks inlining — but lets you store *different* implementors together (`Vec<Box<dyn Summarize>>`) and keeps code small.

Rule of thumb: **generics at hot leaves and in libraries; `dyn` at cold seams and when you need a heterogeneous collection or to break a compile-time dependency.** You can't make a trait object out of every trait — only **object-safe** ones (no generic methods, no `Self`-by-value returns); that's why some `dyn` uses won't compile.

## `impl Trait` in return position

`fn make() -> impl Iterator<Item = u32>` means "returns *some* concrete iterator I won't name" — used to return closures/iterators whose type is unnameable. If callers need to store it in a struct field or you need several different return types, return `Box<dyn Trait>` instead.

## Associated types vs generic parameters

`trait Iterator { type Item; ... }` uses an **associated type** — one `Item` per implementor. Use an associated type when there's exactly one natural choice per type (an iterator yields one item type); use a generic trait parameter (`trait From<T>`) when a type can implement the trait many ways (`From<u8>`, `From<u16>`, …).

## The orphan rule (and the newtype escape)

You may `impl Trait for Type` only if **you own the trait or you own the type** (coherence). So you can't `impl Display for Vec<T>` — both are foreign. Wrap it: `struct MyVec(Vec<T>)` and impl on the newtype. This is the standard workaround, and newtypes also make illegal states unrepresentable ([[rust-architecture]]).

## Reading "the trait bound X is not satisfied"

The single most common beginner error. Read it literally: some code requires `T: SomeTrait`, and the `T` you passed doesn't implement it. Usual fixes, in order: (1) add the missing bound to your generic, (2) `#[derive(...)]` or implement the trait for your type, (3) `use` the trait so its methods are in scope, (4) you passed an owned value where a reference (or vice-versa) was bound. Don't paper over it with `.clone()` — understand which bound is missing ([[rust-ownership]]).

## Anti-patterns (flag on sight)

- Generic code with exactly one concrete caller — a plain function is simpler ([[engineering-philosophy]]).
- `dyn` in a hot inner loop where a generic would be zero-cost, or generics bloating a cold seam where `dyn` would keep it small ([[rust-performance]]).
- `impl Deref` used to simulate inheritance / expose inner methods as if they were the wrapper's own.
- Deriving `Copy` on a type that owns heap data, or `Clone`-ing to dodge a borrow error instead of fixing the borrow ([[rust-ownership]]).
- Hand-writing a conversion as `fn to_foo(...)` instead of `impl From`/`TryFrom`, losing `?`/`.into()`.
- A giant `where` block on a function that should just take a concrete type.
- Silencing "trait bound not satisfied" with `.clone()`/`.to_owned()` rather than adding the right bound or `impl`.

## Verification checklist

- [ ] Generics used only where there's real multi-type reuse; single-type code stays concrete.
- [ ] Dispatch chosen deliberately: generics/`impl Trait` for zero-cost leaves, `dyn` for heterogeneous collections / cold seams.
- [ ] Standard traits derived where obvious (`Debug`, `Clone`, `PartialEq`, …); `Display`/`From`/`TryFrom` implemented where they belong.
- [ ] Conversions go through `From`/`TryFrom`, not ad-hoc functions.
- [ ] Foreign-trait-on-foreign-type solved with a newtype, not fought.
- [ ] Trait-bound errors fixed by the right bound/`impl`/`use`, not masked with `.clone()`.
- [ ] No `Deref` abuse to fake inheritance.

## Cross-references

- [[rust-architecture]] — traits for dependency inversion (repository pattern), static vs dynamic dispatch at seams, newtypes for illegal-states-unrepresentable.
- [[rust-ownership]] — bounds interact with borrowing; `Clone`/`Copy` semantics; don't clone to satisfy a bound.
- [[rust-conventions]] — which traits to derive; `impl Trait` guidance; naming conversions (`as_`/`to_`/`into_`).
- [[rust-iterators-closures]] — `Iterator`/`IntoIterator` and the `Fn` trait family in depth.
- [[rust-performance]] — monomorphization (zero-cost) vs vtable indirection; when each matters.
- [[rust-error-handling]] — `From` powers `?` error conversion via `#[from]`.
- `engineering-philosophy` — YAGNI: don't generify or add a trait for a single concrete case.