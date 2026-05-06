# test/compare_tests.jl
using BoehmCalc
using BoehmCalc: ExactReal, is_comparable, definitely_equal
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
end
