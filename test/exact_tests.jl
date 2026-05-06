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
