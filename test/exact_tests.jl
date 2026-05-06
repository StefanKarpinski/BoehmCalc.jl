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

    # 1/π keeps Pi tag with rat_factor 1, but cr_factor inverted
    inv_pi = ExactReal(1) / ExactReal(π)
    @test inv_pi.prop.tag == BoehmCalc.Pi
    @test inv_pi.rat_factor == 1

    inv_2 = inv(ExactReal(2))
    @test inv_2.rat_factor == 1//2 && is_rational(inv_2)

    # Division by zero
    @test_throws DivideError ExactReal(1) / ExactReal(0)
end
