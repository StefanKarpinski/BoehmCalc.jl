"""
    CR

Abstract supertype for computable reals.

Every concrete `CR` subtype must declare the following mutable fields:
- `min_prec::Int`      — precision level of the cached approximation
- `max_appr::BigInt`   — the cached approximation value at `min_prec`
- `valid::Bool`        — whether the cache is currently valid
- `lock::ReentrantLock` — per-instance lock guarding the cache fields

Use `_make_cache()` to obtain initial values for these four fields in the
correct order.
"""
abstract type CR end

"""
    _shift(x::BigInt, n::Int) -> BigInt

Arithmetic shift of `x` by `n` bit positions.
- `n > 0`: right-shift (floor-divide by `2^n`, rounding toward −∞).
- `n < 0`: left-shift (multiply by `2^(-n)`).
- `n == 0`: identity.

Floor-rounding is intentional. The CR contract requires only
`|a·2^p − x| < 2^p` (i.e. ±1 ULP error is permitted), so truncating the
low-order bits rather than rounding-half-up is perfectly valid, and all
`approximate` implementations account for this.
"""
function _shift(x::BigInt, n::Int)
    n == 0 && return x
    n > 0 ? x >> n : x << -n
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

# Default cache fields helper.
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

"""
Return n such that 2^n ≤ |x| < 2^(n+1) (Boehm's convention: floor of log2|x|),
or `typemin(Int)` if `x` is provably within ±1 of zero at the deepest precision
we'll search.
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

function approximate(x::MulCR, p::Int)
    half_prec = (p >> 1) - 1
    msd_op1 = msd(x.left, half_prec)
    if msd_op1 == typemin(Int)
        msd_op2 = msd(x.right, half_prec)
        if msd_op2 == typemin(Int)
            return BigInt(0)
        end
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
    scale_amount = p - prec1 - prec2
    return _shift(a1 * a2, scale_amount)
end
