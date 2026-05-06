abstract type CR end

# Helper: arithmetic shift for BigInt.
# Positive n shifts right (divides by 2^n, rounding toward -∞).
# Negative n shifts left (multiplies by 2^(-n)).
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
