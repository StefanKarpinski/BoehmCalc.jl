# test/cr_tests.jl
using BoehmCalc
using BoehmCalc: CR, IntCR, get_approx, approximate
using Test

@testset "CR foundation" begin
    @testset "IntCR" begin
        c = IntCR(BigInt(5))
        @test get_approx(c, 0) == 5         # 5 = 5 * 2^0
        @test get_approx(c, -1) == 10       # 5 = 10 * 2^-1
        @test get_approx(c, 1) == 2         # 5 ≈ 2 * 2^1 = 4 (within ±1)
        @test get_approx(c, 4) == 0         # 5/16 rounds to 0
    end

    @testset "Caching" begin
        c = IntCR(BigInt(7))
        # First call computes
        @test get_approx(c, -8) == 7 * 256  # 7 = 1792 * 2^-8
        @test c.min_prec == -8
        # Re-asking at coarser precision: cache scales down
        @test get_approx(c, 0) == 7
        @test c.min_prec == -8              # still cached at -8
    end
end
