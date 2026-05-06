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
end
