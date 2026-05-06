struct ExactReal <: Real
    rat_factor::Rational{BigInt}
    cr_factor::CR
    prop::Property
    function ExactReal(rat_factor::Rational{BigInt}, cr_factor::CR, prop::Property)
        # If rat_factor is zero, normalize cr_factor and prop to One/IntCR(1).
        if iszero(rat_factor)
            return new(rat_factor, _ONE_CR, _ONE_PROP)
        end
        return new(rat_factor, cr_factor, prop)
    end
end

# Shared singletons.
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

const _PI_CR   = PiCR()
const _PI_PROP = Property(Pi, nothing)

ExactReal(::Base.Irrational{:π}) = ExactReal(Rational{BigInt}(1), _PI_CR, _PI_PROP)

function ExactReal(::Base.Irrational{:ℯ})
    e_prop = Property(Exp, Rational{BigInt}(1))
    e_cr   = ExpCR(IntCR(1))
    ExactReal(Rational{BigInt}(1), e_cr, e_prop)
end

# Other Irrational{S}: convert via BigFloat; tag as Irrational.
function ExactReal(x::Base.Irrational)
    cr = BigFloatCR((_)->BigFloat(x), IntCR(0); extra_bits=64)
    ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

# ---------------------------------------------------------------------------
# Arithmetic
# ---------------------------------------------------------------------------

Base.:(-)(x::ExactReal) = ExactReal(-x.rat_factor, x.cr_factor, x.prop)

# Addition
function Base.:(+)(a::ExactReal, b::ExactReal)
    iszero(a) && return b
    iszero(b) && return a

    # Both pure rationals.
    if a.prop.tag == One && b.prop.tag == One
        sum_r = try_add(a.rat_factor, b.rat_factor)
        sum_r !== nothing && return ExactReal(sum_r, _ONE_CR, _ONE_PROP)
        # Overflow → fall back to CR
        return _crsum_fallback(a, b)
    end

    # Same Property: combine rat_factors.
    if a.prop == b.prop
        sum_r = try_add(a.rat_factor, b.rat_factor)
        if sum_r !== nothing
            iszero(sum_r) && return ExactReal(0)
            return ExactReal(sum_r, a.cr_factor, a.prop)
        end
    end

    # Different properties or rat_factor overflow: raw CR sum, no symbolic tag.
    return _crsum_fallback(a, b)
end

Base.:(-)(a::ExactReal, b::ExactReal) = a + (-b)

# Fallback: build the CR (rat_a · cr_a + rat_b · cr_b), drop the tag.
function _crsum_fallback(a::ExactReal, b::ExactReal)
    cr = AddCR(_scale_cr(a.rat_factor, a.cr_factor),
               _scale_cr(b.rat_factor, b.cr_factor))
    return ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

# Scale a CR by a rational factor.
function _scale_cr(r::Rational{BigInt}, c::CR)
    isone(r) && return c
    n = numerator(r); d = denominator(r)
    base = isone(n) ? c : MulCR(IntCR(n), c)
    return isone(d) ? base : MulCR(InvCR(IntCR(d)), base)
end

# Multiplication
function Base.:(*)(a::ExactReal, b::ExactReal)
    (iszero(a) || iszero(b)) && return ExactReal(0)
    rat = try_mul(a.rat_factor, b.rat_factor)

    # Both pure rationals.
    if a.prop.tag == One && b.prop.tag == One && rat !== nothing
        return ExactReal(rat, _ONE_CR, _ONE_PROP)
    end
    # One rational, one symbolic.
    if a.prop.tag == One && rat !== nothing
        return ExactReal(rat, b.cr_factor, b.prop)
    end
    if b.prop.tag == One && rat !== nothing
        return ExactReal(rat, a.cr_factor, a.prop)
    end

    # Both symbolic. Combine tags where possible.
    new_prop, factor = _combine_tags_mul(a.prop, b.prop)
    if new_prop !== nothing && rat !== nothing
        new_rat = try_mul(rat, factor)
        if new_rat !== nothing
            return ExactReal(new_rat, _cr_for(new_prop), new_prop)
        end
    end

    # Fallback: raw CR product, no tag.
    cr = MulCR(_scale_cr(a.rat_factor, a.cr_factor),
               _scale_cr(b.rat_factor, b.cr_factor))
    return ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

# Returns (new_prop, extra_rat_factor) if tags combine, else (nothing, nothing).
function _combine_tags_mul(a::Property, b::Property)
    if a.tag == Sqrt && b.tag == Sqrt
        prod = try_mul(a.arg, b.arg)
        prod === nothing && return (nothing, nothing)
        sq, rem = _extract_square(prod)
        if isone(rem)
            return (Property(One, nothing), sq)
        end
        return (Property(Sqrt, rem), sq)
    elseif a.tag == Exp && b.tag == Exp
        sum_arg = try_add(a.arg, b.arg)
        sum_arg === nothing && return (nothing, nothing)
        new_prop = make_property(Exp, sum_arg)
        return (new_prop, Rational{BigInt}(1))
    end
    return (nothing, nothing)
end

# Construct the CR for a normal-form Property.
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

# Inversion + division
function Base.inv(x::ExactReal)
    iszero(x) && throw(DivideError())
    if x.prop.tag == One
        return ExactReal(inv(x.rat_factor))
    end
    inv_rat = inv(x.rat_factor)
    if x.prop.tag == Sqrt
        # 1/(k·√r) = (1/k)·√(1/r). make_property normalizes the new arg.
        new_arg = inv(x.prop.arg)
        new_prop = make_property(Sqrt, new_arg)
        # If make_property returned One (perfect square), absorb the cr factor.
        if new_prop.tag == One
            return ExactReal(inv_rat, _ONE_CR, _ONE_PROP)
        end
        return ExactReal(inv_rat, _cr_for(new_prop), new_prop)
    end
    if x.prop.tag == Exp
        # 1/e^a = e^(-a). Always Exp-tagged.
        new_arg = -x.prop.arg
        new_prop = make_property(Exp, new_arg)
        if new_prop.tag == One
            return ExactReal(inv_rat, _ONE_CR, _ONE_PROP)
        end
        return ExactReal(inv_rat, _cr_for(new_prop), new_prop)
    end
    # General case: drop the symbolic tag.
    return ExactReal(inv_rat, InvCR(x.cr_factor), Property(Irrational, nothing))
end

Base.:(/)(a::ExactReal, b::ExactReal) = a * inv(b)
