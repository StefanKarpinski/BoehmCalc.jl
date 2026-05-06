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

    @testset "ShiftedCR" begin
        c = BoehmCalc.ShiftedCR(BoehmCalc.IntCR(3), 4)  # 3 * 2^4 = 48
        @test get_approx(c, 0) == 48
        @test get_approx(c, 4) == 3
        c2 = BoehmCalc.ShiftedCR(BoehmCalc.IntCR(8), -2)  # 8 / 4 = 2
        @test get_approx(c2, 0) == 2
    end

    @testset "NegCR" begin
        c = BoehmCalc.NegCR(BoehmCalc.IntCR(7))
        @test get_approx(c, 0) == -7
        @test get_approx(c, -3) == -56
    end

    @testset "AddCR" begin
        a = BoehmCalc.IntCR(5)
        b = BoehmCalc.IntCR(7)
        c = BoehmCalc.AddCR(a, b)
        @test get_approx(c, 0) == 12
        @test get_approx(c, -2) == 48      # 12 = 48 * 2^-2

        # With ShiftedCR: 5 + 8 = 13
        c2 = BoehmCalc.AddCR(BoehmCalc.IntCR(5), BoehmCalc.ShiftedCR(BoehmCalc.IntCR(2), 2))
        @test get_approx(c2, 0) == 13
    end

    @testset "MulCR" begin
        a = BoehmCalc.IntCR(3)
        b = BoehmCalc.IntCR(7)
        c = BoehmCalc.MulCR(a, b)
        @test get_approx(c, 0) == 21
        @test get_approx(c, -10) == 21 * 1024
    end

    @testset "InvCR" begin
        # 1 / 4 = 0.25. At precision -2: 0.25 * 4 = 1
        c = BoehmCalc.InvCR(BoehmCalc.IntCR(4))
        @test get_approx(c, -2) == 1
        @test get_approx(c, -10) == 256       # 0.25 * 1024
        # 1 / 3 ≈ 0.333... at precision -10 should be ≈ 341 (within ±1)
        c2 = BoehmCalc.InvCR(BoehmCalc.IntCR(3))
        @test abs(get_approx(c2, -10) - 341) <= 1
    end

    @testset "SelectCR" begin
        # If selector ≥ 0, return then-branch; else, return else-branch.
        pos = BoehmCalc.IntCR(5)
        neg = BoehmCalc.IntCR(-5)
        sel = BoehmCalc.IntCR(1)               # positive
        c = BoehmCalc.SelectCR(sel, pos, neg)
        @test get_approx(c, 0) == 5

        sel2 = BoehmCalc.IntCR(-1)             # negative
        c2 = BoehmCalc.SelectCR(sel2, pos, neg)
        @test get_approx(c2, 0) == -5
    end
end
