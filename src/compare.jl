function is_comparable(a::ExactReal, b::ExactReal)
    iszero(a) && iszero(b) && return true
    a.prop == b.prop && return true
    a.prop.tag == Sqrt && b.prop.tag == Sqrt && return true
    if definitely_independent(a.prop, b.prop)
        if _magnitude_ge(a, -5000) || _magnitude_ge(b, -5000) || iszero(a) || iszero(b)
            return true
        end
    end
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
    iszero(a) != iszero(b) && return false
    if a.prop == b.prop
        return a.rat_factor == b.rat_factor
    end
    if a.prop.tag == Sqrt && b.prop.tag == Sqrt
        # Compare squared values: rat_factor^2 * arg, with sign tracking.
        sq_a = a.rat_factor^2 * a.prop.arg
        sq_b = b.rat_factor^2 * b.prop.arg
        sign_a = sign(a.rat_factor); sign_b = sign(b.rat_factor)
        return sq_a == sq_b && sign_a == sign_b
    end
    return false
end

# True iff |x| >= 2^p (cheap CR-level magnitude check).
function _magnitude_ge(x::ExactReal, p::Int)
    iszero(x) && return false
    a = get_approx(x.cr_factor, p)
    return abs(a) > 1
end

Base.:(==)(a::ExactReal, b::ExactReal) = definitely_equal(a, b)

function Base.isless(a::ExactReal, b::ExactReal)
    if is_comparable(a, b)
        return _exact_less(a, b)
    end
    d = a - b
    diff_cr = _scale_cr(d.rat_factor, d.cr_factor)
    delta = get_approx(diff_cr, -100)
    delta < -1 && return true
    delta >  1 && return false
    return objectid(a) < objectid(b)
end

function _exact_less(a::ExactReal, b::ExactReal)
    iszero(a) && iszero(b) && return false
    d = a - b
    diff_cr = _scale_cr(d.rat_factor, d.cr_factor)
    delta = get_approx(diff_cr, -64)
    return delta < 0
end

function definitely_less(a::ExactReal, b::ExactReal)::Union{Bool, Missing}
    is_comparable(a, b) || return missing
    return _exact_less(a, b)
end

Base.:<(a::ExactReal, b::ExactReal) = isless(a, b)
Base.:>(a::ExactReal, b::ExactReal) = isless(b, a)
Base.:<=(a::ExactReal, b::ExactReal) = !isless(b, a)
Base.:>=(a::ExactReal, b::ExactReal) = !isless(a, b)

# ---------------------------------------------------------------------------
# Hashing
# ---------------------------------------------------------------------------

function Base.Float64(x::ExactReal)
    if is_rational(x)
        return Float64(x.rat_factor)
    end
    bf = setprecision(BigFloat, 64) do
        a = get_approx(x.cr_factor, -53)
        BigFloat(a) * BigFloat(2.0)^(-53) * BigFloat(x.rat_factor)
    end
    return Float64(bf)
end

function Base.decompose(x::ExactReal)::Tuple{BigInt, Int, BigInt}
    if is_rational(x)
        return (numerator(x.rat_factor), 0, denominator(x.rat_factor))
    end
    return Base.decompose(Float64(x))
end

# Minimal promotion/conversion so that mixed-type == and Set/Dict work.
# Full conversion machinery is in Phase 9 (convert.jl).
Base.convert(::Type{ExactReal}, x::Integer) = ExactReal(x)
Base.convert(::Type{ExactReal}, x::Rational) = ExactReal(x)
Base.promote_rule(::Type{ExactReal}, ::Type{<:Integer}) = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{<:Rational}) = ExactReal

function Base.hash(x::ExactReal, h::UInt)
    # For the canonical mathematical constants π and ℯ, match their Irrational hash.
    if x.prop.tag == Pi && isone(x.rat_factor)
        return hash(π, h)
    end
    if x.prop.tag == Exp && x.prop.arg == Rational{BigInt}(1) && isone(x.rat_factor)
        return hash(ℯ, h)
    end
    # For rational values, delegate to the generic Real hash (which uses decompose).
    # This ensures hash(ExactReal(1//3)) == hash(1//3) etc.
    if is_rational(x)
        return invoke(hash, Tuple{Real, UInt}, x, h)
    end
    # For other irrationals, approximate via Float64 and hash that.
    return hash(Float64(x), h)
end
