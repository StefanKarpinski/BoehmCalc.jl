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
