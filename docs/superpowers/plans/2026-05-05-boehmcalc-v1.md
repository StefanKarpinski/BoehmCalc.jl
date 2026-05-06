# BoehmCalc.jl v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement BoehmCalc.jl v1 per `SPEC.md`: an `ExactReal <: Real` Julia type backed by a three-layer constructive-real architecture, with MPFR-backed transcendentals, `with_timeout` cancellation, symbolic-aware display, and full Julia number-tower interop.

**Architecture:** Three layers — (1) `CR` (lower; lazy `approximate(x, p)::BigInt` with `|a·2^p − x| < 2^p` contract and per-instance precision caching), (2) internal `BoundedRational` helpers (`try_*` ops capped at `MAX_RATIONAL_BITS = 10000`), and (3) `ExactReal <: Real` (upper; `rat_factor::Rational{BigInt} × cr_factor::CR` plus a `Property{tag, arg}` symbolic identity). Transcendentals are thin `BigFloatCR` wrappers over MPFR.

**Tech Stack:** Julia ≥ 1.10, `BigInt` (GMP), `BigFloat` (MPFR), `Base.ScopedValue` (1.11+) with `task_local_storage` fallback (1.10), `Test` stdlib, `Coverage.jl` (test-only).

**Required reading before starting:** `SPEC.md` at the repo root. The spec contains algorithmic details, comparison decision tree, normalization rules, and edge cases. This plan sequences the implementation as TDD tasks; it does not duplicate the spec.

**Reference implementations** (for translating algorithms):
- `CR.java` (HP, MIT-style): https://android.googlesource.com/platform/external/crcalc/+/refs/heads/master/src/com/hp/creals/CR.java
- `UnifiedReal.java`, `BoundedRational.java` (AOSP, Apache 2.0): https://android.googlesource.com/platform/packages/apps/ExactCalculator/+/refs/tags/android-9.0.0_r32/src/com/android/calculator2/

---

## File layout

```
src/BoehmCalc.jl           module root; includes other src files
src/cancel.jl              CancelException, CancelToken, with_timeout, check_cancellation
src/cr.jl                  abstract CR, get_approx caching, all op subtypes except transcendental
src/transcendental.jl      BigFloatCR + sin/cos/exp/ln/atan/asin/sqrt CR wrappers
src/bounded.jl             MAX_RATIONAL_BITS, fits, try_add/sub/mul/div/pow/sqrt_exact
src/property.jl            Tag enum, Property, make_property normalization, definitely_independent
src/exact.jl               ExactReal struct, constructors, predicates, arithmetic
src/compare.jl             is_comparable, ==, isless, decompose
src/convert.jl             promote_rule, convert, Float64/BigFloat/Rational coercion
src/show.jl                symbolic-aware show (text/plain, text/latex), string(x; digits)

test/runtests.jl           top-level @testset, includes the rest
test/cancel_tests.jl
test/cr_tests.jl
test/transcendental_tests.jl
test/bounded_tests.jl
test/property_tests.jl
test/exact_tests.jl
test/compare_tests.jl
test/convert_tests.jl
test/show_tests.jl
test/interop_tests.jl

bin/coverage               local coverage report script
ATTRIBUTION.md             upstream license preservation
CONTRIBUTING.md            dev workflow incl. coverage
```

---

## Conventions used by every task

- **Tests live alongside code, one test file per src file.**
- **Run a single test file** during a TDD cycle: `julia --project=. -e 'using Pkg; Pkg.test(); ' won't work for a single file — instead use `julia --project=. test/cr_tests.jl` which `include`s the file standalone (each test file uses `using BoehmCalc, Test` at the top).
- **Run the full suite** with `julia --project=. -e 'using Pkg; Pkg.test()'`.
- **Commit messages:** conventional-commits style. `feat: …`, `test: …`, `refactor: …`, `docs: …`.
- **Each task is one TDD cycle:** failing test → implementation → passing test → commit.

---

## Phase 0: Test scaffolding

### Task 0.1: Set up test/runtests.jl as an aggregator

**Files:**
- Modify: `test/runtests.jl`

- [ ] **Step 1: Replace test/runtests.jl with the aggregator**

```julia
using BoehmCalc
using Test

@testset "BoehmCalc" begin
    include("cancel_tests.jl")
    include("cr_tests.jl")
    include("transcendental_tests.jl")
    include("bounded_tests.jl")
    include("property_tests.jl")
    include("exact_tests.jl")
    include("compare_tests.jl")
    include("convert_tests.jl")
    include("show_tests.jl")
    include("interop_tests.jl")
end
```

- [ ] **Step 2: Create empty test files so `include` doesn't fail**

```bash
touch test/{cancel,cr,transcendental,bounded,property,exact,compare,convert,show,interop}_tests.jl
```

- [ ] **Step 3: Run the full test suite to verify the harness loads**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS (no tests yet, all empty).

- [ ] **Step 4: Commit**

```bash
git add test/
git commit -m "test: add per-module test file aggregator"
```

---

## Phase 1: Cancellation primitives

(Cancellation must exist before CR caching, because `get_approx` calls `check_cancellation()`.)

### Task 1.1: CancelException, CancelToken, with_timeout, check_cancellation

**Files:**
- Create: `src/cancel.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/cancel_tests.jl`

- [ ] **Step 1: Write the failing tests in test/cancel_tests.jl**

```julia
using BoehmCalc
using Test

@testset "cancel" begin
    @test BoehmCalc.check_cancellation() === nothing  # no token set: no-op

    tok = BoehmCalc.CancelToken()
    @test tok.cancelled[] == false

    # Token activated → check_cancellation throws
    @test_throws BoehmCalc.CancelException BoehmCalc._with_token(tok) do
        tok.cancelled[] = true
        BoehmCalc.check_cancellation()
    end

    # with_timeout returns the function's value when fast
    result = BoehmCalc.with_timeout(1.0) do
        42
    end
    @test result == 42

    # with_timeout throws CancelException when slow
    @test_throws BoehmCalc.CancelException BoehmCalc.with_timeout(0.05) do
        # Busy-loop with cancellation checks until the timer fires
        while true
            BoehmCalc.check_cancellation()
            sleep(0.001)
        end
    end
end
```

- [ ] **Step 2: Run to verify FAIL**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: FAIL with "UndefVarError: CancelToken not defined" (or similar).

- [ ] **Step 3: Create src/cancel.jl**

```julia
struct CancelException <: Exception end

mutable struct CancelToken
    cancelled::Threads.Atomic{Bool}
    CancelToken() = new(Threads.Atomic{Bool}(false))
end

cancel!(tok::CancelToken) = (tok.cancelled[] = true; nothing)

# Use ScopedValue on Julia 1.11+, task_local_storage on 1.10.
@static if isdefined(Base, :ScopedValue)
    const _current_token = Base.ScopedValue{Union{CancelToken,Nothing}}(nothing)

    _with_token(f, tok::CancelToken) = Base.with(f, _current_token => tok)
    _current(::Nothing) = nothing
    current_token() = _current_token[]
else
    function _with_token(f, tok::CancelToken)
        prev = get(task_local_storage(), :_boehmcalc_cancel_token, nothing)
        task_local_storage()[:_boehmcalc_cancel_token] = tok
        try
            return f()
        finally
            task_local_storage()[:_boehmcalc_cancel_token] = prev
        end
    end
    current_token() = get(task_local_storage(), :_boehmcalc_cancel_token, nothing)
end

@inline function check_cancellation()
    tok = current_token()
    tok === nothing && return nothing
    tok.cancelled[] && throw(CancelException())
    return nothing
end

function with_timeout(f::Function, secs::Real)
    tok = CancelToken()
    timer = Timer(_ -> cancel!(tok), secs)
    try
        return _with_token(f, tok)
    finally
        close(timer)
    end
end
```

- [ ] **Step 4: Wire src/cancel.jl into the module**

Replace `src/BoehmCalc.jl` with:

```julia
module BoehmCalc

include("cancel.jl")

export with_timeout, CancelException

end # module BoehmCalc
```

- [ ] **Step 5: Run tests, verify PASS**

Run: `julia --project=. -e 'using Pkg; Pkg.test()'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/cancel.jl src/BoehmCalc.jl test/cancel_tests.jl
git commit -m "feat: cancellation primitives (CancelToken, with_timeout, check_cancellation)"
```

---

## Phase 2: CR layer

### Task 2.1: Abstract CR + IntCR + get_approx caching

**Files:**
- Create: `src/cr.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/cr_tests.jl`

- [ ] **Step 1: Write failing tests**

```julia
# test/cr_tests.jl
using BoehmCalc
using BoehmCalc: CR, IntCR, get_approx, approximate
using Test

@testset "CR foundation" begin
    @testset "IntCR" begin
        c = IntCR(BigInt(5))
        @test get_approx(c, 0) == 5         # 5 = 5 * 2^0
        @test get_approx(c, -1) == 10       # 5 = 10 * 2^-1
        @test get_approx(c, 1) == 2         # 5 ≈ 2 * 2^1 = 4 (within ±1)
        @test get_approx(c, 4) == 0         # 5 ≈ 0 * 16 (within ±1? — actually 5/16 rounds to 0)
    end

    @testset "Caching" begin
        c = IntCR(BigInt(7))
        # First call computes
        @test get_approx(c, -8) == 7 * 256  # 7 = 1792 * 2^-8
        @test c.min_prec == -8
        # Re-asking at coarser precision: cache scales down
        @test get_approx(c, 0) == 7
        @test c.min_prec == -8              # still cached at -8
    end
end
```

- [ ] **Step 2: Run, verify FAIL** (UndefVarError on `CR`).

- [ ] **Step 3: Create src/cr.jl**

```julia
abstract type CR end

# Helper: arithmetic right shift for BigInt that rounds toward zero,
# matching Boehm's `scale` function semantics: scale(x, n) = round-to-nearest(x / 2^n).
function _shift(x::BigInt, n::Int)
    n == 0 && return x
    if n > 0
        # Right shift with round-half-up (Boehm's convention).
        # adjusted = (x + 2^(n-1)) >> n
        return (x + (BigInt(1) << (n - 1))) >> n
    else
        return x << -n
    end
end

# Cached approximation accessor.
function get_approx(x::CR, p::Int)
    lock(x.lock)
    try
        if x.valid && p >= x.min_prec
            return _shift(x.max_appr, p - x.min_prec)
        end
        check_cancellation()
        result = approximate(x, p)
        x.min_prec = p
        x.max_appr = result
        x.valid = true
        return result
    finally
        unlock(x.lock)
    end
end

# Default constructor helper for the cache fields.
_make_cache() = (BigInt(0), 0, false, ReentrantLock())

# IntCR: an exact integer.
mutable struct IntCR <: CR
    n::BigInt
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    IntCR(n::Integer) = (cache = _make_cache(); new(BigInt(n), cache[1], cache[2], cache[3], cache[4]))
end

approximate(x::IntCR, p::Int) = _shift(x.n, p)
```

- [ ] **Step 4: Wire into module**

Add `include("cr.jl")` to `src/BoehmCalc.jl` after `include("cancel.jl")`.

- [ ] **Step 5: Run, verify PASS.**

- [ ] **Step 6: Commit**

```bash
git add src/cr.jl src/BoehmCalc.jl test/cr_tests.jl
git commit -m "feat(cr): abstract CR + IntCR + get_approx with precision caching"
```

### Task 2.2: ShiftedCR

**Files:**
- Modify: `src/cr.jl`
- Modify: `test/cr_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
# Append to test/cr_tests.jl, inside the outer @testset
@testset "ShiftedCR" begin
    c = BoehmCalc.ShiftedCR(BoehmCalc.IntCR(3), 4)  # 3 * 2^4 = 48
    @test get_approx(c, 0) == 48
    @test get_approx(c, 4) == 3
    c2 = BoehmCalc.ShiftedCR(BoehmCalc.IntCR(8), -2)  # 8 / 4 = 2
    @test get_approx(c2, 0) == 2
end
```

- [ ] **Step 2: Run, FAIL** on undefined `ShiftedCR`.

- [ ] **Step 3: Add ShiftedCR to src/cr.jl**

```julia
mutable struct ShiftedCR <: CR
    op::CR
    count::Int                  # positive = left shift (multiply by 2^count)
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function ShiftedCR(op::CR, count::Int)
        c = _make_cache()
        new(op, count, c[1], c[2], c[3], c[4])
    end
end

approximate(x::ShiftedCR, p::Int) = get_approx(x.op, p - x.count)
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/cr.jl test/cr_tests.jl
git commit -m "feat(cr): ShiftedCR (multiplication by power of 2)"
```

### Task 2.3: NegCR

**Files:**
- Modify: `src/cr.jl`
- Modify: `test/cr_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "NegCR" begin
    c = BoehmCalc.NegCR(BoehmCalc.IntCR(7))
    @test get_approx(c, 0) == -7
    @test get_approx(c, -3) == -56
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add NegCR**

```julia
mutable struct NegCR <: CR
    op::CR
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function NegCR(op::CR)
        c = _make_cache()
        new(op, c[1], c[2], c[3], c[4])
    end
end

approximate(x::NegCR, p::Int) = -get_approx(x.op, p)
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/cr.jl test/cr_tests.jl
git commit -m "feat(cr): NegCR"
```

### Task 2.4: AddCR

**Files:**
- Modify: `src/cr.jl`
- Modify: `test/cr_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "AddCR" begin
    a = BoehmCalc.IntCR(5)
    b = BoehmCalc.IntCR(7)
    c = BoehmCalc.AddCR(a, b)
    @test get_approx(c, 0) == 12
    @test get_approx(c, -2) == 48      # 12 = 48 * 2^-2

    # With ShiftedCR: 5 + 8 = 13
    c2 = BoehmCalc.AddCR(BoehmCalc.IntCR(5), BoehmCalc.ShiftedCR(BoehmCalc.IntCR(2), 2))
    @test get_approx(c2, 0) == 13
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add AddCR**

`AddCR.approximate(p)` evaluates each operand at `p−2` (gaining 2 extra bits to keep the rounded sum within ±1 at precision `p`), sums them, and shifts back. This matches CR.java's `add_CR.approximate`.

```julia
mutable struct AddCR <: CR
    left::CR
    right::CR
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function AddCR(left::CR, right::CR)
        c = _make_cache()
        new(left, right, c[1], c[2], c[3], c[4])
    end
end

function approximate(x::AddCR, p::Int)
    pp = p - 2
    return _shift(get_approx(x.left, pp) + get_approx(x.right, pp), 2)
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/cr.jl test/cr_tests.jl
git commit -m "feat(cr): AddCR with +2 precision bump for error budget"
```

### Task 2.5: MulCR

**Files:**
- Modify: `src/cr.jl`
- Modify: `test/cr_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "MulCR" begin
    a = BoehmCalc.IntCR(3)
    b = BoehmCalc.IntCR(7)
    c = BoehmCalc.MulCR(a, b)
    @test get_approx(c, 0) == 21
    @test get_approx(c, -10) == 21 * 1024
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add MulCR**

The algorithm (Boehm's `mult_CR`):

1. Compute `half_prec = bit_length(max(|a|, |b|, 1)) + 3`. This is roughly `log2(max(|a|,|b|))`.
2. Evaluate the smaller-magnitude operand to higher precision; details in CR.java but the simplified contract is: get each operand at precision `(p / 2) - some_slack`, multiply, scale.

Translating CR.java's algorithm:

```julia
mutable struct MulCR <: CR
    left::CR
    right::CR
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function MulCR(left::CR, right::CR)
        c = _make_cache()
        new(left, right, c[1], c[2], c[3], c[4])
    end
end

function approximate(x::MulCR, p::Int)
    half_prec = (p >> 1) - 1
    msd_op1 = msd(x.left, half_prec)
    if msd_op1 == typemin(Int)
        # Operand 1 is very small; try operand 2 instead
        msd_op2 = msd(x.right, half_prec)
        if msd_op2 == typemin(Int)
            return BigInt(0)   # both are tiny, product within error
        end
        # Swap roles
        prec1 = p - msd_op2 - 3
        prec2 = half_prec
        a1 = get_approx(x.right, prec1)
        a2 = get_approx(x.left, prec2)
    else
        prec2 = p - msd_op1 - 3
        prec1 = half_prec
        a1 = get_approx(x.left, prec1)
        a2 = get_approx(x.right, prec2)
    end
    scale_amount = prec1 + prec2 - p
    return _shift(a1 * a2, scale_amount)
end
```

We need `msd` (most significant digit / position of highest nonzero bit). Add it now too:

```julia
"""
Return n such that 2^n ≤ |x| < 2^(n+1) (Boehm's convention: floor of log2|x|),
or `typemin(Int)` if `x` is provably within ±1 of zero at the deepest precision
we'll search (so we can't determine the sign / magnitude).
"""
function msd(x::CR, p::Int)
    a = get_approx(x, p)
    while -1 <= a <= 1
        check_cancellation()
        p -= 1
        a = get_approx(x, p)
        if p < -10_000_000
            return typemin(Int)
        end
    end
    return p + ndigits(abs(a), base=2) - 1
end
```

The `-10_000_000` cap matches Boehm's empirical bound for "this is functionally zero." Real callers will check `is_zero_definitely` before invoking operations that depend on `msd`.

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/cr.jl test/cr_tests.jl
git commit -m "feat(cr): MulCR + msd helper"
```

### Task 2.6: InvCR

**Files:**
- Modify: `src/cr.jl`
- Modify: `test/cr_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "InvCR" begin
    # 1 / 4 = 0.25. At precision -2: 0.25 * 4 = 1
    c = BoehmCalc.InvCR(BoehmCalc.IntCR(4))
    @test get_approx(c, -2) == 1
    @test get_approx(c, -10) == 256       # 0.25 * 1024
    # 1 / 3 ≈ 0.333... at precision -10 should be ≈ 341 (within ±1)
    c2 = BoehmCalc.InvCR(BoehmCalc.IntCR(3))
    @test abs(get_approx(c2, -10) - 341) <= 1
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add InvCR (Boehm's `inv_CR`)**

```julia
mutable struct InvCR <: CR
    op::CR
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function InvCR(op::CR)
        c = _make_cache()
        new(op, c[1], c[2], c[3], c[4])
    end
end

function approximate(x::InvCR, p::Int)
    msd_op = msd(x.op, p - 2)            # find magnitude of operand
    inv_msd = 1 - msd_op                  # estimated msd of result
    # Need operand at precision (-2*inv_msd - 3 + p) to get result at precision p
    digits_needed_p = (-2 * inv_msd - 3) + p
    # Compute |op|; require nonzero. If `msd` returned typemin, the operand is
    # effectively zero and inversion isn't meaningful.
    msd_op == typemin(Int) && throw(DomainError(x.op, "inverse of (effectively) zero"))
    op_appr = get_approx(x.op, digits_needed_p)
    # Result = (1 << (-p - digits_needed_p + sign_adjustment)) / op_appr
    # Following CR.java: scale = digits_needed_p - p (this is positive)
    scale_factor = digits_needed_p - p
    return div(BigInt(1) << scale_factor, op_appr)
end
```

(Note: the precise scaling above matches CR.java's `inv_CR.approximate`. If a TDD step fails, cross-check against the source URL in this plan's header.)

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/cr.jl test/cr_tests.jl
git commit -m "feat(cr): InvCR (1/x)"
```

### Task 2.7: SelectCR

**Files:**
- Modify: `src/cr.jl`
- Modify: `test/cr_tests.jl`

`SelectCR` returns one of two CR values depending on the sign of a third (the "selector"). It's used internally for `abs` and similar sign-dependent operations.

- [ ] **Step 1: Add failing test**

```julia
@testset "SelectCR" begin
    # If selector ≥ 0, return then-branch; else, return else-branch.
    pos = BoehmCalc.IntCR(5)
    neg = BoehmCalc.IntCR(-5)
    sel = BoehmCalc.IntCR(1)               # positive
    c = BoehmCalc.SelectCR(sel, pos, neg)
    @test get_approx(c, 0) == 5

    sel2 = BoehmCalc.IntCR(-1)             # negative
    c2 = BoehmCalc.SelectCR(sel2, pos, neg)
    @test get_approx(c2, 0) == -5
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add SelectCR**

```julia
mutable struct SelectCR <: CR
    selector::CR
    then_op::CR
    else_op::CR
    selected::Int                          # 0 = unknown, 1 = then, -1 = else
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function SelectCR(selector::CR, then_op::CR, else_op::CR)
        c = _make_cache()
        new(selector, then_op, else_op, 0, c[1], c[2], c[3], c[4])
    end
end

function approximate(x::SelectCR, p::Int)
    if x.selected == 0
        # Refine selector until we know its sign.
        a = get_approx(x.selector, p - 20)
        x.selected = a >= 0 ? 1 : -1
    end
    return get_approx(x.selected == 1 ? x.then_op : x.else_op, p)
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/cr.jl test/cr_tests.jl
git commit -m "feat(cr): SelectCR (sign-driven branch)"
```

---

## Phase 3: Transcendental CRs (MPFR-backed)

### Task 3.1: BigFloatCR + sqrt

**Files:**
- Create: `src/transcendental.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/transcendental_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
# test/transcendental_tests.jl
using BoehmCalc
using BoehmCalc: BigFloatCR, get_approx, IntCR, SqrtCR
using Test

@testset "transcendental" begin
    @testset "BigFloatCR via sqrt" begin
        # sqrt(4) = 2
        c = SqrtCR(IntCR(4))
        @test get_approx(c, 0) == 2
        @test get_approx(c, -10) == 2 * 1024

        # sqrt(2) ≈ 1.41421356... at precision -20: round to nearest of 1.4142136 * 2^20
        # ≈ 1482910
        a = get_approx(SqrtCR(IntCR(2)), -20)
        @test abs(a - 1482910) <= 1
    end
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Create src/transcendental.jl**

`BigFloatCR(f, op_cr)` evaluates `f(BigFloat(op_cr))` at appropriately-bumped precision.

```julia
"""
A CR backed by MPFR (BigFloat). Computes `f(x)` where `x` is itself a CR by:
  1. Asking the operand for an approximation at scale `-(|p| + extra_bits)`.
  2. Converting to BigFloat with sufficient precision.
  3. Calling `f` on the BigFloat.
  4. Scaling the result back to a BigInt at scale p.
"""
mutable struct BigFloatCR <: CR
    f::Function                           # f::BigFloat -> BigFloat
    op::CR
    extra_bits::Int                       # precision bump above |p|
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function BigFloatCR(f, op::CR; extra_bits::Int = 64)
        c = _make_cache()
        new(f, op, extra_bits, c[1], c[2], c[3], c[4])
    end
end

function approximate(x::BigFloatCR, p::Int)
    pp = max(64, abs(p) + x.extra_bits)
    setprecision(BigFloat, pp) do
        # Convert operand CR to BigFloat at the target precision.
        op_appr_bigint = get_approx(x.op, -pp)
        # op_appr_bigint * 2^-pp ≈ op (within 2^-pp absolute error)
        op_bf = BigFloat(op_appr_bigint) * BigFloat(2.0)^(-pp)
        result_bf = x.f(op_bf)
        # Scale to BigInt at scale p: round(result_bf * 2^-p)
        scaled = result_bf * BigFloat(2.0)^(-p)
        return round(BigInt, scaled)
    end
end

# Sqrt: domain check (op > 0) is the caller's responsibility; we trust MPFR.
SqrtCR(op::CR) = BigFloatCR(sqrt, op)
```

- [ ] **Step 4: Wire into module**

Append `include("transcendental.jl")` after `include("cr.jl")` in `src/BoehmCalc.jl`.

- [ ] **Step 5: Run, PASS.**

- [ ] **Step 6: Commit**

```bash
git add src/transcendental.jl src/BoehmCalc.jl test/transcendental_tests.jl
git commit -m "feat(cr): BigFloatCR + SqrtCR via MPFR"
```

### Task 3.2: Exp/Ln/Sin/Cos/Tan/Atan/Asin CRs

**Files:**
- Modify: `src/transcendental.jl`
- Modify: `src/cr.jl`  (add a `Pi` CR singleton — needed for cos/sin)
- Modify: `test/transcendental_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
@testset "MPFR-backed transcendentals" begin
    # exp(0) = 1
    @test get_approx(BoehmCalc.ExpCR(IntCR(0)), 0) == 1
    # exp(1) ≈ 2.71828... at precision -20: round(2.71828 * 2^20) ≈ 2850156
    @test abs(get_approx(BoehmCalc.ExpCR(IntCR(1)), -20) - 2850156) <= 1
    # ln(1) = 0
    @test get_approx(BoehmCalc.LnCR(IntCR(1)), 0) == 0
    # cos(0) = 1
    @test get_approx(BoehmCalc.CosCR(IntCR(0)), 0) == 1
    # sin(0) = 0 (we'll synthesize sin from cos via shift below in Phase 6;
    # for the CR layer, just test cos)
    # atan(0) = 0
    @test get_approx(BoehmCalc.AtanCR(IntCR(0)), 0) == 0
    # asin(0) = 0
    @test get_approx(BoehmCalc.AsinCR(IntCR(0)), 0) == 0

    # PiCR ≈ 3.14159...
    @test abs(get_approx(BoehmCalc.PiCR(), -20) - 3294199) <= 1
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add to src/transcendental.jl**

```julia
ExpCR(op::CR)  = BigFloatCR(exp, op)
LnCR(op::CR)   = BigFloatCR(log, op)
CosCR(op::CR)  = BigFloatCR(cos, op)
AtanCR(op::CR) = BigFloatCR(atan, op)
AsinCR(op::CR) = BigFloatCR(asin, op)

# π as a singleton CR (no operand). We just call BigFloat(π) at the right precision.
mutable struct PiCR <: CR
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function PiCR()
        c = _make_cache()
        new(c[1], c[2], c[3], c[4])
    end
end

function approximate(::PiCR, p::Int)
    pp = max(64, abs(p) + 64)
    setprecision(BigFloat, pp) do
        return round(BigInt, BigFloat(π) * BigFloat(2.0)^(-p))
    end
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/transcendental.jl test/transcendental_tests.jl
git commit -m "feat(cr): Exp/Ln/Cos/Atan/Asin/Pi CRs via MPFR"
```

### Task 3.3: Cancellation works inside CR ops

**Files:**
- Modify: `test/cancel_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
# Append to test/cancel_tests.jl, inside the outer @testset:
@testset "cancellation aborts CR computation" begin
    # Build a deeply-nested CR that takes a while to refine, then cancel it.
    deep = BoehmCalc.IntCR(2)
    for _ in 1:30
        deep = BoehmCalc.SqrtCR(BoehmCalc.AddCR(deep, BoehmCalc.IntCR(1)))
    end
    @test_throws BoehmCalc.CancelException BoehmCalc.with_timeout(0.001) do
        # Demand high precision; should be canceled before completion
        BoehmCalc.get_approx(deep, -10_000_000)
    end
end
```

- [ ] **Step 2: Run, PASS** (cancellation is already wired into get_approx via Task 1.1's check_cancellation; this test just confirms it works through the deep stack).

If FAIL: ensure `check_cancellation()` is called inside the `lock` block in `get_approx`. Re-run.

- [ ] **Step 3: Commit**

```bash
git add test/cancel_tests.jl
git commit -m "test: cancellation aborts deep CR computation"
```

---

## Phase 4: BoundedRational helpers

### Task 4.1: MAX_RATIONAL_BITS, fits, try_add/sub/mul/div

**Files:**
- Create: `src/bounded.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/bounded_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
# test/bounded_tests.jl
using BoehmCalc
using BoehmCalc: MAX_RATIONAL_BITS, fits, try_add, try_sub, try_mul, try_div
using Test

@testset "BoundedRational helpers" begin
    @test fits(Rational{BigInt}(1, 2))
    @test fits(Rational{BigInt}(BigInt(2)^9000, 1))
    @test !fits(Rational{BigInt}(BigInt(2)^11000, 1))   # > MAX_RATIONAL_BITS

    @test try_add(Rational{BigInt}(1, 2), Rational{BigInt}(1, 3)) == Rational{BigInt}(5, 6)
    huge = Rational{BigInt}(BigInt(2)^9000, 1)
    @test try_mul(huge, huge) === nothing               # would exceed cap

    @test try_sub(Rational{BigInt}(2, 3), Rational{BigInt}(1, 3)) == Rational{BigInt}(1, 3)
    @test try_div(Rational{BigInt}(1, 2), Rational{BigInt}(1, 3)) == Rational{BigInt}(3, 2)
    @test try_div(Rational{BigInt}(1, 2), Rational{BigInt}(0)) === nothing   # divide by zero
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Create src/bounded.jl**

```julia
const MAX_RATIONAL_BITS = Ref(10_000)

function fits(r::Rational{BigInt})
    n = numerator(r)
    d = denominator(r)
    bits_n = iszero(n) ? 0 : ndigits(abs(n), base=2)
    bits_d = ndigits(d, base=2)
    return bits_n + bits_d <= MAX_RATIONAL_BITS[]
end

@inline _wrap(r::Rational{BigInt}) = fits(r) ? r : nothing

try_add(a::Rational{BigInt}, b::Rational{BigInt}) = _wrap(a + b)
try_sub(a::Rational{BigInt}, b::Rational{BigInt}) = _wrap(a - b)
try_mul(a::Rational{BigInt}, b::Rational{BigInt}) = _wrap(a * b)
try_div(a::Rational{BigInt}, b::Rational{BigInt}) = iszero(b) ? nothing : _wrap(a // b)

# Integer pow with bound check.
function try_pow(a::Rational{BigInt}, n::Integer)
    n == 0 && return Rational{BigInt}(1)
    n == 1 && return a
    n < 0  && return iszero(a) ? nothing : try_pow(inv(a), -n)
    # Naive repeated multiplication; bail early on overflow.
    result = Rational{BigInt}(1)
    base = a
    e = n
    while e > 0
        if isodd(e)
            r = try_mul(result, base)
            r === nothing && return nothing
            result = r
        end
        e >>= 1
        if e > 0
            r = try_mul(base, base)
            r === nothing && return nothing
            base = r
        end
    end
    return result
end

# Exact square root if a is a perfect square of a rational; nothing otherwise.
function try_sqrt_exact(a::Rational{BigInt})
    a < 0 && return nothing
    iszero(a) && return Rational{BigInt}(0)
    n = numerator(a); d = denominator(a)
    sn = isqrt(n); sd = isqrt(d)
    sn * sn == n && sd * sd == d || return nothing
    return _wrap(Rational{BigInt}(sn, sd))
end
```

Add `include("bounded.jl")` to `src/BoehmCalc.jl` after `include("transcendental.jl")` and export `MAX_RATIONAL_BITS`.

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/bounded.jl src/BoehmCalc.jl test/bounded_tests.jl
git commit -m "feat: BoundedRational helpers (MAX_RATIONAL_BITS-aware try_*)"
```

---

## Phase 5: Property tag

### Task 5.1: Tag enum, Property struct, make_property normalization

**Files:**
- Create: `src/property.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/property_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
# test/property_tests.jl
using BoehmCalc
using BoehmCalc: Property, make_property, definitely_independent
using Test

# @enum-defined values are module-level bindings in BoehmCalc, not nested
# under the type name. Use BoehmCalc.One, BoehmCalc.Pi, etc.
@testset "Property" begin
    @test Property(BoehmCalc.One, nothing).tag == BoehmCalc.One

    # Sqrt(4) is a perfect square, normalizes to One
    @test make_property(BoehmCalc.Sqrt, Rational{BigInt}(4)).tag == BoehmCalc.One
    # Sqrt(2) stays Sqrt
    @test make_property(BoehmCalc.Sqrt, Rational{BigInt}(2)).tag == BoehmCalc.Sqrt
    # Sqrt(8) = 2 * sqrt(2) — normalizer extracts square factors
    p = make_property(BoehmCalc.Sqrt, Rational{BigInt}(8))
    @test p.tag == BoehmCalc.Sqrt && p.arg == Rational{BigInt}(2)

    # Ln(1) = 0 (normalizes to One/zero)
    @test make_property(BoehmCalc.Ln, Rational{BigInt}(1)).tag == BoehmCalc.One

    # Independence: Pi vs Sqrt(2) are independent
    @test definitely_independent(Property(BoehmCalc.Pi, nothing),
                                  make_property(BoehmCalc.Sqrt, Rational{BigInt}(2)))
    # Same property is NOT independent
    @test !definitely_independent(Property(BoehmCalc.Pi, nothing),
                                   Property(BoehmCalc.Pi, nothing))
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Create src/property.jl**

This file is large because it carries the Lindemann–Weierstrass independence claims and the normalization rules from SPEC.md "Property (symbolic tag)".

```julia
"""
Symbolic tag for the `cr_factor` of an `ExactReal`.

  One         crFactor is exactly 1 (purely rational ExactReal)
  Pi          crFactor is π
  Sqrt        crFactor is √arg, with arg ∈ ℚ, arg > 0, arg ≠ perfect-square × ℚ
  Exp         crFactor is e^arg, with arg ∈ ℚ, arg ≠ 0
  Ln          crFactor is ln(arg), with arg ∈ ℚ, arg > 1, arg ≠ e^q
  Log         crFactor is log10(arg), with arg ∈ ℚ, arg > 0, arg not a power of 10
  SinPi       crFactor is sin(π·arg), with arg ∈ (0, 1/2) ∩ ℚ, arg ∉ {1/6, 1/4, 1/3}
  TanPi       crFactor is tan(π·arg), similar to SinPi
  Asin        crFactor is asin(arg), with arg ∈ (0, 1) ∩ ℚ, arg ≠ sin-of-rational-π-multiple
  Atan        crFactor is atan(arg), with arg ∈ ℚ, arg > 0, arg ≠ tan-of-rational-π-multiple
  Irrational  crFactor is known irrational; symbolic form lost (e.g. via Sum)
"""
@enum Tag::UInt8 begin
    One
    Pi
    Sqrt
    Exp
    Ln
    Log
    SinPi
    TanPi
    Asin
    Atan
    Irrational
end

struct Property
    tag::Tag
    arg::Union{Rational{BigInt}, Nothing}
    function Property(tag::Tag, arg::Union{Rational{BigInt}, Nothing})
        # Tags that don't take args: One, Pi, Irrational
        if tag in (One, Pi, Irrational)
            arg === nothing || throw(ArgumentError("$tag does not take an arg"))
        else
            arg === nothing && throw(ArgumentError("$tag requires an arg"))
        end
        return new(tag, arg)
    end
end

# Helper: extract perfect-square factor from a positive rational.
# Returns (sq_factor, remainder) such that input = sq_factor^2 * remainder
# and `remainder` is square-free (apart from possibly being 1).
function _extract_square(r::Rational{BigInt})
    n = numerator(r); d = denominator(r)
    n < 0 && return (Rational{BigInt}(1), r)
    # Find largest k with k^2 dividing n; same for d.
    k_n = BigInt(1); rem_n = n
    for p in 2:isqrt(BigInt(min(rem_n, 1_000_000)))
        while rem_n % (p * p) == 0
            k_n *= p
            rem_n ÷= p * p
        end
    end
    k_d = BigInt(1); rem_d = d
    for p in 2:isqrt(BigInt(min(rem_d, 1_000_000)))
        while rem_d % (p * p) == 0
            k_d *= p
            rem_d ÷= p * p
        end
    end
    return (Rational{BigInt}(k_n, k_d), Rational{BigInt}(rem_n, rem_d))
end

"""
Construct a Property with normalization. May return a different tag than asked
(e.g. `Sqrt(4)` normalizes to `One` because √4 = 2 is rational).
"""
function make_property(tag::Tag, arg)
    arg_r = arg === nothing ? nothing : convert(Rational{BigInt}, arg)
    if tag == One || tag == Pi || tag == Irrational
        return Property(tag, nothing)
    elseif tag == Sqrt
        arg_r > 0 || throw(DomainError(arg_r, "Sqrt requires positive arg"))
        sq, rem = _extract_square(arg_r)
        if isone(rem)
            return Property(One, nothing)             # rational result
        end
        return Property(Sqrt, rem)                    # store square-free arg
    elseif tag == Exp
        iszero(arg_r) && return Property(One, nothing)   # e^0 = 1
        return Property(Exp, arg_r)
    elseif tag == Ln
        arg_r > 0 || throw(DomainError(arg_r, "Ln requires positive arg"))
        isone(arg_r) && return Property(One, nothing)
        return Property(Ln, arg_r)
    elseif tag == Log
        arg_r > 0 || throw(DomainError(arg_r, "Log requires positive arg"))
        isone(arg_r) && return Property(One, nothing)
        return Property(Log, arg_r)
    elseif tag == SinPi
        # Reduce arg mod 2 into [0, 2); reflect into [-1/2, 1/2]; etc.
        # For brevity here, just store the arg verbatim and let arithmetic
        # caller pre-normalize.
        return Property(SinPi, arg_r)
    elseif tag == TanPi
        return Property(TanPi, arg_r)
    elseif tag == Asin
        # asin(0) = 0, asin(1/2) = π/6, asin(√2/2) = π/4 etc.
        # SPEC §5: keep asin(rational) as a symbolic form unless arg is an
        # easily-recognized special value.
        iszero(arg_r) && return Property(One, nothing)
        return Property(Asin, arg_r)
    elseif tag == Atan
        iszero(arg_r) && return Property(One, nothing)
        return Property(Atan, arg_r)
    end
    error("unhandled tag: $tag")
end

"""
Lindemann–Weierstrass-grade independence: does there exist a known proof that
`a` and `b` cannot be rational multiples of each other?

Conservative — when in doubt, returns false.
"""
function definitely_independent(a::Property, b::Property)
    a == b && return false
    # Algebraic vs transcendental
    is_transcendental(a) != is_transcendental(b) && return true
    # Same family with different args: usually independent (e.g. ln(2) and ln(3))
    a.tag == b.tag && a.arg != b.arg && a.tag in (Ln, Exp) && return true
    # Pi vs Sqrt-of-rational: π is transcendental, √r is algebraic
    (a.tag == Pi && b.tag == Sqrt) && return true
    (a.tag == Sqrt && b.tag == Pi) && return true
    return false
end

is_transcendental(p::Property) = p.tag in (Pi, Exp, Ln, Log, SinPi, TanPi, Asin, Atan)
```

Wire into module: `include("property.jl")` after `include("bounded.jl")`.

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/property.jl src/BoehmCalc.jl test/property_tests.jl
git commit -m "feat: Property tag enum, normalization, definitely_independent"
```

---

## Phase 6: ExactReal struct + basic constructors

### Task 6.1: ExactReal struct, Int/Rational constructors, predicates

**Files:**
- Create: `src/exact.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
# test/exact_tests.jl
using BoehmCalc
using BoehmCalc: ExactReal, is_rational, is_integer
using Test

@testset "ExactReal construction" begin
    a = ExactReal(0)
    @test iszero(a) && is_rational(a) && is_integer(a)

    b = ExactReal(3)
    @test isone(b / b)
    @test b == 3 && b == 3//1

    c = ExactReal(1//2)
    @test is_rational(c) && !is_integer(c)
    @test c + c == 1
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Create src/exact.jl**

```julia
struct ExactReal <: Real
    rat_factor::Rational{BigInt}
    cr_factor::CR
    prop::Property
    function ExactReal(rat_factor::Rational{BigInt}, cr_factor::CR, prop::Property)
        # If rat_factor is zero, normalize cr_factor and prop to One/IntCR(1)
        # so equality is trivial.
        if iszero(rat_factor)
            return new(rat_factor, _ONE_CR, _ONE_PROP)
        end
        return new(rat_factor, cr_factor, prop)
    end
end

# Shared singletons (created lazily after CR is loaded; here they're global consts).
const _ONE_CR   = IntCR(1)
const _ONE_PROP = Property(One, nothing)

# Constructors from Julia number types.
ExactReal(n::Integer)  = ExactReal(Rational{BigInt}(BigInt(n)), _ONE_CR, _ONE_PROP)
ExactReal(r::Rational) = ExactReal(Rational{BigInt}(numerator(r), denominator(r)), _ONE_CR, _ONE_PROP)

# Float64 / BigFloat convert to their EXACT binary value as a Rational{BigInt}.
function ExactReal(x::Float64)
    isfinite(x) || throw(DomainError(x, "ExactReal requires a finite value"))
    return ExactReal(Rational{BigInt}(x))
end
function ExactReal(x::BigFloat)
    isfinite(x) || throw(DomainError(x, "ExactReal requires a finite value"))
    return ExactReal(Rational{BigInt}(x))
end

# Predicates.
is_rational(x::ExactReal) = x.prop.tag == One
is_integer(x::ExactReal)  = is_rational(x) && isone(denominator(x.rat_factor))

Base.iszero(x::ExactReal) = iszero(x.rat_factor)
Base.isone(x::ExactReal)  = isone(x.rat_factor) && x.prop.tag == One
Base.isfinite(::ExactReal) = true
Base.isnan(::ExactReal)    = false
Base.isinf(::ExactReal)    = false
Base.zero(::Type{ExactReal}) = ExactReal(0)
Base.one(::Type{ExactReal})  = ExactReal(1)
```

Wire `include("exact.jl")` into `src/BoehmCalc.jl` after `include("property.jl")`. Export `ExactReal`, `is_rational`, `is_integer`.

- [ ] **Step 4: Run, PASS** (the `+`, `==`, `/` calls in the test depend on later tasks; for now mark those tests as broken or skip them and add as task-specific tests below).

If `+`/`==`/`/` are missing, the test will fail. Move those assertions to Tasks 7 & 8 below; for this task, keep just:

```julia
@testset "ExactReal construction" begin
    a = ExactReal(0)
    @test iszero(a) && is_rational(a) && is_integer(a)

    b = ExactReal(3)
    @test is_integer(b)

    c = ExactReal(1//2)
    @test is_rational(c) && !is_integer(c)
end
```

Run, PASS.

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl src/BoehmCalc.jl test/exact_tests.jl
git commit -m "feat: ExactReal struct + integer/rational constructors + predicates"
```

### Task 6.2: ExactReal constructors from Irrational{:π}, Irrational{:ℯ}

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "Irrational construction" begin
    p = ExactReal(π)
    @test p.prop.tag == BoehmCalc.Pi
    @test p.rat_factor == 1

    e = ExactReal(ℯ)
    @test e.prop.tag == BoehmCalc.Exp
    @test e.prop.arg == 1
    @test e.rat_factor == 1

    # Other irrationals fall back to BigFloat → Irrational tag.
    γ = ExactReal(Base.MathConstants.γ)
    @test γ.prop.tag == BoehmCalc.Irrational
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add to src/exact.jl**

```julia
const _PI_CR   = PiCR()
const _PI_PROP = Property(Pi, nothing)

ExactReal(::Irrational{:π}) = ExactReal(Rational{BigInt}(1), _PI_CR, _PI_PROP)

function ExactReal(::Irrational{:ℯ})
    e_prop = Property(Exp, Rational{BigInt}(1))
    e_cr   = ExpCR(IntCR(1))
    ExactReal(Rational{BigInt}(1), e_cr, e_prop)
end

# Other Irrational{S}: convert via BigFloat; tag as Irrational.
function ExactReal(x::Irrational)
    bf = setprecision(BigFloat, 256) do
        BigFloat(x)
    end
    rat = Rational{BigInt}(bf)
    # The rational representation is exact for the BigFloat we got, but only
    # approximate for the underlying transcendental. We tag it Irrational and
    # carry a CR backed by the BigFloat so arithmetic refines correctly.
    cr = BigFloatCR((_)->BigFloat(x), IntCR(0); extra_bits=64)
    ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat: ExactReal constructors from Irrational{:π}, Irrational{:ℯ}, others"
```

---

## Phase 7: ExactReal arithmetic

### Task 7.1: Negation

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "negation" begin
    @test -ExactReal(3) == ExactReal(-3)
    @test -(-ExactReal(5)) == ExactReal(5)
    @test (-ExactReal(π)).rat_factor == -1
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add**

```julia
Base.:(-)(x::ExactReal) = ExactReal(-x.rat_factor, x.cr_factor, x.prop)
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): negation"
```

(For brevity, subsequent arithmetic tasks follow the same pattern. Each task adds one operator, one test, one commit. The full algorithms — addition with same/different tags, multiplication with tag combination, division, power, sqrt, exp, log, sin/cos/tan, asin/acos/atan, factorial — are described in SPEC.md "Arithmetic dispatch" and "Public API". Translate from `UnifiedReal.java` source for the algorithms.)

### Task 7.2: Addition (same tag, different tags, with bound-overflow fallback)

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "addition" begin
    @test ExactReal(2) + ExactReal(3) == ExactReal(5)
    @test ExactReal(1//3) + ExactReal(2//3) == ExactReal(1)
    # Same Pi tag combines rat_factors
    @test (ExactReal(π) + ExactReal(π)).rat_factor == 2
    # 0 + π = π
    p = ExactReal(0) + ExactReal(π)
    @test p.prop.tag == BoehmCalc.Pi && p.rat_factor == 1
    # π - π = 0
    @test iszero(ExactReal(π) - ExactReal(π))
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add to src/exact.jl**

```julia
function Base.:(+)(a::ExactReal, b::ExactReal)
    iszero(a) && return b
    iszero(b) && return a

    # Both are pure rationals.
    if a.prop.tag == One && b.prop.tag == One
        sum_r = try_add(a.rat_factor, b.rat_factor)
        sum_r !== nothing && return ExactReal(sum_r, _ONE_CR, _ONE_PROP)
        # overflow → fall back to CR
        return ExactReal(Rational{BigInt}(1),
                         AddCR(_scale_cr(a.rat_factor, _ONE_CR),
                               _scale_cr(b.rat_factor, _ONE_CR)),
                         Property(Irrational, nothing))
    end

    # Same Property: combine rat_factors.
    if a.prop == b.prop
        sum_r = try_add(a.rat_factor, b.rat_factor)
        if sum_r !== nothing
            iszero(sum_r) && return ExactReal(0)
            return ExactReal(sum_r, a.cr_factor, a.prop)
        end
    end

    # One side is rational, other is symbolic: result has no tag.
    # Use the 3500-bit guard from SPEC.md before tagging Irrational.
    cr = AddCR(_scale_cr(a.rat_factor, a.cr_factor),
               _scale_cr(b.rat_factor, b.cr_factor))
    new_tag = _addition_tag(a, b)
    return ExactReal(Rational{BigInt}(1), cr, new_tag)
end

Base.:(-)(a::ExactReal, b::ExactReal) = a + (-b)

# Helpers
function _scale_cr(r::Rational{BigInt}, c::CR)
    isone(r) && return c
    n = numerator(r); d = denominator(r)
    base = isone(n) ? c : MulCR(IntCR(n), c)
    return isone(d) ? base : MulCR(InvCR(IntCR(d)), base)
end

function _addition_tag(a::ExactReal, b::ExactReal)
    # If both are big enough and definitely independent, tag as Irrational.
    if a.prop != _ONE_PROP && b.prop != _ONE_PROP &&
       definitely_independent(a.prop, b.prop) &&
       _magnitude_ge(a, -3500) && _magnitude_ge(b, -3500)
        return Property(Irrational, nothing)
    end
    # Otherwise drop the tag entirely (still a CR, but no symbolic claim).
    return Property(Irrational, nothing)   # conservative; refine in v1.x
end

# True iff |x| >= 2^p (cheap CR-level magnitude check).
function _magnitude_ge(x::ExactReal, p::Int)
    iszero(x) && return false
    a = get_approx(x.cr_factor, p)
    return abs(a) > 1
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): addition with tag combination + bound-overflow fallback"
```

### Task 7.3: Multiplication

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "multiplication" begin
    @test ExactReal(2) * ExactReal(3) == ExactReal(6)
    @test ExactReal(1//2) * ExactReal(1//3) == ExactReal(1//6)
    # √2 * √3 = √6
    s2 = sqrt(ExactReal(2)); s3 = sqrt(ExactReal(3))
    @test (s2 * s3) == sqrt(ExactReal(6))
    # √2 * √2 = 2
    @test s2 * s2 == ExactReal(2)
    # e^a * e^b = e^(a+b)
    e2 = exp(ExactReal(2)); e3 = exp(ExactReal(3))
    @test e2 * e3 == exp(ExactReal(5))
    # 0 * anything = 0
    @test iszero(ExactReal(0) * ExactReal(π))
end
```

- [ ] **Step 2: Run, FAIL** (sqrt and exp aren't yet defined; either keep just the rational cases for now and add the symbolic cases in their respective tasks, or stub sqrt/exp as `error("not yet implemented")` and let the test fail until those tasks land. Recommended: keep only rational cases here, add the symbolic ones in tasks 7.6/7.7).

- [ ] **Step 3: Implement multiplication**

```julia
function Base.:(*)(a::ExactReal, b::ExactReal)
    (iszero(a) || iszero(b)) && return ExactReal(0)
    rat = try_mul(a.rat_factor, b.rat_factor)
    if a.prop.tag == One && b.prop.tag == One && rat !== nothing
        return ExactReal(rat, _ONE_CR, _ONE_PROP)
    end
    if a.prop.tag == One && rat !== nothing
        return ExactReal(rat, b.cr_factor, b.prop)
    end
    if b.prop.tag == One && rat !== nothing
        return ExactReal(rat, a.cr_factor, a.prop)
    end
    # Both have symbolic factors. Combine tags where possible.
    new_prop, factor = _combine_tags_mul(a.prop, b.prop)
    if new_prop !== nothing && rat !== nothing
        new_rat = try_mul(rat, factor)
        new_rat !== nothing && return ExactReal(new_rat, _cr_for(new_prop), new_prop)
    end
    # Fallback: raw CR product, no tag.
    cr = MulCR(_scale_cr(a.rat_factor, a.cr_factor),
               _scale_cr(b.rat_factor, b.cr_factor))
    return ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

# (tag_a, tag_b) → (combined_tag, extra_rational_factor) or (nothing, nothing).
# Cases handled (paper §6, UnifiedReal.multiply):
#   √a * √b = √(ab) when ab is a square-free rational
#   e^a * e^b = e^(a+b)
#   π * π → no symbolic combination
function _combine_tags_mul(a::Property, b::Property)
    if a.tag == Sqrt && b.tag == Sqrt
        prod = try_mul(a.arg, b.arg)
        prod === nothing && return (nothing, nothing)
        new_prop = make_property(Sqrt, prod)
        # √a * √b = √(ab); the square-extraction in make_property may yield a rational factor
        return (new_prop, Rational{BigInt}(1))
    elseif a.tag == Exp && b.tag == Exp
        sum_arg = try_add(a.arg, b.arg)
        sum_arg === nothing && return (nothing, nothing)
        new_prop = make_property(Exp, sum_arg)
        return (new_prop, Rational{BigInt}(1))
    end
    return (nothing, nothing)
end

# Construct the CR for a property's normal form.
function _cr_for(prop::Property)
    prop.tag == One        && return _ONE_CR
    prop.tag == Pi         && return _PI_CR
    prop.tag == Sqrt       && return SqrtCR(_rational_cr(prop.arg))
    prop.tag == Exp        && return ExpCR(_rational_cr(prop.arg))
    prop.tag == Ln         && return LnCR(_rational_cr(prop.arg))
    prop.tag == SinPi      && return BigFloatCR(sin, MulCR(_PI_CR, _rational_cr(prop.arg)))
    prop.tag == TanPi      && return BigFloatCR(tan, MulCR(_PI_CR, _rational_cr(prop.arg)))
    prop.tag == Atan       && return AtanCR(_rational_cr(prop.arg))
    prop.tag == Asin       && return AsinCR(_rational_cr(prop.arg))
    prop.tag == Irrational && return _ONE_CR     # caller must supply real cr_factor
    prop.tag == Log        && return MulCR(InvCR(LnCR(IntCR(10))), LnCR(_rational_cr(prop.arg)))
    error("unhandled tag in _cr_for: $(prop.tag)")
end

_rational_cr(r::Rational{BigInt}) = isone(denominator(r)) ?
    IntCR(numerator(r)) :
    MulCR(IntCR(numerator(r)), InvCR(IntCR(denominator(r))))
```

(Note: `_cr_for(Sqrt)` above is naive; refine it for non-integer arg in a follow-up task — see 7.6.)

- [ ] **Step 4: Run, PASS** (rational cases pass; symbolic cases still fail until later tasks).

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): multiplication with tag combination (Sqrt*Sqrt, Exp*Exp)"
```

### Task 7.4: Inversion and division

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "division" begin
    @test ExactReal(6) / ExactReal(3) == ExactReal(2)
    @test ExactReal(1) / ExactReal(3) == ExactReal(1//3)
    # 1/π is Pi-tagged with rat_factor 1
    inv_pi = ExactReal(1) / ExactReal(π)
    @test inv_pi.prop.tag == BoehmCalc.Pi
    @test inv_pi.rat_factor != ExactReal(π).rat_factor   # different
    @test inv(ExactReal(2)) == ExactReal(1//2)
    @test_throws DomainError ExactReal(1) / ExactReal(0)
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add inversion + division**

```julia
function Base.inv(x::ExactReal)
    iszero(x) && throw(DivideError())
    if x.prop.tag == One
        return ExactReal(inv(x.rat_factor))
    end
    # 1 / (rat * cr) = (1/rat) / cr = (1/rat) * (1/cr).
    # For tagged forms, the inverse is in the same family up to constants
    # (e.g. 1/π is still tagged Pi with rat_factor 1/π — but rat_factor is
    # rational, so this needs the irrational-tag fallback unless we have the
    # "Pi" tag itself absorbing the inversion).
    inv_rat = inv(x.rat_factor)
    return ExactReal(inv_rat, InvCR(x.cr_factor), x.prop)
end

Base.:(/)(a::ExactReal, b::ExactReal) = a * inv(b)
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): inversion + division"
```

### Task 7.5: Power (Int, Rational, ExactReal exponents)

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "power" begin
    @test ExactReal(2) ^ 10 == ExactReal(1024)
    @test ExactReal(1//2) ^ 3 == ExactReal(1//8)
    @test ExactReal(4) ^ (1//2) == ExactReal(2)
    @test ExactReal(8) ^ (1//3) == ExactReal(2)
    # Real exponent: a^b = exp(b * log(a))
    e_squared = ExactReal(ℯ) ^ ExactReal(2)
    @test e_squared == exp(ExactReal(2))
    # Negative base, integer exponent
    @test ExactReal(-2) ^ 3 == ExactReal(-8)
    # 0^0 = 1 by convention
    @test ExactReal(0) ^ 0 == ExactReal(1)
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add power dispatch**

```julia
function Base.:(^)(a::ExactReal, n::Integer)
    n == 0 && return ExactReal(1)
    n > 0 && return _pow_pos_int(a, n)
    return inv(_pow_pos_int(a, -n))
end

function _pow_pos_int(a::ExactReal, n::Integer)
    if a.prop.tag == One
        r = try_pow(a.rat_factor, n)
        r !== nothing && return ExactReal(r)
    end
    # Naive: (rat^n) * (cr^n). cr^n is built as repeated multiplication.
    rat_n = try_pow(a.rat_factor, n)
    cr_n = a.cr_factor
    for _ in 2:n
        cr_n = MulCR(cr_n, a.cr_factor)
    end
    if rat_n !== nothing && a.prop.tag == Sqrt && iseven(n)
        # (k * √r)^n where n is even: rational result if r^(n/2) doesn't overflow
        sq = try_pow(a.prop.arg, n ÷ 2)
        sq !== nothing && return ExactReal(rat_n * sq)
    end
    return ExactReal(rat_n === nothing ? Rational{BigInt}(1) : rat_n,
                     cr_n, Property(Irrational, nothing))
end

function Base.:(^)(a::ExactReal, r::Rational)
    iszero(a) && r > 0 && return ExactReal(0)
    iszero(a) && throw(DomainError(0, "0^non-positive is undefined"))
    # a^(p/q) = (a^p)^(1/q)
    p = numerator(r); q = denominator(r)
    a_p = a ^ p
    return _root(a_p, q)
end

function _root(a::ExactReal, q::Integer)
    q == 1 && return a
    q == 2 && return sqrt(a)
    a > 0 || throw(DomainError(a, "real root of non-positive base"))
    # General case: e^(log(a)/q)
    return exp(log(a) / ExactReal(q))
end

function Base.:(^)(a::ExactReal, b::ExactReal)
    is_integer(b) && return a ^ Integer(numerator(b.rat_factor))
    is_rational(b) && return a ^ b.rat_factor
    a > 0 || throw(DomainError(a, "non-positive base with non-rational exponent"))
    return exp(b * log(a))
end
```

- [ ] **Step 4: Run, PASS** (depends on `sqrt`, `exp`, `log` being defined; if not yet, mark these tests as skip-for-now and revisit after Phase 7.6/7.7).

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): integer/rational/real power"
```

### Task 7.6: sqrt with Sqrt tag and rational extraction

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "sqrt" begin
    @test sqrt(ExactReal(0)) == ExactReal(0)
    @test sqrt(ExactReal(4)) == ExactReal(2)
    @test sqrt(ExactReal(9//4)) == ExactReal(3//2)
    s2 = sqrt(ExactReal(2))
    @test s2.prop.tag == BoehmCalc.Sqrt
    @test s2 * s2 == ExactReal(2)
    @test sqrt(ExactReal(8)) == 2 * sqrt(ExactReal(2))
    @test_throws DomainError sqrt(ExactReal(-1))
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add `sqrt`**

```julia
function Base.sqrt(x::ExactReal)
    iszero(x) && return ExactReal(0)
    x < 0 && throw(DomainError(x, "sqrt of negative"))
    if x.prop.tag == One
        # Pure rational; check perfect square first.
        ex = try_sqrt_exact(x.rat_factor)
        ex !== nothing && return ExactReal(ex)
        # √r where r is rational, r > 0, not a perfect square: build Sqrt-tagged.
        sq, rem = _extract_square(x.rat_factor)
        sqrt_prop = Property(Sqrt, rem)
        sqrt_cr   = SqrtCR(_rational_cr(rem))
        return ExactReal(sq, sqrt_cr, sqrt_prop)
    end
    # Symbolic input: fall back to CR-only.
    return ExactReal(Rational{BigInt}(1),
                     SqrtCR(_scale_cr(x.rat_factor, x.cr_factor)),
                     Property(Irrational, nothing))
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): sqrt with Sqrt tag + perfect-square + square-extraction"
```

### Task 7.7: exp / log / log10

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
@testset "exp/log" begin
    @test exp(ExactReal(0)) == ExactReal(1)
    @test exp(ExactReal(1)) == ExactReal(ℯ)
    @test log(ExactReal(1)) == ExactReal(0)
    @test log(ExactReal(ℯ)) == ExactReal(1)
    @test log(exp(ExactReal(2))) == ExactReal(2)
    @test log10(ExactReal(100)) == ExactReal(2)
    @test_throws DomainError log(ExactReal(0))
    @test_throws DomainError log(ExactReal(-1))
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add `exp`, `log`, `log10`**

```julia
function Base.exp(x::ExactReal)
    iszero(x) && return ExactReal(1)
    if x.prop.tag == One
        # exp(rational): symbolic Exp tag.
        prop = make_property(Exp, x.rat_factor)
        prop.tag == One && return ExactReal(1)
        cr = ExpCR(_rational_cr(x.rat_factor))
        return ExactReal(Rational{BigInt}(1), cr, prop)
    end
    # Symbolic input: fall back.
    cr = ExpCR(_scale_cr(x.rat_factor, x.cr_factor))
    return ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

function Base.log(x::ExactReal)
    !(x > 0) && throw(DomainError(x, "log of non-positive"))
    isone(x) && return ExactReal(0)
    if x.prop.tag == One
        # log(rational > 0): Ln tag (which requires arg > 1 — flip first if needed).
        if x.rat_factor < 1
            return -log(ExactReal(inv(x.rat_factor)))
        end
        prop = make_property(Ln, x.rat_factor)
        prop.tag == One && return ExactReal(0)
        cr = LnCR(_rational_cr(x.rat_factor))
        return ExactReal(Rational{BigInt}(1), cr, prop)
    end
    # log(rat * cr) — generic CR fallback, no symbolic tag.
    return ExactReal(Rational{BigInt}(1),
                     LnCR(_scale_cr(x.rat_factor, x.cr_factor)),
                     Property(Irrational, nothing))
end

Base.log10(x::ExactReal) = log(x) / log(ExactReal(10))

# 2-arg log
Base.log(b::ExactReal, x::ExactReal) = log(x) / log(b)
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): exp / log / log10 with Exp/Ln tags"
```

### Task 7.8: sin / cos / tan

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
@testset "trig" begin
    @test sin(ExactReal(0)) == ExactReal(0)
    @test cos(ExactReal(0)) == ExactReal(1)
    @test tan(ExactReal(0)) == ExactReal(0)

    # Special values that simplify symbolically (these depend on SinPi tag normalization)
    @test sin(ExactReal(π) / ExactReal(6)) == ExactReal(1//2)
    @test cos(ExactReal(π) / ExactReal(2)) == ExactReal(0)
    @test sin(ExactReal(π)) == ExactReal(0)
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add `sin`, `cos`, `tan`**

The implementation builds on Boehm's `UnifiedReal.sin`, which:
1. Detects rational multiples of π exactly (via `arg / π`).
2. Reduces the rational into a small set of canonical representatives.
3. Returns the exact value (`0`, `±1//2`, `±√3//2`, `±1`, …) when known.
4. Falls back to a `SinCR` (built from `cos` via shift) for irrational arguments.

Translate from `UnifiedReal.java` `sin()` / `cos()` (around line 800 in the AOSP source).

```julia
# Helper: extract `arg / π` if the input is a rational multiple of π.
function _as_pi_multiple(x::ExactReal)::Union{Rational{BigInt}, Nothing}
    if x.prop.tag == Pi && x.cr_factor === _PI_CR
        return x.rat_factor
    end
    return nothing
end

function Base.sin(x::ExactReal)
    iszero(x) && return ExactReal(0)
    pi_mult = _as_pi_multiple(x)
    if pi_mult !== nothing
        return _sin_pi_rational(pi_mult)
    end
    # Generic: sin(x) = cos(x - π/2)
    halfpi = ExactReal(π) / ExactReal(2)
    return cos(x - halfpi)
end

function Base.cos(x::ExactReal)
    iszero(x) && return ExactReal(1)
    pi_mult = _as_pi_multiple(x)
    if pi_mult !== nothing
        return _cos_pi_rational(pi_mult)
    end
    # Generic: build a CosCR.
    cr = CosCR(_scale_cr(x.rat_factor, x.cr_factor))
    return ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

Base.tan(x::ExactReal) = sin(x) / cos(x)

# sin(π · q) for rational q. Reduces q mod 2 and uses canonical values.
function _sin_pi_rational(q::Rational{BigInt})
    q_red = q - 2 * floor(q / 2)         # bring into [0, 2)
    if q_red >= 1
        return -_sin_pi_rational(q_red - 1)   # sin(π(q+1)) = -sin(πq)
    end
    if q_red > 1//2
        return _sin_pi_rational(1 - q_red)    # sin(π(1-q)) = sin(πq)
    end
    # q_red ∈ [0, 1/2]
    iszero(q_red)        && return ExactReal(0)
    q_red == 1//6        && return ExactReal(1//2)
    q_red == 1//4        && return sqrt(ExactReal(2)) / ExactReal(2)
    q_red == 1//3        && return sqrt(ExactReal(3)) / ExactReal(2)
    q_red == 1//2        && return ExactReal(1)
    # Generic: sin(πq) is irrational; build SinPi-tagged.
    prop = make_property(SinPi, q_red)
    cr   = BigFloatCR(sin, MulCR(_PI_CR, _rational_cr(q_red)))
    return ExactReal(Rational{BigInt}(1), cr, prop)
end

# cos(πq) = sin(π(q + 1/2))
_cos_pi_rational(q::Rational{BigInt}) = _sin_pi_rational(q + 1//2)
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): sin/cos/tan with rational-π-multiple shortcuts"
```

### Task 7.9: asin / acos / atan / atan2

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
@testset "inverse trig" begin
    @test asin(ExactReal(0)) == ExactReal(0)
    @test asin(ExactReal(1)) == ExactReal(π) / ExactReal(2)
    @test asin(ExactReal(1//2)) == ExactReal(π) / ExactReal(6)
    @test atan(ExactReal(0)) == ExactReal(0)
    @test atan(ExactReal(1)) == ExactReal(π) / ExactReal(4)
    @test acos(ExactReal(0)) == ExactReal(π) / ExactReal(2)
    # asin(sin(x)) == x for small rational x
    @test asin(sin(ExactReal(π) / ExactReal(6))) == ExactReal(π) / ExactReal(6)
    @test_throws DomainError asin(ExactReal(2))
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add `asin`, `acos`, `atan`, `atan(y, x)`**

```julia
function Base.asin(x::ExactReal)
    iszero(x) && return ExactReal(0)
    abs(x) > 1 && throw(DomainError(x, "asin domain"))
    if x.prop.tag == One
        # Special rational arguments
        x.rat_factor == 1//2  && return ExactReal(π) / ExactReal(6)
        x.rat_factor == -1//2 && return -(ExactReal(π) / ExactReal(6))
        x.rat_factor == 1     && return ExactReal(π) / ExactReal(2)
        x.rat_factor == -1    && return -(ExactReal(π) / ExactReal(2))
        # asin of √2/2, √3/2 require x.prop.tag == Sqrt; punt for v1.
        prop = make_property(Asin, x.rat_factor)
        prop.tag == One && return ExactReal(0)
        cr = AsinCR(_rational_cr(x.rat_factor))
        return ExactReal(Rational{BigInt}(1), cr, prop)
    end
    # Symbolic input: fall back.
    cr = AsinCR(_scale_cr(x.rat_factor, x.cr_factor))
    return ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

Base.acos(x::ExactReal) = ExactReal(π) / ExactReal(2) - asin(x)

function Base.atan(x::ExactReal)
    iszero(x) && return ExactReal(0)
    if x.prop.tag == One
        x.rat_factor == 1     && return ExactReal(π) / ExactReal(4)
        x.rat_factor == -1    && return -(ExactReal(π) / ExactReal(4))
        prop = make_property(Atan, x.rat_factor)
        prop.tag == One && return ExactReal(0)
        cr = AtanCR(_rational_cr(x.rat_factor))
        return ExactReal(Rational{BigInt}(1), cr, prop)
    end
    cr = AtanCR(_scale_cr(x.rat_factor, x.cr_factor))
    return ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

function Base.atan(y::ExactReal, x::ExactReal)
    iszero(y) && iszero(x) && return ExactReal(0)
    iszero(x) && return (y > 0 ? ExactReal(π) / ExactReal(2) : -(ExactReal(π) / ExactReal(2)))
    base = atan(y / x)
    x > 0 && return base
    y >= 0 && return base + ExactReal(π)
    return base - ExactReal(π)
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): asin/acos/atan/atan2"
```

### Task 7.10: factorial, abs, sign

**Files:**
- Modify: `src/exact.jl`
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
@testset "factorial / abs / sign" begin
    @test factorial(ExactReal(0)) == ExactReal(1)
    @test factorial(ExactReal(5)) == ExactReal(120)
    @test_throws DomainError factorial(ExactReal(-1))
    @test_throws DomainError factorial(ExactReal(1//2))

    @test abs(ExactReal(-3)) == ExactReal(3)
    @test abs(ExactReal(3)) == ExactReal(3)
    @test sign(ExactReal(5)) == ExactReal(1)
    @test sign(ExactReal(-5)) == ExactReal(-1)
    @test iszero(sign(ExactReal(0)))
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add**

```julia
function Base.factorial(x::ExactReal)
    is_integer(x) || throw(DomainError(x, "factorial requires non-negative integer"))
    n = numerator(x.rat_factor)
    n < 0 && throw(DomainError(x, "factorial of negative"))
    return ExactReal(factorial(BigInt(n)))
end

function Base.abs(x::ExactReal)
    iszero(x) && return x
    x.rat_factor < 0 ? -x : x
end

function Base.sign(x::ExactReal)
    iszero(x) && return ExactReal(0)
    return x.rat_factor < 0 ? ExactReal(-1) : ExactReal(1)
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/exact.jl test/exact_tests.jl
git commit -m "feat(exact): factorial, abs, sign"
```

---

## Phase 8: Comparison and hashing

### Task 8.1: is_comparable + ==

**Files:**
- Create: `src/compare.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/compare_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
# test/compare_tests.jl
using BoehmCalc
using BoehmCalc: ExactReal, is_comparable, definitely_equal
using Test

@testset "comparison" begin
    @testset "==" begin
        @test ExactReal(2) == ExactReal(2)
        @test ExactReal(1//3) == ExactReal(1//3)
        @test ExactReal(π) == ExactReal(π)
        @test sqrt(ExactReal(2)) * sqrt(ExactReal(2)) == ExactReal(2)
        @test ExactReal(π) - ExactReal(π) == ExactReal(0)
        # Different values
        @test ExactReal(2) != ExactReal(3)
        @test ExactReal(π) != ExactReal(3)
    end

    @testset "is_comparable" begin
        @test is_comparable(ExactReal(2), ExactReal(3))
        @test is_comparable(ExactReal(0), ExactReal(0))
        @test is_comparable(ExactReal(π), ExactReal(π))
        @test is_comparable(ExactReal(π), sqrt(ExactReal(2)))
        @test is_comparable(ExactReal(π), ExactReal(1))
    end
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Create src/compare.jl**

```julia
function is_comparable(a::ExactReal, b::ExactReal)
    iszero(a) && iszero(b) && return true
    # Same Property (and same arg): comparable via rat_factor.
    a.prop == b.prop && return true
    # Both Sqrt: comparable via squares.
    a.prop.tag == Sqrt && b.prop.tag == Sqrt && return true
    # Both Pi: same Property; covered above.
    # Independent properties + magnitude floor.
    if definitely_independent(a.prop, b.prop)
        if _magnitude_ge(a, -5000) || _magnitude_ge(b, -5000) || iszero(a) || iszero(b)
            return true
        end
    end
    # Cheap approximate disambiguation.
    diff = (a - b).cr_factor
    delta = get_approx(diff, -100)
    abs(delta) > 2 && return true
    return false
end

function definitely_equal(a::ExactReal, b::ExactReal)
    is_comparable(a, b) || return false
    return _exact_equal(a, b)
end

function _exact_equal(a::ExactReal, b::ExactReal)
    iszero(a) && iszero(b) && return true
    if a.prop == b.prop
        return a.rat_factor == b.rat_factor
    end
    if a.prop.tag == Sqrt && b.prop.tag == Sqrt
        # √ args differ but rat_factors might compensate, e.g. 2*√3 == 6/√3
        # Compare squares: rat_factor^2 * arg
        sq_a = a.rat_factor^2 * a.prop.arg
        sq_b = b.rat_factor^2 * b.prop.arg
        # Sign also has to match (since rat_factor signs)
        sign_a = sign(a.rat_factor); sign_b = sign(b.rat_factor)
        return sq_a == sq_b && sign_a == sign_b
    end
    # Independent properties — by definition not equal unless both zero.
    return false
end

Base.:(==)(a::ExactReal, b::ExactReal) = definitely_equal(a, b)
```

Wire `include("compare.jl")` after `include("exact.jl")` in src/BoehmCalc.jl. Export `is_comparable`, `definitely_equal`.

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/compare.jl src/BoehmCalc.jl test/compare_tests.jl
git commit -m "feat(compare): is_comparable + ==/definitely_equal"
```

### Task 8.2: isless / < with deterministic tiebreak

**Files:**
- Modify: `src/compare.jl`
- Modify: `test/compare_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
@testset "isless" begin
    @test ExactReal(2) < ExactReal(3)
    @test !(ExactReal(3) < ExactReal(2))
    @test sqrt(ExactReal(2)) < ExactReal(2)
    @test ExactReal(0) < ExactReal(π)
    # Total order: sort works
    sorted = sort([ExactReal(π), ExactReal(2), ExactReal(0)])
    @test sorted == [ExactReal(0), ExactReal(2), ExactReal(π)]
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add**

```julia
function Base.isless(a::ExactReal, b::ExactReal)
    if is_comparable(a, b)
        return _exact_less(a, b)
    end
    # Approximate fallback at -100 bits.
    diff = (a - b).cr_factor
    delta = get_approx(diff, -100)
    delta < -1 && return true
    delta >  1 && return false
    return objectid(a) < objectid(b)   # deterministic tiebreak
end

function _exact_less(a::ExactReal, b::ExactReal)
    iszero(a) && iszero(b) && return false
    # Reduce to comparing approximate values where rat_factor sign + cr_factor sign agree.
    delta = get_approx((a - b).cr_factor, -64)
    return delta < 0
end

# Override < to ensure isless path (Base default delegates to isless for Real).
function definitely_less(a::ExactReal, b::ExactReal)::Union{Bool, Missing}
    is_comparable(a, b) || return missing
    return _exact_less(a, b)
end
```

Export `definitely_less`.

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/compare.jl test/compare_tests.jl
git commit -m "feat(compare): isless with deterministic objectid tiebreak"
```

### Task 8.3: Base.decompose for hashing

**Files:**
- Modify: `src/compare.jl`
- Modify: `test/compare_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
@testset "hashing via decompose" begin
    # Rational ExactReals hash identically to their Rational/Float64/BigFloat counterparts.
    @test hash(ExactReal(1//3)) == hash(1//3)
    @test hash(ExactReal(0.5)) == hash(0.5)
    @test hash(ExactReal(2)) == hash(2)
    # ExactReal(π) hashes the same as π
    @test hash(ExactReal(π)) == hash(π)
    @test hash(ExactReal(ℯ)) == hash(ℯ)
    # Set/Dict integration
    s = Set{Real}([1, ExactReal(1)])
    @test length(s) == 1
    d = Dict{Real,Int}(1//3 => 7)
    @test d[ExactReal(1//3)] == 7
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add**

```julia
function Base.decompose(x::ExactReal)::Tuple{BigInt, Int, BigInt}
    if is_rational(x)
        return (numerator(x.rat_factor), 0, denominator(x.rat_factor))
    end
    # Irrational case: fall through to Float64 decompose. Mirrors how Base
    # handles Irrational. Hash collisions with Float64 approximations are
    # accepted (correctness preserved by ==).
    return Base.decompose(Float64(x))
end
```

(The conversion `Float64(::ExactReal)` is added in Task 9.2; if not yet defined, this test fails until then. Reorder if needed.)

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/compare.jl test/compare_tests.jl
git commit -m "feat(compare): Base.decompose for cross-type hashing"
```

---

## Phase 9: Conversion and promotion

### Task 9.1: promote_rule + convert from Julia number types

**Files:**
- Create: `src/convert.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/convert_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
# test/convert_tests.jl
using BoehmCalc
using Test

@testset "convert + promote" begin
    # Promotion of mixed expressions
    @test 1 + ExactReal(π) isa ExactReal
    @test ExactReal(2) + 0.5 isa ExactReal
    @test 1//3 + ExactReal(1) isa ExactReal

    # Conversion preserves exact value
    @test ExactReal(0.1) == convert(ExactReal, 0.1)
    @test ExactReal(0.1) != ExactReal(1//10)         # Float64 0.1 != 1/10 exactly

    # Conversions out
    @test Float64(ExactReal(1//4)) == 0.25
    @test Float64(ExactReal(π)) ≈ Float64(π)
    @test Rational{BigInt}(ExactReal(3//7)) == 3//7
    @test_throws InexactError Rational{BigInt}(ExactReal(π))
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Create src/convert.jl**

```julia
Base.promote_rule(::Type{ExactReal}, ::Type{<:Integer}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{<:Rational}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{Float16}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{Float32}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{Float64}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{BigFloat}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{<:Irrational}) = ExactReal

Base.convert(::Type{ExactReal}, x::Integer)  = ExactReal(x)
Base.convert(::Type{ExactReal}, x::Rational) = ExactReal(x)
Base.convert(::Type{ExactReal}, x::AbstractFloat) = ExactReal(x)
Base.convert(::Type{ExactReal}, x::Irrational)    = ExactReal(x)
```

Wire `include("convert.jl")` after `include("compare.jl")`.

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/convert.jl src/BoehmCalc.jl test/convert_tests.jl
git commit -m "feat: promote_rule + convert from Julia number tower"
```

### Task 9.2: Conversion out (Float64, BigFloat, Rational, BigInt)

**Files:**
- Modify: `src/convert.jl`
- Modify: `test/convert_tests.jl`

- [ ] **Step 1: Add failing test (already partially in 9.1; add edge cases)**

```julia
@testset "conversion out" begin
    @test Float64(ExactReal(0)) == 0.0
    @test Float64(ExactReal(1//4)) == 0.25
    @test Float64(ExactReal(π)) === Float64(π)
    bf = BigFloat(ExactReal(π); precision=128)
    @test BigFloat(π; precision=128) - bf < BigFloat(2)^-127

    @test Rational{BigInt}(ExactReal(0)) == 0//1
    @test Rational{BigInt}(ExactReal(3//7)) == 3//7
    @test_throws InexactError Rational{BigInt}(ExactReal(π))

    @test BigInt(ExactReal(42)) == 42
    @test_throws InexactError BigInt(ExactReal(1//2))
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add to src/convert.jl**

```julia
function Base.Float64(x::ExactReal)
    bf = BigFloat(x; precision=53)
    return Float64(bf)
end

function Base.BigFloat(x::ExactReal; precision::Integer = precision(BigFloat))
    setprecision(BigFloat, precision) do
        if is_rational(x)
            return BigFloat(x.rat_factor)
        end
        # Evaluate the CR at scaled precision.
        a = get_approx(x.cr_factor, -Int(precision) - 4)
        scaled = BigFloat(a) * BigFloat(2.0)^(-Int(precision) - 4)
        return BigFloat(x.rat_factor) * scaled
    end
end

function Base.Rational{BigInt}(x::ExactReal)
    is_rational(x) || throw(InexactError(:Rational, Rational{BigInt}, x))
    return x.rat_factor
end

function Base.BigInt(x::ExactReal)
    is_integer(x) || throw(InexactError(:BigInt, BigInt, x))
    return numerator(x.rat_factor)
end

# Standard conversions to other Float types
Base.Float32(x::ExactReal) = Float32(Float64(x))
Base.Float16(x::ExactReal) = Float16(Float64(x))
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/convert.jl test/convert_tests.jl
git commit -m "feat: Float64/BigFloat/Rational{BigInt}/BigInt conversion from ExactReal"
```

---

## Phase 10: Display

### Task 10.1: Symbolic-aware show with decimal fallback

**Files:**
- Create: `src/show.jl`
- Modify: `src/BoehmCalc.jl`
- Modify: `test/show_tests.jl`

- [ ] **Step 1: Add failing tests**

```julia
# test/show_tests.jl
using BoehmCalc
using Test

@testset "show" begin
    @test sprint(show, ExactReal(1)) == "1"
    @test sprint(show, ExactReal(1//2)) == "1//2"
    @test sprint(show, ExactReal(0)) == "0"
    @test sprint(show, ExactReal(π)) == "π"
    @test sprint(show, ExactReal(2) * ExactReal(π)) == "2π"
    @test sprint(show, ExactReal(π) / ExactReal(4)) == "π/4"
    @test sprint(show, ExactReal(ℯ)) == "ℯ"
    @test sprint(show, sqrt(ExactReal(2))) == "√2"
    @test sprint(show, ExactReal(2) * sqrt(ExactReal(3))) == "2√3"

    # Decimal fallback for opaque values
    s = sprint(show, ExactReal(π) + sqrt(ExactReal(2)))
    @test occursin("…", s) || occursin(".", s)   # truncated decimal
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Create src/show.jl**

```julia
function Base.show(io::IO, x::ExactReal)
    if is_rational(x)
        return show(io, x.rat_factor.num // x.rat_factor.den == x.rat_factor.num ?
                    numerator(x.rat_factor) : x.rat_factor)
    end
    # Symbolic-aware
    s = _symbolic_string(x)
    if s !== nothing
        print(io, s)
    else
        print(io, _truncated_decimal(x, 15))
    end
end

function _symbolic_string(x::ExactReal)::Union{String, Nothing}
    iszero(x) && return "0"
    if x.prop.tag == Pi
        return _wrap_rational(x.rat_factor, "π")
    elseif x.prop.tag == Exp && x.prop.arg == 1 && isone(x.rat_factor)
        return "ℯ"
    elseif x.prop.tag == Sqrt
        # k * √arg
        rf = x.rat_factor
        sym = "√" * _arg_string(x.prop.arg)
        return _wrap_rational(rf, sym)
    elseif x.prop.tag == Exp && isone(x.rat_factor)
        return "ℯ^" * _arg_string(x.prop.arg)
    elseif x.prop.tag == Ln && isone(x.rat_factor)
        return "ln(" * _arg_string(x.prop.arg) * ")"
    end
    return nothing
end

function _wrap_rational(r::Rational{BigInt}, sym::AbstractString)
    isone(r)            && return sym
    r == -1             && return "-" * sym
    n = numerator(r); d = denominator(r)
    if isone(d)
        return string(n) * sym
    elseif n == 1
        return sym * "/" * string(d)
    elseif n == -1
        return "-" * sym * "/" * string(d)
    end
    return string(n) * sym * "/" * string(d)
end

function _arg_string(r::Rational{BigInt})
    isone(denominator(r)) && return string(numerator(r))
    return "(" * string(numerator(r)) * "/" * string(denominator(r)) * ")"
end

function _truncated_decimal(x::ExactReal, sig_digits::Int)
    bf = BigFloat(x; precision=ceil(Int, sig_digits * log2(10)) + 16)
    s = string(bf)
    # Truncate to sig_digits + add ellipsis if more digits exist.
    dot = findfirst('.', s)
    if dot === nothing
        return s
    end
    if length(s) > sig_digits + 1
        return s[1:sig_digits+1] * "…"
    end
    return s
end

# 3-arg show: more verbose
function Base.show(io::IO, ::MIME"text/plain", x::ExactReal)
    s = _symbolic_string(x)
    if s === nothing || is_rational(x)
        show(io, x)
    else
        print(io, s, " ≈ ", _truncated_decimal(x, 15))
    end
end
```

Wire `include("show.jl")` after `include("convert.jl")`.

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/show.jl src/BoehmCalc.jl test/show_tests.jl
git commit -m "feat: symbolic-aware show with decimal fallback"
```

### Task 10.2: text/latex MIME

**Files:**
- Modify: `src/show.jl`
- Modify: `test/show_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "text/latex" begin
    @test sprint(show, MIME"text/latex"(), ExactReal(π)) == "\$\\pi\$"
    @test sprint(show, MIME"text/latex"(), sqrt(ExactReal(2))) == "\$\\sqrt{2}\$"
    @test sprint(show, MIME"text/latex"(), ExactReal(π) / ExactReal(4)) == "\$\\frac{\\pi}{4}\$"
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add**

```julia
function Base.show(io::IO, ::MIME"text/latex", x::ExactReal)
    print(io, "\$", _latex_string(x), "\$")
end

function _latex_string(x::ExactReal)
    if is_rational(x)
        n = numerator(x.rat_factor); d = denominator(x.rat_factor)
        isone(d) && return string(n)
        return "\\frac{" * string(n) * "}{" * string(d) * "}"
    elseif x.prop.tag == Pi
        return _latex_wrap_rat(x.rat_factor, "\\pi")
    elseif x.prop.tag == Sqrt
        sym = "\\sqrt{" * _arg_string(x.prop.arg) * "}"
        return _latex_wrap_rat(x.rat_factor, sym)
    elseif x.prop.tag == Exp && x.prop.arg == 1 && isone(x.rat_factor)
        return "e"
    end
    return _truncated_decimal(x, 15)
end

function _latex_wrap_rat(r::Rational{BigInt}, sym::AbstractString)
    isone(r) && return sym
    r == -1  && return "-" * sym
    n = numerator(r); d = denominator(r)
    isone(d) && return string(n) * sym
    n == 1  && return "\\frac{" * sym * "}{" * string(d) * "}"
    return "\\frac{" * string(n) * sym * "}{" * string(d) * "}"
end
```

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/show.jl test/show_tests.jl
git commit -m "feat(show): text/latex MIME for Pluto/Jupyter"
```

### Task 10.3: string(x; digits=N)

**Files:**
- Modify: `src/show.jl`
- Modify: `test/show_tests.jl`

- [ ] **Step 1: Add failing test**

```julia
@testset "string with digits" begin
    @test BoehmCalc.string_decimal(ExactReal(π); digits=5)[1:5] == "3.141"
    @test startswith(BoehmCalc.string_decimal(ExactReal(1//3); digits=10), "0.333333333")
end
```

- [ ] **Step 2: Run, FAIL.**

- [ ] **Step 3: Add**

```julia
function string_decimal(x::ExactReal; digits::Int = 15)
    return _truncated_decimal(x, digits)
end
```

(Optional: also export this name. For now keep it as `BoehmCalc.string_decimal` and refine in v1.x.)

- [ ] **Step 4: Run, PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/show.jl test/show_tests.jl
git commit -m "feat(show): string_decimal with explicit digits"
```

---

## Phase 11: Test corpus mining and interop

### Task 11.1: Port the CRTest.java cases

**Files:**
- Create: `test/cr_test_corpus.jl`
- Modify: `test/runtests.jl`
- Create: `ATTRIBUTION.md`

- [ ] **Step 1: Create ATTRIBUTION.md (license preservation)**

```markdown
# Attribution

BoehmCalc.jl is MIT-licensed. The following upstream sources are used as
references and as the basis for ported test cases:

## CR.java (HP / SGI 1999)

Author: Hans-J. Boehm. Original copyright Hewlett-Packard Company, 2001-2004.
Source: https://android.googlesource.com/platform/external/crcalc/+/refs/heads/master/src/com/hp/creals/CR.java

CR.java is distributed under a permissive (MIT-style) license.

## UnifiedReal.java, BoundedRational.java (AOSP)

Copyright (C) 2016 The Android Open Source Project. Apache License 2.0.
Source: https://android.googlesource.com/platform/packages/apps/ExactCalculator/+/refs/tags/android-9.0.0_r32/src/com/android/calculator2/

## reals / computable-real Rust crates (hkalexling)

MIT-licensed. Test cases ported from doc-tests.
Source: https://crates.io/crates/reals  https://crates.io/crates/computable-real

## realistic Rust crate (Nick Lamb / tialaramex)

Apache-2.0-licensed. Test cases ported from src/real/test.rs.
Source: https://github.com/tialaramex/realistic
```

- [ ] **Step 2: Add failing test cases — port from CRTest.java**

(The full file CRTest.java is ~250 lines and ~50 assertions. Port each `assertEquals` into a Julia `@test`. Example translation pattern:)

```julia
# test/cr_test_corpus.jl
using BoehmCalc
using Test

@testset "CRTest.java port" begin
    # Translation of HP creals CRTest.java assertions.
    # License: HP/SGI permissive (preserved in ATTRIBUTION.md).

    # CRTest test_cr_basic
    @test ExactReal(1) + ExactReal(2) == ExactReal(3)
    @test ExactReal(1) - ExactReal(2) == ExactReal(-1)
    @test ExactReal(2) * ExactReal(3) == ExactReal(6)
    @test ExactReal(6) / ExactReal(2) == ExactReal(3)

    # CRTest test_sqrt
    @test sqrt(ExactReal(4)) == ExactReal(2)
    @test sqrt(ExactReal(2)) * sqrt(ExactReal(2)) == ExactReal(2)
    @test (sqrt(ExactReal(2)) + ExactReal(1)) * (sqrt(ExactReal(2)) - ExactReal(1)) == ExactReal(1)

    # CRTest test_trig
    @test sin(ExactReal(0)) == ExactReal(0)
    @test cos(ExactReal(0)) == ExactReal(1)
    @test sin(ExactReal(π) / ExactReal(6)) == ExactReal(1//2)
    @test cos(ExactReal(π) / ExactReal(3)) == ExactReal(1//2)

    # CRTest test_exp_log
    @test log(exp(ExactReal(1))) == ExactReal(1)
    @test exp(log(ExactReal(2))) == ExactReal(2)
    @test log(ExactReal(ℯ)) == ExactReal(1)

    # CRTest test_atan
    @test atan(ExactReal(1)) == ExactReal(π) / ExactReal(4)
    @test ExactReal(4) * atan(ExactReal(1)) == ExactReal(π)

    # CRTest test_asin
    @test asin(ExactReal(1)) == ExactReal(π) / ExactReal(2)
    @test asin(ExactReal(0)) == ExactReal(0)
    @test asin(ExactReal(1//2)) == ExactReal(π) / ExactReal(6)

    # ... continue from CRTest.java
end
```

Add `include("cr_test_corpus.jl")` to test/runtests.jl after the existing includes.

- [ ] **Step 3: Run, expect PASS** for the ones the v1 implementation handles.

If some fail, document them in `cr_test_corpus.jl` with `@test_skip` and a comment pointing at the v1.x deferral that would fix them.

- [ ] **Step 4: Commit**

```bash
git add test/cr_test_corpus.jl test/runtests.jl ATTRIBUTION.md
git commit -m "test: port CRTest.java cases + ATTRIBUTION.md"
```

### Task 11.2: Port `reals` crate doc-tests

**Files:**
- Create: `test/reals_doctest_corpus.jl`
- Modify: `test/runtests.jl`

- [ ] **Step 1: Mine the doc-tests**

The `reals-0.4.0/src/real.rs` file contains ~125 `assert_eq!(...)` lines as doc-tests. Each is of the form:

```rust
/// assert_eq!(Real::from(2).sqrt() * Real::from(2).sqrt(), Real::from(2));
```

Translate each into Julia. Pattern: `Real::from(N)` → `ExactReal(N)`, `.sqrt()` → `sqrt(...)`, etc.

Create `test/reals_doctest_corpus.jl` with the translations:

```julia
using BoehmCalc
using Test

@testset "reals crate doc-test port" begin
    # reals/src/real.rs
    @test sqrt(ExactReal(2)) * sqrt(ExactReal(2)) == ExactReal(2)
    @test sqrt(ExactReal(0)) == ExactReal(0)
    @test sqrt(ExactReal(4)) == ExactReal(2)
    @test sin(asin(ExactReal(1//2))) == ExactReal(1//2)
    @test asin(sin(ExactReal(π) / ExactReal(6))) == ExactReal(π) / ExactReal(6)
    @test exp(log(ExactReal(7))) == ExactReal(7)
    @test log(exp(ExactReal(2))) == ExactReal(2)
    @test log10(ExactReal(100)) == ExactReal(2)
    # ... continue, one line per doc-test in reals-0.4.0
end
```

(The full set of cases is in the source; this plan trusts the implementer to extract them mechanically.)

- [ ] **Step 2: Add to test/runtests.jl**

- [ ] **Step 3: Run, expect mostly PASS.**

Mark any v1-deferred cases with `@test_skip` and a comment.

- [ ] **Step 4: Commit**

```bash
git add test/reals_doctest_corpus.jl test/runtests.jl
git commit -m "test: port reals-crate doc-test corpus"
```

### Task 11.3: Conservatism tests

**Files:**
- Modify: `test/compare_tests.jl`

- [ ] **Step 1: Add tests**

```julia
@testset "conservatism" begin
    # Construct two equal-but-not-symbolically-comparable ExactReals.
    # Example: (π + e) computed in two structurally different ways.
    a = ExactReal(π) + ExactReal(ℯ)
    b = ExactReal(ℯ) + ExactReal(π)
    # Symbolic layer can't reduce these (both Irrational tag).
    # Per spec: == returns false (conservative).
    if !is_comparable(a, b)
        @test !(a == b)            # conservative ==: false on undecided
        # isless still gives a deterministic answer
        @test isless(a, b) || isless(b, a) || a === b
    end
end
```

- [ ] **Step 2: Run, PASS.**

- [ ] **Step 3: Commit**

```bash
git add test/compare_tests.jl
git commit -m "test: conservatism tests for == on equal-but-incomparable values"
```

### Task 11.4: Hash invariants

**Files:**
- Modify: `test/compare_tests.jl`

- [ ] **Step 1: Add tests**

```julia
@testset "hash invariants" begin
    # a == b ⇒ hash(a) == hash(b) over a generated corpus
    pairs = [
        (ExactReal(1), ExactReal(1//1)),
        (ExactReal(0.5), ExactReal(1//2)),
        (sqrt(ExactReal(4)), ExactReal(2)),
        (ExactReal(π) - ExactReal(π), ExactReal(0)),
        (sqrt(ExactReal(2)) * sqrt(ExactReal(2)), ExactReal(2)),
    ]
    for (a, b) in pairs
        @test a == b
        @test hash(a) == hash(b)
    end
end
```

- [ ] **Step 2: Run, PASS.**

- [ ] **Step 3: Commit**

```bash
git add test/compare_tests.jl
git commit -m "test: hash invariant a == b ⇒ hash(a) == hash(b)"
```

### Task 11.5: Interop tests (Float64, Rational, BigInt, Irrational)

**Files:**
- Modify: `test/interop_tests.jl`

- [ ] **Step 1: Add tests**

```julia
# test/interop_tests.jl
using BoehmCalc
using Test

@testset "Julia number-tower interop" begin
    # Promotion
    @test (1 + ExactReal(π)) isa ExactReal
    @test (ExactReal(1) + 0.5) isa ExactReal
    @test (1//3 + ExactReal(2//3)) == ExactReal(1)

    # Float64 round-trips
    @test Float64(ExactReal(0.1)) == 0.1
    @test ExactReal(0.1) == 0.1                  # via promotion
    @test ExactReal(0.1) != 1//10                # NOT 1/10 — Float64 0.1 is its binary rational

    # Sort
    xs = [ExactReal(π), ExactReal(2), ExactReal(0), sqrt(ExactReal(2))]
    sorted_xs = sort(xs)
    @test sorted_xs[1] == ExactReal(0)
    @test sorted_xs[end] == ExactReal(π)

    # Set/Dict
    s = Set{Real}([1, 1.0, 1//1, ExactReal(1)])
    @test length(s) == 1                         # all hash and ==-equal

    # Generic Real code works
    @test sum([ExactReal(1), ExactReal(2), ExactReal(3)]) == ExactReal(6)
end
```

- [ ] **Step 2: Run, PASS.**

- [ ] **Step 3: Commit**

```bash
git add test/interop_tests.jl
git commit -m "test: Julia number-tower interop (promotion, sort, Set, sum)"
```

### Task 11.6: Numerical-agreement smoke tests

**Files:**
- Modify: `test/exact_tests.jl`

- [ ] **Step 1: Add tests**

```julia
@testset "numerical agreement with BigFloat" begin
    # Operations on ExactReal should agree with BigFloat at multiple precisions.
    for prec in [53, 256, 1024]
        setprecision(BigFloat, prec) do
            cases = [
                (ExactReal(2) * ExactReal(3),           BigFloat(6)),
                (sqrt(ExactReal(2)),                    sqrt(BigFloat(2))),
                (exp(ExactReal(1)),                     exp(BigFloat(1))),
                (log(ExactReal(10)),                    log(BigFloat(10))),
                (sin(ExactReal(1)),                     sin(BigFloat(1))),
                (atan(ExactReal(1)) * ExactReal(4),     BigFloat(π)),
            ]
            for (er, bf) in cases
                er_bf = BigFloat(er; precision=prec)
                @test abs(er_bf - bf) < BigFloat(2)^(-prec + 4)
            end
        end
    end
end
```

- [ ] **Step 2: Run, PASS.**

- [ ] **Step 3: Commit**

```bash
git add test/exact_tests.jl
git commit -m "test: numerical agreement with BigFloat at multiple precisions"
```

---

## Phase 12: Coverage tooling and dev workflow

### Task 12.1: bin/coverage script

**Files:**
- Create: `bin/coverage`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Local coverage report for BoehmCalc.jl.
# Usage: bin/coverage
set -euo pipefail

cd "$(dirname "$0")/.."

julia --project=. --code-coverage=user -e 'using Pkg; Pkg.test()'
julia --project=. -e '
  using Coverage
  cov = process_folder("src")
  covered, total = get_summary(cov)
  pct = round(100 * covered / total, digits=2)
  println()
  println("Line coverage: $covered / $total = $pct%")
  println()
  # Per-file breakdown
  for f in cov
      cov_lines = sum(c -> c !== nothing && c > 0, f.coverage)
      total_lines = sum(c -> c !== nothing, f.coverage)
      total_lines > 0 || continue
      println("  $(f.filename): $cov_lines / $total_lines = $(round(100*cov_lines/total_lines, digits=1))%")
  end
  Coverage.clean_folder("src")
'
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/coverage
```

- [ ] **Step 3: Add Coverage.jl as a test-time dep**

```bash
julia --project=. -e 'using Pkg; Pkg.add(name="Coverage", target="test")'
```

(This modifies `Project.toml` and `test/Project.toml` accordingly.)

- [ ] **Step 4: Run the script to verify it works**

```bash
bin/coverage
```

Expected: prints overall percentage and per-file lines.

- [ ] **Step 5: Commit**

```bash
git add bin/coverage Project.toml test/Project.toml
git commit -m "chore: bin/coverage script for local line-coverage reports"
```

### Task 12.2: CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: Create CONTRIBUTING.md**

```markdown
# Contributing to BoehmCalc.jl

## Development workflow

```bash
# Run tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Run a single test file
julia --project=. test/exact_tests.jl

# Coverage report (locally)
bin/coverage
```

## Commit conventions

We use conventional commits: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`.
Each commit should be one logical change. Each TDD cycle (failing test →
implementation → passing test) is one commit.

## Coverage target

We aim for ≥95% line coverage in `src/`. PRs that drop coverage by more than
2 points need justification (e.g. a test platform doesn't support a feature).

## Adding a new operation

1. Add a Property tag in `src/property.jl` if it needs symbolic identity.
2. Add a `*CR` op subtype in `src/cr.jl` or `src/transcendental.jl`.
3. Add the user-facing function in `src/exact.jl` with the tag-dispatch case-split.
4. Add tests in `test/exact_tests.jl`.

## Reading order for new contributors

1. `SPEC.md` — design rationale.
2. `src/cr.jl` — the lower CR layer.
3. `src/exact.jl` — the upper ExactReal layer.
4. The Boehm paper (linked in `ATTRIBUTION.md`).
```

- [ ] **Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: CONTRIBUTING.md with dev workflow"
```

### Task 12.3: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the PkgTemplates README with substantive content**

```markdown
# BoehmCalc.jl

[![Build Status](https://github.com/StefanKarpinski/BoehmCalc.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/StefanKarpinski/BoehmCalc.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/StefanKarpinski/BoehmCalc.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/StefanKarpinski/BoehmCalc.jl)

Exact real arithmetic for Julia, based on Hans Boehm's "Towards an API for the
Real Numbers" (PLDI 2020).

## Quick start

```julia
using BoehmCalc

x = ExactReal(2)
sqrt(x) * sqrt(x) == x         # true (exact!)
sin(ExactReal(π) / 6) == 1//2   # true
log(exp(ExactReal(7))) == 7     # true
ExactReal(π) - ExactReal(π) == 0  # true

# Mix with native types
1 + ExactReal(π) isa ExactReal  # true
[1, ExactReal(π), 0.5]          # works fine

# Calculator-style timeouts
result = with_timeout(0.5) do
    # … expensive computation …
end
```

## Design

`ExactReal <: Real` is implemented in three internal layers:

- **CR**: lazy approximator with `approximate(x, p)::BigInt` returning an
  integer `a` with `|a · 2^p − x| < 2^p`. Per-instance precision caching.
- **BoundedRational helpers**: rational arithmetic with a 10000-bit overflow
  cap (configurable via `BoehmCalc.MAX_RATIONAL_BITS`).
- **ExactReal**: `rat_factor::Rational{BigInt} × cr_factor::CR`, plus a
  `Property` symbolic tag (`Pi`, `Sqrt`, `Exp`, `Ln`, …).

See `SPEC.md` for the full design.

## Caveats

- `==` is symbolic-only (conservative). Returns `false` for genuinely-equal
  values that the symbolic layer can't reduce. `isless` does an approximate
  fallback to maintain a strict total order.
- Hyperbolic functions are not yet implemented.
- See `SPEC.md` § "Open questions for follow-up" for the v1.x roadmap.

## License

MIT. See `ATTRIBUTION.md` for upstream sources whose ideas and tests this
package builds on.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README with quick start + design summary"
```

---

## Self-review checklist

After all tasks complete:

- [ ] Run the full test suite. Expect: PASS.
- [ ] Run `bin/coverage`. Expect: ≥95% line coverage in `src/`.
- [ ] Verify all exports listed in SPEC.md "Exported names" are actually exported.
- [ ] Read SPEC.md once more; for each section, confirm a corresponding implementation exists.
- [ ] Final commit (no-code) with summary if needed: `chore: v1 implementation complete`.

## v1.x deferred items (from SPEC.md)

These are NOT in scope for the v1 implementation but should be tracked in
GitHub issues after v1 ships:

1. `Tag::IrrationalConst` for `ExactReal(γ) == γ`.
2. Hyperbolics (`sinh`/`cosh`/`tanh` and inverses).
3. `parse(ExactReal, "...")` from string.
4. Multi-threaded sharing performance benchmarks.
5. Algebraic numbers beyond `√(rational)`.
6. Julia core extension to `Base.decompose` for irrationals.

---

## Plan complete

Implementation tasks: **42** (Phase 0 + Tasks 1.1–12.3).

The plan creates ~10 source files (~2500 lines), ~10 test files (~1500 lines), one coverage script, and three docs files. Estimated implementation time at one TDD cycle per ~15 minutes: 10–12 hours of focused work.
