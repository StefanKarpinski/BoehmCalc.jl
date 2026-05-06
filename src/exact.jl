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

# ---------------------------------------------------------------------------
# sqrt
# ---------------------------------------------------------------------------

function Base.sqrt(x::ExactReal)
    iszero(x) && return ExactReal(0)
    x.prop.tag == One && x.rat_factor < 0 && throw(DomainError(x, "sqrt of negative"))

    if x.prop.tag == One
        # Pure rational; check perfect square first.
        ex = try_sqrt_exact(x.rat_factor)
        ex !== nothing && return ExactReal(ex)
        # √r where r > 0, not a perfect square: build Sqrt-tagged.
        sq, rem = _extract_square(x.rat_factor)
        if isone(rem)
            # Should not happen if try_sqrt_exact returned nothing, but be safe.
            return ExactReal(sq * BigInt(0))  # unreachable; bail to fallback
        end
        sqrt_prop = Property(Sqrt, rem)
        sqrt_cr   = SqrtCR(_rational_cr(rem))
        return ExactReal(sq, sqrt_cr, sqrt_prop)
    end
    # Symbolic input: fall back to CR-only with Irrational tag.
    return ExactReal(Rational{BigInt}(1),
                     SqrtCR(_scale_cr(x.rat_factor, x.cr_factor)),
                     Property(Irrational, nothing))
end

# ---------------------------------------------------------------------------
# exp / log / log10
# ---------------------------------------------------------------------------

function Base.exp(x::ExactReal)
    iszero(x) && return ExactReal(1)
    if x.prop.tag == One
        prop = make_property(Exp, x.rat_factor)
        prop.tag == One && return ExactReal(1)
        cr = ExpCR(_rational_cr(x.rat_factor))
        return ExactReal(Rational{BigInt}(1), cr, prop)
    end
    # Symbolic input: CR-only fallback.
    cr = ExpCR(_scale_cr(x.rat_factor, x.cr_factor))
    return ExactReal(Rational{BigInt}(1), cr, Property(Irrational, nothing))
end

function Base.log(x::ExactReal)
    # Domain check using rational layer when possible.
    x.prop.tag == One && x.rat_factor <= 0 && throw(DomainError(x, "log of non-positive"))
    isone(x) && return ExactReal(0)

    # log(e^a) = a (when ExactReal is purely Exp-tagged with rat_factor 1)
    if x.prop.tag == Exp && isone(x.rat_factor)
        return ExactReal(x.prop.arg)
    end

    if x.prop.tag == One
        # log(rational > 0): use Ln tag (which requires arg > 1).
        if x.rat_factor < 1
            return -log(ExactReal(inv(x.rat_factor)))
        end
        prop = make_property(Ln, x.rat_factor)
        prop.tag == One && return ExactReal(0)
        cr = LnCR(_rational_cr(x.rat_factor))
        return ExactReal(Rational{BigInt}(1), cr, prop)
    end
    # Generic symbolic: CR fallback, Irrational tag.
    return ExactReal(Rational{BigInt}(1),
                     LnCR(_scale_cr(x.rat_factor, x.cr_factor)),
                     Property(Irrational, nothing))
end

Base.log10(x::ExactReal) = log(x) / log(ExactReal(10))
Base.log(b::ExactReal, x::ExactReal) = log(x) / log(b)

# ---------------------------------------------------------------------------
# Power
# ---------------------------------------------------------------------------

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
    # Generic: repeated multiplication.
    result = a
    for _ in 2:n
        result = result * a
    end
    return result
end

function Base.:(^)(a::ExactReal, r::Rational)
    iszero(a) && r > 0 && return ExactReal(0)
    iszero(a) && throw(DomainError(0, "0^non-positive is undefined"))
    p = numerator(r); q = denominator(r)
    a_p = a ^ p
    return _root(a_p, q)
end

function _root(a::ExactReal, q::Integer)
    q == 1 && return a
    q == 2 && return sqrt(a)
    # General: a^(1/q) = exp(log(a)/q). Requires a > 0.
    a.prop.tag == One && a.rat_factor < 0 && throw(DomainError(a, "real root of negative"))
    return exp(log(a) / ExactReal(q))
end

function Base.:(^)(a::ExactReal, b::ExactReal)
    is_integer(b) && return a ^ Integer(numerator(b.rat_factor))
    is_rational(b) && return a ^ b.rat_factor
    a.prop.tag == One && a.rat_factor <= 0 && throw(DomainError(a, "non-positive base with non-rational exponent"))
    return exp(b * log(a))
end

# ---------------------------------------------------------------------------
# sin / cos / tan
# ---------------------------------------------------------------------------

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
