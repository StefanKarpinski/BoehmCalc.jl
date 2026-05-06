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
end
