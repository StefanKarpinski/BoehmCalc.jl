"""
A CR backed by MPFR (BigFloat). Computes `f(x)` where `x` is itself a CR by:
  1. Asking the operand for an approximation at scale `-(|p| + extra_bits)`.
  2. Converting to BigFloat with sufficient precision.
  3. Calling `f` on the BigFloat.
  4. Scaling the result back to a BigInt at scale p.
"""
mutable struct BigFloatCR <: CR
    f::Function                           # f::BigFloat -> BigFloat
    op::CR
    extra_bits::Int                       # precision bump above |p|
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function BigFloatCR(f, op::CR; extra_bits::Int = 64)
        c = _make_cache()
        new(f, op, extra_bits, c[1], c[2], c[3], c[4])
    end
end

function approximate(x::BigFloatCR, p::Int)
    pp = max(64, abs(p) + x.extra_bits)
    setprecision(BigFloat, pp) do
        op_appr_bigint = get_approx(x.op, -pp)
        op_bf = BigFloat(op_appr_bigint) * BigFloat(2.0)^(-pp)
        result_bf = x.f(op_bf)
        yield()
        check_cancellation()
        scaled = result_bf * BigFloat(2.0)^(-p)
        return round(BigInt, scaled)
    end
end

# Sqrt: domain check is the caller's responsibility (we trust MPFR).
SqrtCR(op::CR) = BigFloatCR(sqrt, op)

ExpCR(op::CR)  = BigFloatCR(exp, op)
LnCR(op::CR)   = BigFloatCR(log, op)
CosCR(op::CR)  = BigFloatCR(cos, op)
AtanCR(op::CR) = BigFloatCR(atan, op)
AsinCR(op::CR) = BigFloatCR(asin, op)

# π as a singleton CR (no operand). We just call BigFloat(π) at the right precision.
mutable struct PiCR <: CR
    max_appr::BigInt
    min_prec::Int
    valid::Bool
    lock::ReentrantLock
    function PiCR()
        c = _make_cache()
        new(c[1], c[2], c[3], c[4])
    end
end

function approximate(::PiCR, p::Int)
    pp = max(64, abs(p) + 64)
    setprecision(BigFloat, pp) do
        return round(BigInt, BigFloat(π) * BigFloat(2.0)^(-p))
    end
end
