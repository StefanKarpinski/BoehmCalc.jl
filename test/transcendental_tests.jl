using BoehmCalc
using BoehmCalc: BigFloatCR, get_approx, IntCR, SqrtCR
using Test

@testset "transcendental" begin
    @testset "BigFloatCR via sqrt" begin
        # sqrt(4) = 2
        c = SqrtCR(IntCR(4))
        @test get_approx(c, 0) == 2
        @test get_approx(c, -10) == 2 * 1024

        # sqrt(2) ≈ 1.41421356... at precision -20: round to nearest of 1.4142136 * 2^20
        # ≈ 1482910
        a = get_approx(SqrtCR(IntCR(2)), -20)
        @test abs(a - 1482910) <= 1
    end

    @testset "MPFR-backed transcendentals" begin
        # exp(0) = 1
        @test get_approx(BoehmCalc.ExpCR(IntCR(0)), 0) == 1
        # exp(1) ≈ 2.71828... at precision -20: round(e * 2^20) ≈ 2850325
        @test abs(get_approx(BoehmCalc.ExpCR(IntCR(1)), -20) - 2850325) <= 1
        # ln(1) = 0
        @test get_approx(BoehmCalc.LnCR(IntCR(1)), 0) == 0
        # cos(0) = 1
        @test get_approx(BoehmCalc.CosCR(IntCR(0)), 0) == 1
        # atan(0) = 0
        @test get_approx(BoehmCalc.AtanCR(IntCR(0)), 0) == 0
        # asin(0) = 0
        @test get_approx(BoehmCalc.AsinCR(IntCR(0)), 0) == 0

        # PiCR ≈ 3.14159...
        @test abs(get_approx(BoehmCalc.PiCR(), -20) - 3294199) <= 1
    end
end
