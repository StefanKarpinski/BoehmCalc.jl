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
    # Repeated squaring; bail early on overflow.
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
