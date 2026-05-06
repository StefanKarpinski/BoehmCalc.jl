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
