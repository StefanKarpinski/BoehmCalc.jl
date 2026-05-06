# ---------------------------------------------------------------------------
# Promotion rules: Julia number types → ExactReal
# ---------------------------------------------------------------------------

Base.promote_rule(::Type{ExactReal}, ::Type{<:Integer})         = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{<:Rational})        = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{Float16})           = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{Float32})           = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{Float64})           = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{BigFloat})          = ExactReal
Base.promote_rule(::Type{ExactReal}, ::Type{<:Base.Irrational}) = ExactReal

# ---------------------------------------------------------------------------
# Conversion in: Julia number types → ExactReal
# ---------------------------------------------------------------------------

Base.convert(::Type{ExactReal}, x::Integer)         = ExactReal(x)
Base.convert(::Type{ExactReal}, x::Rational)        = ExactReal(x)
Base.convert(::Type{ExactReal}, x::AbstractFloat)   = ExactReal(x)
Base.convert(::Type{ExactReal}, x::Base.Irrational) = ExactReal(x)

# ---------------------------------------------------------------------------
# Conversion out: ExactReal → Julia number types
# ---------------------------------------------------------------------------

function Base.Float64(x::ExactReal)
    if is_rational(x)
        return Float64(x.rat_factor)
    end
    bf = BigFloat(x; precision=53)
    return Float64(bf)
end

function Base.BigFloat(x::ExactReal; precision::Integer = Base.precision(BigFloat))
    setprecision(BigFloat, Int(precision)) do
        if is_rational(x)
            return BigFloat(x.rat_factor)
        end
        a = get_approx(x.cr_factor, -Int(precision) - 4)
        scaled = BigFloat(a) * BigFloat(2.0)^(-Int(precision) - 4)
        return BigFloat(x.rat_factor) * scaled
    end
end

function Base.Rational{BigInt}(x::ExactReal)
    is_rational(x) || throw(InexactError(:Rational, Rational{BigInt}, x))
    return x.rat_factor
end

function Base.BigInt(x::ExactReal)
    is_integer(x) || throw(InexactError(:BigInt, BigInt, x))
    return numerator(x.rat_factor)
end

Base.Float32(x::ExactReal) = Float32(Float64(x))
Base.Float16(x::ExactReal) = Float16(Float64(x))
