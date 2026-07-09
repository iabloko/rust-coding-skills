---
name: rust-iterators-closures
description: Write idiomatic Rust with iterators and closures instead of C-style index loops — the `Fn`/`FnMut`/`FnOnce` closure traits and capture (by ref vs `move`), lazy iterator adapters (`map`/`filter`/`filter_map`/`flat_map`/`enumerate`/`zip`) vs consumers (`collect`/`fold`/`sum`/`find`/`any`), `collect` into the right type (incl. `Result`/`Option` short-circuit), `iter`/`iter_mut`/`into_iter` ownership, and writing a custom `Iterator`. Use whenever transforming a collection, writing a loop, or passing a callback.
---

# Rust Iterators & Closures

Idiomatic Rust transforms data with **iterator chains**, not index loops — it's clearer, avoids off-by-one and bounds panics, and is zero-cost (the compiler optimizes a chain down to the same machine code as a hand loop). Closures are the anonymous functions those chains run. This is the shift from "C written in Rust" to Rust. But **readability wins**: a chain that's harder to read than a plain `for` loop is the wrong call. Pair with [[rust-conventions]] (iterators over index loops), [[rust-ownership]] (what a chain borrows vs consumes), and [[rust-performance]] (zero-cost, but don't allocate intermediates).

## Closures and the `Fn` traits

A closure captures variables from its surrounding scope. Which trait it implements depends on *how* it uses them:

- **`Fn`** — captures by shared reference (`&`); callable many times, reads only.
- **`FnMut`** — captures by mutable reference (`&mut`); callable many times, mutates.
- **`FnOnce`** — consumes captures; callable once (e.g. moves a value out).

```rust
let factor = 3;
let scale = |x: i32| x * factor;   // Fn: borrows `factor`
nums.iter().map(scale);

let data = vec![1, 2, 3];
let consume = move || data.len();  // `move`: takes ownership of `data`
```

- **`move`** forces the closure to *own* its captures — required when the closure outlives the current scope (spawned tasks/threads — see [[rust-async]]) or is returned.
- **Accept a closure** with a generic bound: `fn apply<F: Fn(i32) -> i32>(f: F)`, or `f: impl Fn(i32) -> i32`. **Return** one as `impl Fn(...) -> ...` (or `Box<dyn Fn...>` when the type must be named/stored). See [[rust-traits-generics]].
- Prefer the least-restrictive bound the caller needs: `FnOnce` > `FnMut` > `Fn` in permissiveness for the caller.

## Iterators are lazy

An iterator produces items one at a time via `.next()`. **Adapters** (which return another iterator) do *nothing* until a **consumer** drives them:

```rust
let evens_doubled: Vec<i32> = nums.iter()
    .filter(|&&n| n % 2 == 0)   // adapter — lazy
    .map(|&n| n * 2)            // adapter — lazy
    .collect();                // consumer — runs the whole chain
```

The #1 beginner surprise: `v.iter().map(|x| do_side_effect(x));` **runs nothing** — no consumer. Use `for_each`, `collect`, or a plain `for` loop for side effects.

## The adapters worth knowing

- **`map`** — transform each item. **`filter`** — keep items matching a predicate.
- **`filter_map`** — map returning `Option`, keeping the `Some`s (map+filter in one). **`flat_map`** — map to iterators and flatten.
- **`enumerate`** — pair each item with its index (`(i, item)`) — the idiomatic replacement for `for i in 0..len`.
- **`zip`** — pair two iterators; **`chain`** — concatenate; **`rev`** — reverse; **`take`/`skip`/`take_while`/`skip_while`** — slice; **`cloned`/`copied`** — `&T` → `T`; **`inspect`** — peek for debugging without changing items; **`peekable`** — look ahead.

## The consumers worth knowing

- **`collect`** — gather into a collection (see below). **`for_each`** — run a side effect per item.
- **`sum` / `product` / `count`** — reduce to a number. **`min` / `max` / `min_by_key` / `max_by_key`** — extremes.
- **`fold`** — accumulate with a custom function and seed. **`reduce`** — like fold but seeds from the first item.
- **`find` / `position`** — first match / its index. **`any` / `all`** — boolean quantifiers (short-circuit).
- `find`/`any`/`all`/`take` are **lazy consumers**: they stop early, so chaining them over a huge or infinite iterator is fine.

## `collect` into the right type

`collect` is type-directed — annotate the target:

```rust
let v: Vec<_>            = it.collect();
let set: HashSet<_>      = it.collect();
let map: HashMap<_, _>   = pairs.collect();     // iterator of (k, v)
let s: String            = chars.collect();
```

- **Short-circuit on failure:** `iter.collect::<Result<Vec<_>, _>>()` turns an iterator of `Result`s into `Result<Vec<_>, E>` — stops at the first `Err`. Same with `Option`. This is the idiomatic "do all or fail" ([[rust-error-handling]]).
- Collect **once** at the end; don't `collect` into a `Vec` mid-chain just to keep iterating ([[rust-performance]]).

## Ownership: `iter` vs `iter_mut` vs `into_iter`

Which one decides what the chain can do (see [[rust-ownership]]):

- **`.iter()`** yields `&T` — read the collection, keep it.
- **`.iter_mut()`** yields `&mut T` — mutate in place, keep it.
- **`.into_iter()`** yields `T` — consume the collection, move items out. (A bare `for x in vec` uses `into_iter` and moves the vec; `for x in &vec` uses `iter`.)

Picking `into_iter` when you still need the collection afterward is a common borrow-checker mistake.

## Writing a custom iterator

Implement `Iterator` by defining `Item` and `next`; you get all the adapters for free ([[rust-traits-generics]]):

```rust
struct Counter { n: u32 }
impl Iterator for Counter {
    type Item = u32;
    fn next(&mut self) -> Option<u32> {
        if self.n < 5 { self.n += 1; Some(self.n) } else { None }
    }
}
```

Implement `IntoIterator` for your collection type so `for x in my_collection` works.

## Anti-patterns (flag on sight)

- `for i in 0..v.len() { let x = v[i]; ... }` where `.iter()` / `.enumerate()` / `.zip()` is clearer and panic-free ([[rust-conventions]]).
- An iterator chain built for side effects with **no consumer** — the chain never runs.
- A baroque adapter chain that a plain `for` loop would express more readably — readability wins.
- `collect`ing into an intermediate `Vec` mid-pipeline instead of chaining lazily ([[rust-performance]]).
- Manual `match`/`if let` loops accumulating into a `Vec` where `filter_map` / `collect::<Result<_,_>>()` says it directly.
- `.into_iter()` (consuming) when the collection is still needed afterwards — should be `.iter()`.
- A `move` closure that needlessly clones captured data, or a missing `move` on a closure that outlives the scope ([[rust-async]]).
- `.unwrap()` inside a `map`/`filter` closure on a shipping path — propagate with `filter_map`/`collect::<Result<_,_>>` instead ([[rust-error-handling]]).

## Verification checklist

- [ ] Loops that transform data use iterator chains; index loops only where genuinely clearer.
- [ ] Every chain ends in a consumer (side-effect-only chains use `for_each`/`for`, not a dangling `map`).
- [ ] `collect` targets the right type; fallible chains use `collect::<Result<_, _>>()` to short-circuit.
- [ ] `iter` / `iter_mut` / `into_iter` chosen to match whether the collection is kept or consumed.
- [ ] Closures use the least-restrictive `Fn`/`FnMut`/`FnOnce` bound; `move` present exactly where ownership must transfer.
- [ ] No `.unwrap()` inside chain closures on shipping paths.
- [ ] No intermediate `collect` where lazy chaining works.

## Cross-references

- [[rust-conventions]] — iterators over index loops; don't out-clever a readable `for`.
- [[rust-ownership]] — `iter`/`iter_mut`/`into_iter` borrow-vs-consume; closure captures by ref vs `move`.
- [[rust-traits-generics]] — `Iterator`/`IntoIterator` and the `Fn`/`FnMut`/`FnOnce` trait family; accepting/returning closures.
- [[rust-performance]] — chains are zero-cost; the cost is needless intermediate `collect`s and allocations.
- [[rust-error-handling]] — `collect::<Result<Vec<_>, _>>()` to short-circuit; don't `unwrap` inside closures.
- [[rust-async]] — `move` closures for spawned tasks; async streams as the async analogue of iterators.