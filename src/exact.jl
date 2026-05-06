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
