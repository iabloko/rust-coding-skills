---
name: rust-ownership
description: Reason about Rust ownership, borrowing, and lifetimes correctly — references vs owned values, the borrow-checker mental model, when clone/Rc/Arc/RefCell/Mutex is the right tool vs a crutch to silence the compiler, lifetime annotations, and smart-pointer selection. Use whenever the borrow checker complains, code reaches for .clone()/Rc/Arc/RefCell, or a signature needs a lifetime.
---

# Rust Ownership, Borrowing & Lifetimes

The borrow checker is where beginners fight the compiler and "win" by scattering `.clone()`, `Rc<RefCell<T>>`, and `.to_string()` until it compiles. That code compiles and is wrong — it hides the design problem. This skill is the mental model and the decision rules. Pair with [[rust-conventions]].

## The rules the compiler enforces

1. Every value has exactly one **owner**. When the owner goes out of scope, the value is dropped.
2. You can have **either** one mutable borrow (`&mut T`) **or** any number of shared borrows (`&T`) — never both at once. (This is what prevents data races at compile time.)
3. A borrow must not outlive the value it points to.

Almost every borrow-checker error is one of these three being violated. Read the error message — rustc's borrow-checker diagnostics name the exact rule and location. Don't reflexively `.clone()`; first understand *which* rule fired.

## Borrow first, own only when you must

The default in a function signature is to **borrow**:

- Take `&T` when you only read. Take `&mut T` when you mutate in place. Take `T` (owned) only when the function must *store* the value, *consume* it, or return it transformed.
- Parameters: `&str` over `&String`, `&[T]` over `&Vec<T>`, `&T` over `&Box<T>` — borrow the slice/trait, not the container. This accepts more callers and avoids forcing an allocation.
- Return owned (`String`, `Vec<T>`) when you produce new data; return a borrow (`&T`, `&str`) when you're lending out something you own (and can express the lifetime).

## `.clone()` — tool or crutch?

`.clone()` is legitimate. It is *also* the #1 way beginners paper over a borrow they should have restructured.

**A clone is the right call when:**
- The value is cheap to copy (`Copy` types clone for free; small `String`s, small `Vec`s are cheap enough).
- You genuinely need two independent owned copies that diverge afterward.
- The alternative is a lifetime tangle that hurts readability more than the clone costs, *and* the clone isn't in a hot path.

**A clone is a crutch (fix the borrow instead) when:**
- You cloned solely because the compiler complained about a move or an overlapping borrow — restructure the scopes, split the borrow, or return a reference instead.
- It's inside a loop or hot path (measure — see [[rust-performance]]).
- You cloned a large owned structure to read one field — borrow the field.

When you clone, be able to say *why* in one sentence. "To satisfy the borrow checker" is not a why — it's the smell. Reach for these before cloning: reorder statements so borrows don't overlap; introduce a scope `{ }` to end a borrow early; split into two functions; take the value by reference; use `std::mem::take`/`replace` to move out of a `&mut`.

## Smart pointers — pick the minimum

Reach down this list only as far as the problem forces you. Beginners jump to the bottom too fast.

| Need | Use | Notes |
|---|---|---|
| Single owner, heap allocation (recursion, large value, trait object) | `Box<T>` | Cheapest indirection. `Box<dyn Trait>` for dynamic dispatch. |
| Multiple owners, single-threaded, read-only sharing | `Rc<T>` | Reference-counted. Not `Send`. |
| Multiple owners, across threads | `Arc<T>` | Atomic refcount — pay only when you cross threads. |
| Mutate through a shared `&`, single-threaded | `RefCell<T>` | Moves borrow checking to **runtime** — panics on violation. Usually `Rc<RefCell<T>>`. |
| Mutate through a shared `&`, across threads | `Mutex<T>` / `RwLock<T>` | Usually `Arc<Mutex<T>>`. Prefer `RwLock` for read-heavy. |

- **`Rc<RefCell<T>>` and `Arc<Mutex<T>>` are not the default for shared state — they're the escape hatch.** Before reaching for them, ask: can this be a single owner that lends `&`/`&mut` borrows? Can ownership be restructured (pass the value in, return it out)? Can the graph be an arena/index instead of pointers? In a beginner's code, a reflexive `Rc<RefCell<T>>` usually means the ownership wasn't thought through — justify it or restructure.
- `RefCell` trades compile-time safety for runtime panics: a double-borrow that the borrow checker would have caught becomes a `BorrowMutError` panic at runtime. Only worth it when you *need* interior mutability and can keep the borrows short and local.
- `Arc<Mutex<T>>` shared across async tasks: hold the lock for the *shortest* possible span, and **never hold a `std::sync::Mutex` guard across an `.await`** — it can deadlock the runtime. Use `tokio::sync::Mutex` when the guard must live across an await, or (better) restructure so it doesn't.

## Lifetimes

- Most lifetimes are **elided** — you rarely annotate. Only annotate when the compiler asks, which means it genuinely can't infer how output borrows relate to input borrows.
- A lifetime annotation (`&'a T`, `struct Foo<'a>`) is a *description* of a relationship that already exists, not a knob that changes behavior. `'a` says "this reference lives at least as long as `'a`". You can't make a reference live longer by annotating it.
- A struct holding a reference (`struct Parser<'a> { input: &'a str }`) ties the struct's lifetime to the borrowed data — the struct can't outlive `input`. This is fine for short-lived views (parsers, iterators) but a burden for long-lived types; there, prefer owning the data or using an index/handle.
- `'static` means "lives for the whole program" — it's a real constraint (`Box<dyn Error + Send + Sync + 'static>`, `tokio::spawn` requires `'static` futures), not a magic "make the error go away" incantation. Don't slap `'static` on to silence a bound without understanding it forces owned/leaked data.
- When lifetimes get genuinely knotted, that's often the signal to **own the data** (clone once at the boundary, or restructure) rather than thread a lifetime through five layers. Owning at a boundary is a legitimate design choice, not a defeat.

## `Copy` vs `Clone` vs move

- `Copy` types (`u32`, `bool`, `char`, `&T`, small `Copy` structs) are duplicated implicitly on assignment — no move. Don't derive `Copy` on anything holding heap data (`String`, `Vec`) — you can't, and shouldn't want to.
- Moving is the default for non-`Copy` types: `let b = a;` moves `a` into `b`; `a` is no longer usable. This is not a bug — it's ownership transfer. If you need `a` afterward, you needed a borrow or a clone, so decide which (see above).
- `#[derive(Clone)]` just to move on — fine when clone is cheap and intended; a smell when it's there to dodge a move you could have avoided.

## Anti-patterns (flag on sight)

- `.clone()` / `.to_string()` / `.to_vec()` added only to make the borrow checker stop complaining, with no other reason.
- `Rc<RefCell<T>>` or `Arc<Mutex<T>>` reached for before simpler single-owner borrowing was tried — especially in tree/graph modeling where an arena + indices is cleaner.
- Holding a `std::sync::Mutex`/`RefCell` guard across an `.await` point.
- `&Vec<T>` / `&String` / `&Box<T>` parameters instead of `&[T]` / `&str` / `&T` (clippy's `ptr_arg`).
- `'static` bounds added to silence a lifetime error without understanding the ownership implication.
- Returning a reference to a local (`fn f() -> &str { let s = String::new(); &s }`) — the classic "does not live long enough"; return owned instead.
- Cloning a large struct to read one field.
- `.clone()` in a hot loop (measure — [[rust-performance]]).

## Verification checklist

- [ ] Every `.clone()` in the diff has a one-sentence reason that isn't "to satisfy the borrow checker".
- [ ] Function parameters borrow (`&str`/`&[T]`/`&T`) unless ownership is genuinely needed.
- [ ] Any `Rc<RefCell<T>>` / `Arc<Mutex<T>>` is justified — simpler single-owner borrowing was ruled out.
- [ ] No lock/`RefCell` guard is held across an `.await`.
- [ ] Lifetime annotations describe a real relationship, not a bolted-on `'static` to silence rustc.
- [ ] No reference is returned that outlives its owner.

## Cross-references

- [[rust-conventions]] — signature-borrowing and clone-smell rules summarized there.
- [[rust-error-handling]] — error types own their data; decide clone-vs-borrow at the error boundary.
- `rust-performance` (later) — measure clone/alloc cost before optimizing; `Arc` cloning is cheap, deep clones aren't.
- `reviewing-changes` — clone-spam and reflexive `Rc<RefCell>` fold into the code-quality pass.
- `engineering-philosophy` — Investigate-Don't-Mask: a clone to silence the compiler masks a design problem.