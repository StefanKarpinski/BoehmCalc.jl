# test/compare_tests.jl
using BoehmCalc
using BoehmCalc: ExactReal, is_comparable, definitely_equal, definitely_less
using Test

@testset "comparison" begin
    @testset "==" begin
        @test ExactReal(2) == ExactReal(2)
        @test ExactReal(1//3) == ExactReal(1//3)
        @test ExactReal(π) == ExactReal(π)
        @test sqrt(ExactReal(2)) * sqrt(ExactReal(2)) == ExactReal(2)
        @test ExactReal(π) - ExactReal(π) == ExactReal(0)
        @test ExactReal(2) != ExactReal(3)
        @test ExactReal(π) != ExactReal(3)
    end

    @testset "is_comparable" begin
        @test is_comparable(ExactReal(2), ExactReal(3))
        @test is_comparable(ExactReal(0), ExactReal(0))
        @test is_comparable(ExactReal(π), ExactReal(π))
        @test is_comparable(ExactReal(π), sqrt(ExactReal(2)))
        @test is_comparable(ExactReal(π), ExactReal(1))
    end

    @testset "isless" begin
        @test ExactReal(2) < ExactReal(3)
        @test !(ExactReal(3) < ExactReal(2))
        @test sqrt(ExactReal(2)) < ExactReal(2)
        @test ExactReal(0) < ExactReal(π)
        sorted = sort([ExactReal(π), ExactReal(2), ExactReal(0)])
        @test sorted == [ExactReal(0), ExactReal(2), ExactReal(π)]
    end

    @testset "hashing via decompose" begin
        @test hash(ExactReal(1//3)) == hash(1//3)
        @test hash(ExactReal(0.5)) == hash(0.5)
        @test hash(ExactReal(2)) == hash(2)
        @test hash(ExactReal(π)) == hash(π)
        @test hash(ExactReal(ℯ)) == hash(ℯ)

        s = Set{Real}([1, ExactReal(1)])
        @test length(s) == 1

        d = Dict{Real,Int}(1//3 => 7)
        @test d[ExactReal(1//3)] == 7
    end

    @testset "conservatism" begin
        # (π + e) computed in two structurally different ways isn't symbolically
        # comparable; per spec, == returns false (conservative).
        a = ExactReal(π) + ExactReal(ℯ)
        b = ExactReal(ℯ) + ExactReal(π)
        if !is_comparable(a, b)
            @test !(a == b)
            # isless still gives a deterministic answer
            @test isless(a, b) || isless(b, a)
        end
    end

    @testset "hash invariants" begin
        pairs = [
            (ExactReal(1), ExactReal(1//1)),
            (ExactReal(0.5), ExactReal(1//2)),
            (sqrt(ExactReal(4)), ExactReal(2)),
            (ExactReal(π) - ExactReal(π), ExactReal(0)),
            (sqrt(ExactReal(2)) * sqrt(ExactReal(2)), ExactReal(2)),
        ]
        for (a, b) in pairs
            @test a == b
            @test hash(a) == hash(b)
        end
    end

    @testset "coverage" begin
        # _exact_equal Sqrt-vs-Sqrt: same squared magnitude but different sign → not equal
        s2a = sqrt(ExactReal(2))               # rat=1, prop=Sqrt(2)
        s2b = -sqrt(ExactReal(2))              # rat=-1, prop=Sqrt(2)
        # 1·√2 != -1·√2 (different sign)
        @test !(s2a == s2b)
        # 2·√(1/2) == √2: rat_factor^2 * arg: 4*(1/2) == 1*2, same sign
        # sqrt(ExactReal(1//2)) gives Sqrt(1//2) tagged with rat_factor=1
        # Multiplying by 2 gives rat_factor=2, prop=Sqrt(1//2)
        sqrt_half_scaled = ExactReal(2) * sqrt(ExactReal(1//2))
        @test sqrt_half_scaled == s2a   # 2·√(1/2) = √2

        # decompose for irrational hits the Float64 branch
        decomp = Base.decompose(ExactReal(π))
        @test isa(decomp, Tuple{BigInt, Int, BigInt})

        # hash for generic irrational (not π or ℯ) uses Float64 path
        s2_hash = hash(sqrt(ExactReal(2)))
        @test s2_hash == hash(Float64(sqrt(ExactReal(2))))

        # definitely_less returns missing when not comparable
        a_irr = ExactReal(π) + ExactReal(ℯ)    # Irrational-tagged
        b_irr = ExactReal(ℯ) + ExactReal(π)    # Irrational-tagged
        if !is_comparable(a_irr, b_irr)
            result = definitely_less(a_irr, b_irr)
            @test result === missing
        end

        # isless non-comparable path: π+ℯ vs ℯ+π
        # Force the non-comparable branch in isless (returns a Bool, not missing)
        if !is_comparable(a_irr, b_irr)
            # isless always returns a Bool (uses objectid tiebreak)
            r = isless(a_irr, b_irr)
            @test r isa Bool
        end

        # is_comparable step 4: definitely_independent but both small
        # two independently-computed tiny values — hard to trigger magnitude < 2^-5000 in tests,
        # so instead exercise it via the cr diff path that falls through to false
        # Build two ExactReals that are independent (Pi vs Ln) but comparable numerically
        pi_val = ExactReal(π)
        ln2_val = log(ExactReal(2))
        # These are definitely_independent; at least one magnitude_ge should hold
        @test is_comparable(pi_val, ln2_val)
    end
end
