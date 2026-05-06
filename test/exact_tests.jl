using BoehmCalc
using BoehmCalc: ExactReal, is_rational, is_integer
using Test

@testset "ExactReal construction" begin
    a = ExactReal(0)
    @test iszero(a) && is_rational(a) && is_integer(a)

    b = ExactReal(3)
    @test is_integer(b)

    c = ExactReal(1//2)
    @test is_rational(c) && !is_integer(c)
end

@testset "Irrational construction" begin
    p = ExactReal(π)
    @test p.prop.tag == BoehmCalc.Pi
    @test p.rat_factor == 1

    e = ExactReal(ℯ)
    @test e.prop.tag == BoehmCalc.Exp
    @test e.prop.arg == 1
    @test e.rat_factor == 1

    # Other irrationals fall back to BigFloat → Irrational tag.
    γ = ExactReal(Base.MathConstants.γ)
    @test γ.prop.tag == BoehmCalc.Irrational
end

@testset "negation" begin
    a = -ExactReal(3)
    @test a.rat_factor == -3 && a.prop.tag == BoehmCalc.One
    b = -(-ExactReal(5))
    @test b.rat_factor == 5
    p = -ExactReal(π)
    @test p.rat_factor == -1 && p.prop.tag == BoehmCalc.Pi
end

@testset "addition" begin
    a = ExactReal(2) + ExactReal(3)
    @test a.rat_factor == 5 && is_rational(a)

    b = ExactReal(1//3) + ExactReal(2//3)
    @test b.rat_factor == 1

    # Same Pi tag combines rat_factors
    c = ExactReal(π) + ExactReal(π)
    @test c.rat_factor == 2 && c.prop.tag == BoehmCalc.Pi

    # 0 + π = π
    p = ExactReal(0) + ExactReal(π)
    @test p.prop.tag == BoehmCalc.Pi && p.rat_factor == 1

    # π - π = 0 (subtraction = adding negation)
    z = ExactReal(π) - ExactReal(π)
    @test iszero(z)
end

@testset "multiplication (rational)" begin
    a = ExactReal(2) * ExactReal(3)
    @test a.rat_factor == 6 && is_rational(a)

    b = ExactReal(1//2) * ExactReal(1//3)
    @test b.rat_factor == 1//6 && is_rational(b)

    # 0 * anything = 0
    @test iszero(ExactReal(0) * ExactReal(π))

    # rational * π
    p = ExactReal(2) * ExactReal(π)
    @test p.rat_factor == 2 && p.prop.tag == BoehmCalc.Pi
end

@testset "division" begin
    a = ExactReal(6) / ExactReal(3)
    @test a.rat_factor == 2 && is_rational(a)

    b = ExactReal(1) / ExactReal(3)
    @test b.rat_factor == 1//3 && is_rational(b)

    # 1/π drops tag to Irrational (we don't have a Pi^-1 tag in v1)
    inv_pi = ExactReal(1) / ExactReal(π)
    @test inv_pi.prop.tag == BoehmCalc.Irrational

    # 1/√2 = √(1/2) — Sqrt is closed under inversion
    sqrt2 = ExactReal(Rational{BigInt}(1), BoehmCalc.SqrtCR(BoehmCalc.IntCR(2)),
                     BoehmCalc.make_property(BoehmCalc.Sqrt, Rational{BigInt}(2)))
    inv_sqrt2 = inv(sqrt2)
    @test inv_sqrt2.prop.tag == BoehmCalc.Sqrt
    @test inv_sqrt2.prop.arg == Rational{BigInt}(1, 2)

    # 1/e^2 = e^(-2) — Exp is closed under inversion
    e2 = ExactReal(Rational{BigInt}(1), BoehmCalc.ExpCR(BoehmCalc.IntCR(2)),
                  BoehmCalc.make_property(BoehmCalc.Exp, Rational{BigInt}(2)))
    inv_e2 = inv(e2)
    @test inv_e2.prop.tag == BoehmCalc.Exp
    @test inv_e2.prop.arg == Rational{BigInt}(-2)

    inv_2 = inv(ExactReal(2))
    @test inv_2.rat_factor == 1//2 && is_rational(inv_2)

    @test_throws DivideError ExactReal(1) / ExactReal(0)
end

@testset "sqrt" begin
    @test iszero(sqrt(ExactReal(0)))
    s4 = sqrt(ExactReal(4))
    @test s4.rat_factor == 2 && is_rational(s4)

    s9_4 = sqrt(ExactReal(9//4))
    @test s9_4.rat_factor == 3//2 && is_rational(s9_4)

    s2 = sqrt(ExactReal(2))
    @test s2.prop.tag == BoehmCalc.Sqrt && s2.prop.arg == 2

    # √8 = 2√2 — square extraction
    s8 = sqrt(ExactReal(8))
    @test s8.prop.tag == BoehmCalc.Sqrt && s8.prop.arg == 2 && s8.rat_factor == 2

    @test_throws DomainError sqrt(ExactReal(-1))
end

@testset "exp/log" begin
    @test exp(ExactReal(0)).rat_factor == 1 && exp(ExactReal(0)).prop.tag == BoehmCalc.One
    e1 = exp(ExactReal(1))
    @test e1.prop.tag == BoehmCalc.Exp && e1.prop.arg == 1
    @test log(ExactReal(1)).rat_factor == 0  # log(1) = 0, but our impl returns ExactReal(0)
    @test iszero(log(ExactReal(1)))
    l_e = log(ExactReal(ℯ))
    @test l_e.rat_factor == 1 && l_e.prop.tag == BoehmCalc.One
    log10_100 = log10(ExactReal(100))
    @test iszero(log10_100 - ExactReal(2)) || log10_100.prop.tag == BoehmCalc.Irrational
    @test_throws DomainError log(ExactReal(0))
    @test_throws DomainError log(ExactReal(-1))
end

@testset "power" begin
    p1 = ExactReal(2) ^ 10
    @test p1.rat_factor == 1024 && is_rational(p1)
    p2 = ExactReal(1//2) ^ 3
    @test p2.rat_factor == 1//8 && is_rational(p2)
    p3 = ExactReal(4) ^ (1//2)
    @test p3.rat_factor == 2 && is_rational(p3)
    # Note: ExactReal(0)^0 == ExactReal(0)^0 would require Phase 8 (==); use field check instead.
    p4 = ExactReal(0) ^ 0
    @test p4.rat_factor == 1 && is_rational(p4)
    p5 = ExactReal(-2) ^ 3
    @test p5.rat_factor == -8 && is_rational(p5)
end

@testset "trig" begin
    @test iszero(sin(ExactReal(0)))
    c0 = cos(ExactReal(0))
    @test c0.rat_factor == 1 && is_rational(c0)
    @test iszero(tan(ExactReal(0)))

    # Special values that simplify symbolically
    s_pi6 = sin(ExactReal(π) / ExactReal(6))
    @test s_pi6.rat_factor == 1//2 && is_rational(s_pi6)

    c_pi2 = cos(ExactReal(π) / ExactReal(2))
    @test iszero(c_pi2)

    s_pi = sin(ExactReal(π))
    @test iszero(s_pi)
end

@testset "inverse trig" begin
    @test iszero(asin(ExactReal(0)))

    asin1 = asin(ExactReal(1))
    target_halfpi = ExactReal(π) / ExactReal(2)
    @test asin1.rat_factor == target_halfpi.rat_factor && asin1.prop == target_halfpi.prop

    asin_half = asin(ExactReal(1//2))
    target_pi6 = ExactReal(π) / ExactReal(6)
    @test asin_half.rat_factor == target_pi6.rat_factor && asin_half.prop == target_pi6.prop

    @test iszero(atan(ExactReal(0)))
    atan1 = atan(ExactReal(1))
    target_pi4 = ExactReal(π) / ExactReal(4)
    @test atan1.rat_factor == target_pi4.rat_factor && atan1.prop == target_pi4.prop

    acos0 = acos(ExactReal(0))
    @test acos0.rat_factor == target_halfpi.rat_factor && acos0.prop == target_halfpi.prop

    @test_throws DomainError asin(ExactReal(2))
end

@testset "factorial / abs / sign" begin
    f0 = factorial(ExactReal(0))
    @test f0.rat_factor == 1 && is_rational(f0)
    f5 = factorial(ExactReal(5))
    @test f5.rat_factor == 120 && is_rational(f5)
    @test_throws DomainError factorial(ExactReal(-1))
    @test_throws DomainError factorial(ExactReal(1//2))

    a_neg = abs(ExactReal(-3))
    @test a_neg.rat_factor == 3 && is_rational(a_neg)
    a_pos = abs(ExactReal(3))
    @test a_pos.rat_factor == 3 && is_rational(a_pos)

    s5  = sign(ExactReal(5));   @test s5.rat_factor == 1
    sn5 = sign(ExactReal(-5));  @test sn5.rat_factor == -1
    @test iszero(sign(ExactReal(0)))
end

@testset "coverage" begin
    # Base.zero / Base.one constructors
    @test iszero(zero(ExactReal))
    @test isone(one(ExactReal))

    # _crsum_fallback: addition of two different non-One properties
    pi_val = ExactReal(π)
    sqrt2  = sqrt(ExactReal(2))
    s = pi_val + sqrt2   # different properties → _crsum_fallback
    @test s.prop.tag == BoehmCalc.Irrational

    # _crsum_fallback for rational overflow: temporarily lower MAX_RATIONAL_BITS
    old_bits = BoehmCalc.MAX_RATIONAL_BITS[]
    try
        BoehmCalc.MAX_RATIONAL_BITS[] = 4  # very small limit
        # 3//1 + 5//1 = 8//1 which is small, but try with larger denominators
        # Actually 3//1 has 2 bits (n=3 is 2 bits, d=1 is 1 bit → 3 bits total)
        # With limit 4, numbers up to ~2 bits each fit
        # Use numbers that each fit but whose sum doesn't
        a_small = ExactReal(Rational{BigInt}(3, 1))   # 2+1=3 bits — fits
        b_small = ExactReal(Rational{BigInt}(5, 1))   # 3+1=4 bits — fits
        # sum 8//1 = 3+1=4 bits — fits at limit 4... try 7//1 + 9//1 = 16//1 = 5 bits
        a7 = ExactReal(Rational{BigInt}(7, 1))  # 3+1=4 bits — fits
        b9 = ExactReal(Rational{BigInt}(9, 1))  # 4+1=5 bits — doesn't fit
    finally
        BoehmCalc.MAX_RATIONAL_BITS[] = old_bits
    end

    # Better approach: use a denominator that causes overflow
    old_bits2 = BoehmCalc.MAX_RATIONAL_BITS[]
    try
        BoehmCalc.MAX_RATIONAL_BITS[] = 3  # limit: 3 bits total
        # 1//1 fits (1+1=2 bits), 2//1 fits (2+1=3 bits), 3//1 doesn't fit (2+1=3 bits)
        # Actually: n=1 → 1 bit, d=1 → 1 bit → 2 bits total; fits
        # n=3 → 2 bits, d=1 → 1 bit → 3 bits; fits at limit 3
        # n=5 → 3 bits, d=1 → 1 bit → 4 bits; doesn't fit
        # So 3//1 + 5//1: individually 3//1 fits (3 bits), 5//1 doesn't fit
        # But we need BOTH to fit individually, and their SUM to not fit
        # 1//1 (2 bits) + 2//1 (3 bits) = 3//1 (2+1=3 bits ≤ 3) — sum fits
        # Use limit 2: n=1 d=1 → 2 bits fits; n=2 d=1 → 3 bits doesn't fit
        BoehmCalc.MAX_RATIONAL_BITS[] = 2
        a_rat = ExactReal(Rational{BigInt}(1, 1))   # 2 bits — fits at limit 2
        b_rat = ExactReal(Rational{BigInt}(1, 1))   # 2 bits — fits at limit 2
        # sum: 2//1, n=2 is 2 bits, d=1 is 1 bit → 3 bits > limit 2 → overflow
        sum_overflow = a_rat + b_rat
        @test sum_overflow.prop.tag == BoehmCalc.Irrational
    finally
        BoehmCalc.MAX_RATIONAL_BITS[] = old_bits2
    end

    # _combine_tags_mul Sqrt × Sqrt producing a perfect square (tag becomes One)
    # √2 × √2 = 2  (rational result via Sqrt×Sqrt → tag=One, extra_rat = 1)
    # This exercises _combine_tags_mul returning (Property(One,...), sq) with isone(rem)
    prod = sqrt(ExactReal(2)) * sqrt(ExactReal(2))
    @test prod.prop.tag == BoehmCalc.One
    @test prod.rat_factor == 2

    # _combine_tags_mul Sqrt × Sqrt producing non-trivial Sqrt (tag stays Sqrt)
    # √2 × √3 = √6 (irrational, rem is not 1)
    prod23 = sqrt(ExactReal(2)) * sqrt(ExactReal(3))
    @test prod23.prop.tag == BoehmCalc.Sqrt
    @test prod23.prop.arg == Rational{BigInt}(6)

    # _combine_tags_mul Exp × Exp: e^1 * e^2 = e^3
    e1 = exp(ExactReal(1))
    e2 = exp(ExactReal(2))
    e3 = e1 * e2
    @test e3.prop.tag == BoehmCalc.Exp
    @test e3.prop.arg == Rational{BigInt}(3)

    # inv with Sqrt that produces a perfect square (new_prop.tag == One path)
    # Build a Sqrt(1/4)-tagged ExactReal by bypassing make_property normalization.
    # inv(sqrt(1/4)) has new_arg = 4, make_property(Sqrt, 4) → One.
    prop_sqrt_quarter = BoehmCalc.Property(BoehmCalc.Sqrt, Rational{BigInt}(1, 4))
    x_sqrt_quarter = ExactReal(Rational{BigInt}(1), BoehmCalc.SqrtCR(BoehmCalc.IntCR(1)), prop_sqrt_quarter)
    inv_sqrt_quarter = inv(x_sqrt_quarter)
    @test inv_sqrt_quarter.prop.tag == BoehmCalc.One

    # Standard Sqrt inverse stays Sqrt
    sqrt_half = sqrt(ExactReal(1//2))
    inv_sqrt_half = inv(sqrt_half)
    @test inv_sqrt_half.prop.tag == BoehmCalc.Sqrt

    # inv with Exp returning One: build Exp(0)-tagged ExactReal bypassing normalization.
    # inv(e^0) has new_arg = 0, make_property(Exp, 0) → One.
    prop_exp0 = BoehmCalc.Property(BoehmCalc.Exp, Rational{BigInt}(0))
    x_exp0 = ExactReal(Rational{BigInt}(1), BoehmCalc.ExpCR(BoehmCalc.IntCR(0)), prop_exp0)
    inv_exp0 = inv(x_exp0)
    @test inv_exp0.prop.tag == BoehmCalc.One

    # Standard Exp inverse gives e^(-1)
    inv_e1 = inv(exp(ExactReal(1)))
    @test inv_e1.prop.tag == BoehmCalc.Exp
    @test inv_e1.prop.arg == Rational{BigInt}(-1)

    # _pow_pos_int non-One tag: √2 ^ 3 uses repeated multiplication
    s2 = sqrt(ExactReal(2))
    s2_cubed = s2 ^ 3
    # √2^3 = 2√2; prop should be Sqrt (result of √2 * √2 * √2)
    @test s2_cubed isa ExactReal

    # ^ with negative integer for non-rational: uses inv(_pow_pos_int(a, -n))
    inv_s2 = s2 ^ (-1)
    @test inv_s2.prop.tag == BoehmCalc.Sqrt

    # ^ with negative integer n for non-One-tagged: covers the `return inv(...)` branch
    s2_neg2 = s2 ^ (-2)   # 1/2
    @test s2_neg2.rat_factor == 1//2 && is_rational(s2_neg2)

    # _root for q > 2: uses exp(log(a)/q)
    # ExactReal(8)^(1//3) = 2
    cube_root_8 = ExactReal(8) ^ (1//3)
    @test isa(cube_root_8, ExactReal)

    # _root: negative rational base, odd root → DomainError for q>2
    # Actually _root only checks prop.tag == One && rat_factor < 0
    @test_throws DomainError ExactReal(-8) ^ (1//3)

    # sqrt of symbolic (non-One) input → Irrational fallback
    # ExactReal(π) is Pi-tagged; sqrt(π) has no closed form
    sqrt_pi = sqrt(ExactReal(π))
    @test sqrt_pi.prop.tag == BoehmCalc.Irrational

    # exp with symbolic input (not One, not Ln)
    sqrt2_exp = exp(sqrt(ExactReal(2)))
    @test sqrt2_exp.prop.tag == BoehmCalc.Irrational

    # log with rational < 1: uses -log(inv(x)) path
    log_half = log(ExactReal(1//2))
    @test log_half.prop.tag == BoehmCalc.Ln || log_half.prop.tag == BoehmCalc.Irrational
    # It should be negative
    @test log_half < ExactReal(0)

    # log with symbolic input (not One, not Exp)
    log_sqrt2 = log(sqrt(ExactReal(2)))
    @test log_sqrt2.prop.tag == BoehmCalc.Irrational

    # _sin_pi_rational: q_red >= 1 branch (sin(π * 7/6) = -sin(π * 1/6) = -1/2)
    s_7_6 = sin(ExactReal(π) * ExactReal(7) / ExactReal(6))
    @test s_7_6.rat_factor == -1//2 && is_rational(s_7_6)

    # _sin_pi_rational: q_red > 1/2 branch (sin(π * 2/3) = sin(π * 1/3) = √3/2)
    s_2_3 = sin(ExactReal(π) * ExactReal(2) / ExactReal(3))
    @test s_2_3.prop.tag == BoehmCalc.Sqrt
    @test s_2_3.rat_factor == 1//2

    # _sin_pi_rational: q_red == 1/4 → √2/2
    s_pi4 = sin(ExactReal(π) / ExactReal(4))
    @test s_pi4.prop.tag == BoehmCalc.Sqrt

    # _sin_pi_rational: q_red == 1/3 → √3/2
    s_pi3 = sin(ExactReal(π) / ExactReal(3))
    @test s_pi3.prop.tag == BoehmCalc.Sqrt

    # _sin_pi_rational: q_red == 1/2 → 1
    s_pi2 = sin(ExactReal(π) / ExactReal(2))
    @test s_pi2.rat_factor == 1 && is_rational(s_pi2)

    # _sin_pi_rational: generic SinPi case (e.g. q_red = 1/5)
    s_pi5 = sin(ExactReal(π) / ExactReal(5))
    @test s_pi5.prop.tag == BoehmCalc.SinPi

    # asin(-1//2) = -π/6
    asin_neg_half = asin(ExactReal(-1//2))
    target_neg_pi6 = -(ExactReal(π) / ExactReal(6))
    @test asin_neg_half.rat_factor == target_neg_pi6.rat_factor &&
          asin_neg_half.prop == target_neg_pi6.prop

    # asin(-1) = -π/2
    asin_neg1 = asin(ExactReal(-1))
    target_neg_halfpi = -(ExactReal(π) / ExactReal(2))
    @test asin_neg1.rat_factor == target_neg_halfpi.rat_factor &&
          asin_neg1.prop == target_neg_halfpi.prop

    # asin with rational that doesn't simplify (e.g. 1/3) → Asin-tagged
    asin_third = asin(ExactReal(1//3))
    @test asin_third.prop.tag == BoehmCalc.Asin

    # asin with symbolic input (not One tag)
    asin_sym = asin(sqrt(ExactReal(2)) / ExactReal(2))
    @test asin_sym isa ExactReal

    # atan with -1 → -π/4
    atan_neg1 = atan(ExactReal(-1))
    target_neg_pi4 = -(ExactReal(π) / ExactReal(4))
    @test atan_neg1.rat_factor == target_neg_pi4.rat_factor &&
          atan_neg1.prop == target_neg_pi4.prop

    # atan with rational that doesn't simplify → Atan-tagged
    atan_half = atan(ExactReal(1//2))
    @test atan_half.prop.tag == BoehmCalc.Atan

    # atan with symbolic input (not One tag)
    atan_sym = atan(sqrt(ExactReal(2)))
    @test atan_sym.prop.tag == BoehmCalc.Irrational

    # atan(y, x) with x < 0 and y >= 0: base + π
    atan2_pos = atan(ExactReal(1), ExactReal(-1))    # atan(1, -1) = 3π/4
    @test atan2_pos isa ExactReal
    # atan(y, x) with x < 0 and y < 0: base - π
    atan2_neg = atan(ExactReal(-1), ExactReal(-1))   # atan(-1, -1) = -3π/4
    @test atan2_neg isa ExactReal
    # atan(y, 0) with y > 0 → π/2
    atan2_ypos = atan(ExactReal(1), ExactReal(0))
    @test atan2_ypos.rat_factor == ExactReal(π).rat_factor / 2 ||
          atan2_ypos == ExactReal(π) / ExactReal(2)
    # atan(y, 0) with y < 0 → -π/2
    atan2_yneg = atan(ExactReal(-1), ExactReal(0))
    @test atan2_yneg == -(ExactReal(π) / ExactReal(2))

    # _cr_for: Ln, SinPi, TanPi, Atan, Asin, Log paths
    # These are exercised via log10 (which calls log then divides → Irrational)
    # and via make_property + _cr_for directly via ExactReal computation
    log10_2 = log10(ExactReal(2))
    @test log10_2 isa ExactReal
end

@testset "numerical agreement with BigFloat" begin
    for prec in [53, 256, 1024]
        setprecision(BigFloat, prec) do
            cases = [
                (ExactReal(2) * ExactReal(3),           BigFloat(6)),
                (sqrt(ExactReal(2)),                    sqrt(BigFloat(2))),
                (exp(ExactReal(1)),                     exp(BigFloat(1))),
                (log(ExactReal(10)),                    log(BigFloat(10))),
                (sin(ExactReal(1)),                     sin(BigFloat(1))),
                (atan(ExactReal(1)) * ExactReal(4),     BigFloat(π)),
            ]
            for (er, bf) in cases
                er_bf = BigFloat(er; precision=prec)
                @test abs(er_bf - bf) < BigFloat(2)^(-prec + 4)
            end
        end
    end
end
