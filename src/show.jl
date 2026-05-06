# ---------------------------------------------------------------------------
# Task 10.1: Symbolic-aware show with decimal fallback
# ---------------------------------------------------------------------------

function Base.show(io::IO, x::ExactReal)
    if is_rational(x)
        r = x.rat_factor
        if isone(denominator(r))
            print(io, numerator(r))
        else
            print(io, numerator(r), "//", denominator(r))
        end
        return
    end
    s = _symbolic_string(x)
    if s !== nothing
        print(io, s)
    else
        print(io, _truncated_decimal(x, 15))
    end
end

function _symbolic_string(x::ExactReal)::Union{String, Nothing}
    iszero(x) && return "0"
    if x.prop.tag == Pi
        return _wrap_rational(x.rat_factor, "π")
    elseif x.prop.tag == Exp && x.prop.arg == 1 && isone(x.rat_factor)
        return "ℯ"
    elseif x.prop.tag == Sqrt
        sym = "√" * _arg_string(x.prop.arg)
        return _wrap_rational(x.rat_factor, sym)
    elseif x.prop.tag == Exp && isone(x.rat_factor)
        return "ℯ^" * _arg_string(x.prop.arg)
    elseif x.prop.tag == Ln && isone(x.rat_factor)
        return "ln(" * _arg_string(x.prop.arg) * ")"
    end
    return nothing
end

function _wrap_rational(r::Rational{BigInt}, sym::AbstractString)
    isone(r)            && return sym
    r == -1             && return "-" * sym
    n = numerator(r); d = denominator(r)
    if isone(d)
        return string(n) * sym
    elseif n == 1
        return sym * "/" * string(d)
    elseif n == -1
        return "-" * sym * "/" * string(d)
    end
    return string(n) * sym * "/" * string(d)
end

function _arg_string(r::Rational{BigInt})
    isone(denominator(r)) && return string(numerator(r))
    return "(" * string(numerator(r)) * "/" * string(denominator(r)) * ")"
end

function _truncated_decimal(x::ExactReal, sig_digits::Int)
    bf = BigFloat(x; precision=ceil(Int, sig_digits * log2(10)) + 16)
    s = string(bf)
    dot = findfirst('.', s)
    if dot === nothing
        return s
    end
    if length(s) > sig_digits + 1
        return s[1:sig_digits+1] * "…"
    end
    return s
end

function Base.show(io::IO, ::MIME"text/plain", x::ExactReal)
    s = _symbolic_string(x)
    if s === nothing || is_rational(x)
        show(io, x)
    else
        print(io, s, " ≈ ", _truncated_decimal(x, 15))
    end
end

# ---------------------------------------------------------------------------
# Task 10.2: text/latex MIME
# ---------------------------------------------------------------------------

function Base.show(io::IO, ::MIME"text/latex", x::ExactReal)
    print(io, "\$", _latex_string(x), "\$")
end

function _latex_string(x::ExactReal)
    if is_rational(x)
        n = numerator(x.rat_factor); d = denominator(x.rat_factor)
        isone(d) && return string(n)
        return "\\frac{" * string(n) * "}{" * string(d) * "}"
    elseif x.prop.tag == Pi
        return _latex_wrap_rat(x.rat_factor, "\\pi")
    elseif x.prop.tag == Sqrt
        sym = "\\sqrt{" * _arg_string(x.prop.arg) * "}"
        return _latex_wrap_rat(x.rat_factor, sym)
    elseif x.prop.tag == Exp && x.prop.arg == 1 && isone(x.rat_factor)
        return "e"
    end
    return _truncated_decimal(x, 15)
end

function _latex_wrap_rat(r::Rational{BigInt}, sym::AbstractString)
    isone(r) && return sym
    r == -1  && return "-" * sym
    n = numerator(r); d = denominator(r)
    isone(d) && return string(n) * sym
    n == 1  && return "\\frac{" * sym * "}{" * string(d) * "}"
    return "\\frac{" * string(n) * sym * "}{" * string(d) * "}"
end

# ---------------------------------------------------------------------------
# Task 10.3: string_decimal with explicit digits
# ---------------------------------------------------------------------------

function string_decimal(x::ExactReal; digits::Int = 15)
    return _truncated_decimal(x, digits)
end
