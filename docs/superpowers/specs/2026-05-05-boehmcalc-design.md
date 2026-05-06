# BoehmCalc.jl — Design

**Date:** 2026-05-05
**Status:** Draft for review

A Julia implementation of Hans Boehm's "Towards an API for the Real Numbers" (PLDI 2020). The package exports an `ExactReal <: Real` type that interoperates cleanly with Julia's number tower (`Float64`, `Rational`, `BigInt`, `Irrational`) and is suitable both as a number type inside generic Julia code and as a backend for a calculator-style UI.

## Goals

- A `Real` subtype that gives correct symbolic answers for calculator-typical operations (`sqrt(2)*sqrt(2) == 2`, `sin(π/6) == 1//2`, `log(exp(x)) == x`).
- Native interop: `Float64`, `Rational`, `BigInt`, `Irrational` promote/convert to `ExactReal`. Float values are interpreted as their exact binary value (Float64 `0.1` is exactly `3602879701896397 // 36028797018963968`).
- Calculator-UI usable: a `with_timeout(secs) do … end` helper aborts long computations cleanly.
- `==` and `<` are total — never throw, never loop forever — at the cost of conservative semantics on adversarial inputs.

## Non-goals (for v1)

- Hyperbolic functions (`sinh`/`cosh`/`tanh` and their inverses).
- Symbolic identities for `Irrational` constants other than `π` and `ℯ` (γ, catalan, φ etc. fall through to a tagged-Irrational form via `BigFloat`).
- Algebraic-number support beyond `√(rational)`.
- Multi-threaded sharing of a single `ExactReal`'s approximation cache (a future concern; v1 documents this as not supported).
- `parse(ExactReal, "expr")` from a string (a v1.x add).

## Architecture

Three internal layers, mirroring Boehm's CR / BoundedRational / UnifiedReal split, exposed as a single user-facing type.

```
┌──────────────────────────────────────────────────────────────────┐
│  ExactReal <: Real     (exported)                                │
│    rat_factor::Rational{BigInt}                                  │
│    cr_factor::CR                                                 │
│    prop::Property                                                │
│  value(x) = x.rat_factor * x.cr_factor                           │
└──────────────────────────────────────────────────────────────────┘
        ↓ owns                            ↓ tags
┌─────────────────────────────┐  ┌───────────────────────────────┐
│  CR  (lower layer)          │  │  Property                     │
│  abstract; ~14 op subtypes  │  │    tag::Tag                   │
│  approximate(x, p)::BigInt  │  │    arg::Union{Rational,       │
│  contract: |a*2^p - x| < 2^p│  │             Nothing}          │
│  precision-cached           │  │  Tag = One|Pi|Sqrt|Exp|Ln|    │
│                             │  │        Log|SinPi|TanPi|Asin|  │
│                             │  │        Atan|Irrational        │
└─────────────────────────────┘  └───────────────────────────────┘

  ↑
  │ rational arithmetic with overflow guard
┌─────────────────────────────┐
│  BoundedRational helpers    │
│  (internal, not exported)   │
│  try_add / try_mul / etc.   │
│  return Nothing on overflow │
│  threshold: MAX_RATIONAL_BITS│
└─────────────────────────────┘
```

### Why three layers

Each layer has one job:

- **`CR`** answers "give me an integer that approximates this real number to within ±1 at precision p". It knows nothing about symbolic identity — just lazy evaluation with caching.
- **`BoundedRational` helpers** keep the rational-arithmetic costs bounded. Without a cap, `(1 + 10⁻¹⁰⁰⁰)¹⁰⁰⁰⁰⁰` would build an exact rational of millions of bits even though the user only wants 15 decimal digits. The cap (default 10000 bits of `num + den` size) is the threshold past which we drop to the CR layer.
- **`ExactReal`** binds the symbolic tag to the lazy approximator and the rational factor. Equality reduces to comparing `(tag, arg, rat_factor)` for tagged forms; for `Irrational` it relies on Lindemann–Weierstrass-grade independence proofs.

## Module layout

```
BoehmCalc/
├── Project.toml                    # Julia ≥ 1.10
├── src/
│   ├── BoehmCalc.jl                # module root, re-exports
│   ├── cr.jl                       # CR + ~14 op subtypes
│   ├── bounded.jl                  # internal try_* rational helpers
│   ├── property.jl                 # Tag, Property, normalization, independence
│   ├── exact.jl                    # ExactReal struct + arithmetic
│   ├── compare.jl                  # is_comparable, ==, <, isless, hash
│   ├── transcendental.jl           # MPFR-backed sin/cos/tan/exp/ln/sqrt/asin/atan CRs
│   ├── show.jl                     # symbolic-aware display
│   ├── cancel.jl                   # CancelToken, with_timeout
│   └── convert.jl                  # promote_rule, convert
├── test/
│   ├── runtests.jl
│   ├── cr_tests.jl                 # ported from CRTest.java (HP MIT-style)
│   ├── exact_tests.jl              # ported from `reals` doc-tests (MIT)
│   ├── compare_tests.jl
│   ├── show_tests.jl
│   ├── cancel_tests.jl
│   └── interop_tests.jl
├── bin/
│   └── coverage                    # local coverage report script
├── docs/
│   └── superpowers/specs/2026-05-05-boehmcalc-design.md
├── CONTRIBUTING.md                 # incl. coverage workflow
└── ATTRIBUTION.md                  # AOSP / HP / `reals` license preservation
```

## Public API

### Exported names

`ExactReal`, `with_timeout`, `CancelException`, `MAX_RATIONAL_BITS`, plus the predicates `is_rational`, `is_integer`, `is_comparable`, `definitely_equal`, `definitely_less`. `is_zero_definitely` and `is_nonzero_definitely` are accessible as `BoehmCalc.is_zero_definitely` (not exported — niche use).

Note: we deliberately do **not** export `π` or `ℯ`. Users get the existing `Base.MathConstants.π` / `ℯ`, which convert/promote to `ExactReal` automatically.

### Constructors

```julia
ExactReal(::Int)
ExactReal(::BigInt)
ExactReal(::Rational)              # any Rational subtype
ExactReal(::Float64)               # interprets binary value exactly
ExactReal(::BigFloat)              # interprets binary value exactly
ExactReal(::Irrational{:π})        # symbolic Pi
ExactReal(::Irrational{:ℯ})        # symbolic Exp(1)
ExactReal(::Irrational{S}) where S # other irrationals → BigFloat → Irrational tag
```

### Arithmetic and elementary functions

- Arithmetic: `+`, `-`, `*`, `/`, `^` (rational and real exponents), `inv`, `abs`, `sign`.
- Roots: `sqrt`.
- Exponential / logarithm: `exp`, `log` (natural), `log10`, `log` (with base, dispatched to `log(x) / log(b)`).
- Trigonometric: `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan(y, x)`.
- Discrete: `factorial` (defined for non-negative integer-valued ExactReals).
- `zero(ExactReal)`, `one(ExactReal)`.

### Predicates

- `iszero`, `isone`, `isfinite` (always true), `isnan` (always false), `isinf` (always false).
- `is_rational(x)`, `is_integer(x)`, `is_zero_definitely(x)`, `is_nonzero_definitely(x)`.

### Comparison

- `==(a, b)`, `<(a, b)`, `<=`, `>=`, `isless`, `isequal` — all return `Bool`, never throw, never loop.
- `is_comparable(a, b)::Bool` — Boehm's `isComparable` decision tree, exposed for users who want to know in advance.
- `definitely_equal(a, b)::Bool` — alias for the symbolic-only equality (same as `==`).

### Conversion

- `convert(::Type{ExactReal}, x)` for `Int`, `BigInt`, `Rational`, `Float64`, `BigFloat`, `Irrational`.
- `Float64(x::ExactReal)` — round-to-nearest at 53 bits.
- `BigFloat(x::ExactReal; precision=...)` — round-to-nearest at the requested precision.
- `Rational{BigInt}(x::ExactReal)` — errors with `InexactError` unless `is_rational(x)`.

### Display

- `show(io, x::ExactReal)` — symbolic-aware default, decimal fallback (see "Display" section below).
- `show(io, ::MIME"text/plain", x)` — symbolic + decimal both shown.
- `show(io, ::MIME"text/latex", x)` — for Pluto/Jupyter.
- `string(x; digits=15)` — explicit decimal at requested significant digits, regardless of symbolic structure.

### Cancellation

```julia
with_timeout(f::Function, secs::Real)  # runs f(), aborts via CancelException after secs
struct CancelException <: Exception end
```

`with_timeout` uses `Base.ScopedValue` (Julia 1.11+) or `task_local_storage` (1.10) to thread a cancellation flag through every `approximate` call.

## Internal data structures

### CR (lower layer)

```julia
abstract type CR end

# Each op carries its operands and a precision cache.
mutable struct AddCR <: CR
    left::CR
    right::CR
    min_prec::Int
    max_appr::BigInt
    valid::Bool
    lock::ReentrantLock         # lazy-init on first contended access
end
```

Op subtypes (~14): `IntCR`, `ShiftedCR`, `NegCR`, `AddCR`, `MulCR`, `InvCR`, `SqrtCR`, `ExpCR`, `LnCR`, `CosCR`, `AtanCR`, `AsinCR`, `SelectCR` (sign-driven if-else), and `BigFloatCR` (the MPFR fast path).

**Approximation contract.** For any `x::CR` with mathematical value `v`:

```
approximate(x, p)::BigInt  ⇒  |a * 2^p − v| < 2^p
```

where `a` is the returned BigInt and `p` is typically negative (more negative = more precision). This matches Boehm's CR.java contract exactly.

**Caching.** `get_approx(x, p)` is the public, thread-safe entry:

```julia
function get_approx(x::CR, p::Int)
    @lock lock_for(x) begin
        if x.valid && p ≥ x.min_prec
            return x.max_appr >> (p - x.min_prec)
        end
        check_cancellation()
        result = approximate(x, p)
        x.min_prec = p
        x.max_appr = result
        x.valid = true
        return result
    end
end
```

`approximate(::CR, p)` is the per-subtype compute method, only called from `get_approx`.

**MPFR fast path.** `BigFloatCR` evaluates a transcendental via `BigFloat` at `setprecision(BigFloat, |p| + 64)`. For sane precisions (up to millions of bits) MPFR is dramatically faster than naive Taylor in BigInt and is correctly rounded. We trust MPFR's precision contract.

### BoundedRational (internal)

`Rational{BigInt}` plus a size predicate:

```julia
const MAX_RATIONAL_BITS = Ref(10_000)

function fits(r::Rational{BigInt})
    return ndigits(numerator(r), base=2) +
           ndigits(denominator(r), base=2) ≤ MAX_RATIONAL_BITS[]
end

# Returns nothing if the result would overflow the cap.
function try_add(a::Rational{BigInt}, b::Rational{BigInt})
    s = a + b
    fits(s) ? s : nothing
end

# Similar: try_sub, try_mul, try_div, try_pow_int, try_sqrt_exact, …
```

When a `try_*` returns `nothing`, the upper layer absorbs the value into `cr_factor` and sets `rat_factor = 1`, with the symbolic tag adjusted to `Irrational` (or whatever the combined form computes to).

### Property (symbolic tag)

```julia
@enum Tag::UInt8 begin
    One         # crFactor is exactly 1; value is purely rational
    Pi          # crFactor is π
    Sqrt        # crFactor is √arg, with arg::Rational > 0 not a perfect square
    Exp         # crFactor is e^arg, with arg ≠ 0
    Ln          # crFactor is ln(arg), with arg > 1 rational
    Log         # crFactor is log10(arg), with arg > 0 rational, arg not a power of 10
    SinPi       # crFactor is sin(π·arg), with arg ∈ (0, 1/2) and arg ∉ {1/6, 1/4, 1/3}
    TanPi       # crFactor is tan(π·arg), similar normalization
    Asin        # crFactor is asin(arg), with arg ∈ (0, 1) rational
    Atan        # crFactor is atan(arg), with arg > 0 rational
    Irrational  # cr is known irrational but symbolic form is lost
end

struct Property
    tag::Tag
    arg::Union{Rational{BigInt}, Nothing}  # nothing iff tag ∈ {One, Pi, Irrational}
end
```

Every Property is in canonical normal form via a private `make_property(tag, arg)` constructor that runs the normalization rules (paper §6). The normalization invariants are critical: they're what makes the Lindemann–Weierstrass independence argument valid.

### ExactReal (upper layer)

```julia
struct ExactReal <: Real
    rat_factor::Rational{BigInt}
    cr_factor::CR
    prop::Property
end
```

Mathematically: `value(x) = x.rat_factor * x.cr_factor`, with `x.prop` describing the symbolic identity of `cr_factor`.

Construction invariants enforced at all entry points:
- If `rat_factor == 0`, the ExactReal represents zero regardless of `cr_factor`/`prop`.
- If `prop.tag == One`, `cr_factor` evaluates to 1 (an `IntCR(1)` instance, shared).
- For all other tags, `cr_factor`'s value matches `prop` according to the tag's definition.

## Arithmetic dispatch

`+`, `-`, `*`, `/` on `ExactReal` are case-split on `(prop_a.tag, prop_b.tag)`:

- **Same tag, same arg:** combine rat_factors. `a·π + b·π = (a+b)·π`. Result tag = same.
- **`One` + anything:** the `One` side is a pure rational; addition becomes `(rat_a + rat_b·crFactor_b)`. If `rat_a == 0` the result preserves `b`'s tag. Otherwise the sum has no symbolic tag (becomes `Irrational` if the irrational summand is "big enough" — see below — or is left as a structured CR with no tag for tiny irrational summands).
- **Different tags, both irrational:** result is `Irrational` *only if* both summands have magnitude ≥ 2⁻³⁵⁰⁰ (the paper's guard against spurious-IRRATIONAL on summands that may cancel down). Otherwise the tag is dropped and the result becomes a plain CR with no symbolic guarantees.
- **Multiplication:** combines tags multiplicatively. `√a · √b = √(ab)` (when `ab` is in canonical form). `e^a · e^b = e^(a+b)`. `π · √a` becomes Irrational with no further structure.
- **Inverse / division:** `1 / (rat_factor · crFactor)` flips rat_factor and inverts crFactor. For `Sqrt` and friends, the inverse stays in the symbolic family (`1/√a = √(1/a)/...` after normalization).

When any of these tag-combination paths yields a `try_*` overflow, the rat_factor falls back to 1, the CR is constructed as the raw composition, and the tag becomes `Irrational` (or is dropped entirely).

## Comparison

### `is_comparable(a, b)::Bool`

Boehm's decision tree, runs in this order:

1. **Both zero.** If `iszero(a.rat_factor) && iszero(b.rat_factor)`, return true.
2. **Same Property.** If `a.prop == b.prop` and the prop is known nonzero, return true (compare reduces to comparing `rat_factor`).
3. **Both Sqrt with same rat_factor sign.** Compare squares directly.
4. **Independent properties + magnitude floor.** If the props are provably independent (Lindemann–Weierstrass: e.g. `Pi` is transcendental, `Sqrt(rat)` is algebraic of degree 2, distinct `Exp(rat)` are independent, etc.) AND at least one operand is ≥ 2⁻⁵⁰⁰⁰ in absolute value (cheap CR check), return true.
5. **Cheap approximate disambiguation.** If `get_approx(a − b, -100)` is unambiguously nonzero (≥ 2 in absolute value), return true.
6. Otherwise return false.

### `==`

```julia
function Base.:(==)(a::ExactReal, b::ExactReal)
    is_comparable(a, b) || return false
    return _exact_equal(a, b)   # cross-multiplication on rat_factors after tag matching
end
```

Conservative: false on undecided. False negatives are possible for adversarial inputs where mathematically-equal values aren't symbolically reducible.

### `isless` and `<`

Strict total order, with three-tier tiebreak:

```julia
function Base.isless(a::ExactReal, b::ExactReal)
    is_comparable(a, b) && return _exact_less(a, b)
    diff = (a - b).cr_factor                      # the difference as a CR
    Δ = get_approx(diff, -100)                    # BigInt approximation, ±1 of true value
    Δ < -1 && return true
    Δ >  1 && return false
    return objectid(a) < objectid(b)              # deterministic tiebreak
end
```

This guarantees `sort` produces deterministic, locally-correct output. The `objectid` tiebreak means `isless` is not perfectly mathematically motivated on the tied tail, but is consistent across runs (within a single process) and won't surprise generic Julia code that expects a total order.

`a < b` calls `isless(a, b)`. `a <= b` is `!(b < a)`.

The asymmetry between `==` (conservative) and `isless` (always-decides) is documented; users wanting strict symbolic ordering call `definitely_less(a, b)::Union{Bool,Missing}`.

### `hash`

```julia
function Base.hash(x::ExactReal, h::UInt)
    iszero(x.rat_factor) && return hash(0, h)
    return hash(x.prop.tag, hash(x.prop.arg, hash(x.rat_factor, h)))
end
```

Equal-comparable values hash identically (the contract `a == b ⇒ hash(a) == hash(b)` holds because `==` returns true only when `(rat_factor, tag, arg)` matches or both rat_factors are zero). Equal-but-not-comparable values may hash differently; that's fine because `==` returns false on those.

## Display

`show(io, x::ExactReal)` (the 2-arg form, used in arrays and interpolation) chooses by structure:

- `is_rational(x)` → print as `Rational` would (e.g. `3//2`, `0`, `1`).
- `prop.tag == Pi`, `rat_factor == 1` → `π`.
- `prop.tag == Pi`, `rat_factor == 1//4` → `π/4`.
- `prop.tag == Pi`, `rat_factor == 2` → `2π`.
- `prop.tag == Sqrt`, `rat_factor == 1` → `√{arg}` (printed with the arg).
- `prop.tag == Exp`, `arg == 1` → `ℯ`.
- Other tagged forms (small enum of "nice" patterns): printed similarly.
- Otherwise: `_truncated_decimal(x, 15)` — produces e.g. `1.4142135623730…` with the trailing `…`.

`show(io, ::MIME"text/plain", x)` prints both: `π/4 ≈ 0.7853981633974…` for the cases where the symbolic form differs from the decimal.

`show(io, ::MIME"text/latex", x)` produces LaTeX-formatted output for Pluto/Jupyter (`\frac{\pi}{4}`, `\sqrt{2}`, etc.).

`string(x; digits=15)` returns the truncated decimal at the requested significant digits, regardless of symbolic structure.

## Cancellation

```julia
struct CancelException <: Exception end

mutable struct CancelToken
    cancelled::Threads.Atomic{Bool}
end

const _current_token = ScopedValue{Union{CancelToken,Nothing}}(nothing)
# Fallback to task_local_storage on Julia 1.10.

function with_timeout(f::Function, secs::Real)
    tok = CancelToken(Threads.Atomic{Bool}(false))
    timer = Timer(_ -> tok.cancelled[] = true, secs)
    try
        with(_current_token => tok) do
            f()
        end
    finally
        close(timer)
    end
end

@inline check_cancellation() = let t = _current_token[]
    t === nothing && return
    t.cancelled[] && throw(CancelException())
end
```

`get_approx` calls `check_cancellation()` once per call. The check is cheap (one ScopedValue lookup, one atomic load). Cancellation surfaces as `CancelException` in the user's `with_timeout` block.

The user is expected to wrap potentially-slow computations:

```julia
result = try
    with_timeout(0.5) do
        very_complex_expression
    end
catch e
    e isa CancelException ? :timeout : rethrow()
end
```

## Conversion / promotion

```julia
Base.promote_rule(::Type{ExactReal}, ::Type{<:Integer}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{<:Rational}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{Float64}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{BigFloat}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{<:Irrational}) = ExactReal
```

`Float64` and `BigFloat` conversion treats the value as its exact binary form. `0.1` becomes `Rational(0.1) = 3602879701896397 // 36028797018963968` in the `One` tag.

For `Irrational{:π}` and `Irrational{:ℯ}`, conversion produces a properly-tagged `ExactReal`. For other `Irrational` constants (γ, catalan, φ, …), conversion goes through `BigFloat` at a default precision (256 bits, configurable) and produces an `Irrational`-tagged `ExactReal`. v1 doesn't add symbolic identities for these; v1.x can.

## Error handling

- **Domain errors** (sqrt of negative, log of non-positive, asin of out-of-range): throw `DomainError` at construction time when the rational layer can prove the violation; otherwise raised lazily on first `approximate` call. Matches Boehm.
- **Bound overflow**: never user-visible. Internal `try_*` returns `nothing` and the caller compensates.
- **`==` and `<`**: never throw, never loop. Always return `Bool`.
- **Cancellation**: `CancelException` propagates out of any `get_approx` call when `with_timeout` flips the token.

## Testing strategy

Three tiers of tests, plus interop:

1. **CR contract tests.** For each op subtype, generate random precisions and verify `|approximate(x, p) * 2^p − exact_value| < 2^p` against `BigFloat` reference computations. ~50 cases per op.

2. **Symbolic identity tests.** Ported from `reals` doc-tests (MIT) and `realistic` test suite (Apache 2.0). Each test asserts an exact symbolic equality:
   - `sqrt(2)*sqrt(2) == 2`
   - `sin(π/6) == 1//2`
   - `log(exp(x)) == x` for rational x
   - `asin(sin(x)) == x` for x in range
   - `pi - pi == 0`
   - `2*atan(1) == π/2`
   - … (~150 cases)

3. **Numerical agreement.** ExactReal results agree with `BigFloat` at multiple precisions across a generated corpus. Smoke tests catch numerical regressions.

4. **`CRTest.java` port.** ~50 cases from the AOSP CR test file (HP MIT-style license preserved in `ATTRIBUTION.md`).

5. **Cancellation tests.** Compute a known-slow operation in `with_timeout(0.05)`, verify `CancelException` is thrown.

6. **Hash invariants.** Generate a corpus of equal-comparable pairs; assert `hash(a) == hash(b)`.

7. **Promotion / interop tests.**
   - `1 + ExactReal(π) isa ExactReal`.
   - `ExactReal(0.1) != 1//10` — Float64 `0.1` is exactly `3602879701896397 // 36028797018963968`, *not* `1//10`. Test asserts both inequality with `1//10` and exact equality with the explicit binary rational.
   - `Float64(ExactReal(π)) ≈ π` to ~15 digits.
   - `[1, ExactReal(π)]` doesn't error and contains two `ExactReal`s after promotion.
   - `sort([ExactReal(π), ExactReal(2), ExactReal(0)])` produces `[0, 2, π]`.

8. **Conservatism tests.** Construct an ExactReal that is mathematically equal to another but where the symbolic layer can't reduce it. Assert `==` returns `false`, `isless` is consistent with the tiebreak rule, and `is_comparable` returns `false`. This documents the conservative-`==` design choice as a tested behavior.

### Coverage

Target ~100% line and branch coverage for `src/`. Workflow:

```bash
# bin/coverage
julia --project=. --code-coverage=user -e 'using Pkg; Pkg.test()'
julia --project=. -e '
  using Coverage
  cov = process_folder("src")
  covered, total = get_summary(cov)
  pct = round(100 * covered / total, digits=2)
  println("Line coverage: $covered / $total = $pct%")
  clean_folder("src")
'
```

Documented in `CONTRIBUTING.md`. The Codecov upload from CI gives the canonical number; the local script is for fast iteration.

### CI

- Julia 1.10 (LTS) and 1.12 (latest stable), Linux/macOS/Windows.
- Codecov integration (already configured by PkgTemplates).
- Dependabot for GitHub Actions version bumps (already configured).

## Performance notes

- BigInt is GMP, faster than Java BigInteger.
- BigFloat (MPFR) is the inner kernel for transcendentals: `setprecision(BigFloat, |p| + 64)` and trust MPFR's correct rounding.
- Caching: each CR caches its highest-computed-precision approximation. Re-asking for equal-or-coarser precision is a cheap right-shift.
- Lock contention on the cache is rare (CRs are usually accessed by a single task); the lock is allocated lazily.
- Property-tag equality check is `(tag, arg)` cross-comparison — small cases dispatch fast.

## Licensing

`BoehmCalc.jl` itself is MIT (already chosen at package creation). `ATTRIBUTION.md` lists upstream sources whose tests/algorithms we mine:

- `CR.java` from AOSP `external/crcalc` (HP, 2001–2004, MIT-style permissive).
- `UnifiedReal.java` and `BoundedRational.java` from AOSP `packages/apps/ExactCalculator` (Google, Apache 2.0).
- `reals` and `computable-real` Rust crates (hkalexling, MIT) — for ported test cases.
- `realistic` Rust crate (Nick Lamb, Apache 2.0) — for ported test cases.

All compatible with MIT redistribution; we preserve copyright notices in the test files we port.

## Open questions for follow-up

These are deliberately deferred to v1.x:

- Symbolic identities for `Irrational{:γ}`, `Irrational{:catalan}`, `Irrational{:φ}`. These would need new `Tag` values and Lindemann–Weierstrass-grade independence claims with the existing tags.
- Hyperbolics with symbolic tags. Either as derived (`sinh = (exp(x) - exp(-x))/2`, no new tags) or first-class (`Sinh`/`Cosh`/`Tanh` tags with their own normalization).
- `parse(ExactReal, "sqrt(2)+pi/3")` for string round-tripping.
- Multi-threaded sharing of a single ExactReal's CR cache. Currently the `ReentrantLock` per CR makes it formally safe but performance under contention is untested.
- Algebraic numbers beyond `√(rational)`. A future "AlgebraicReal" extension could plug into the property algebra.
