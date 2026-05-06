"""
Symbolic tag for the `cr_factor` of an `ExactReal`.

  One         crFactor is exactly 1 (purely rational ExactReal)
  Pi          crFactor is π
  Sqrt        crFactor is √arg, with arg ∈ ℚ, arg > 0, arg ≠ perfect-square × ℚ
  Exp         crFactor is e^arg, with arg ∈ ℚ, arg ≠ 0
  Ln          crFactor is ln(arg), with arg ∈ ℚ, arg > 1
  Log         crFactor is log10(arg), with arg ∈ ℚ, arg > 0, arg not a power of 10
  SinPi       crFactor is sin(π·arg), with arg ∈ (0, 1/2) ∩ ℚ, arg ∉ {1/6, 1/4, 1/3}
  TanPi       crFactor is tan(π·arg), similar to SinPi
  Asin        crFactor is asin(arg), with arg ∈ (0, 1) ∩ ℚ
  Atan        crFactor is atan(arg), with arg ∈ ℚ, arg > 0
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
        return Property(SinPi, arg_r)
    elseif tag == TanPi
        return Property(TanPi, arg_r)
    elseif tag == Asin
        iszero(arg_r) && return Property(One, nothing)
        return Property(Asin, arg_r)
    elseif tag == Atan
        iszero(arg_r) && return Property(One, nothing)
        return Property(Atan, arg_r)
    end
    error("unhandled tag: $tag")
end

is_transcendental(p::Property) = p.tag in (Pi, Exp, Ln, Log, SinPi, TanPi, Asin, Atan)

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
