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
