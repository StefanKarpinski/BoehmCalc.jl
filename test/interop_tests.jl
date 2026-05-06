using BoehmCalc
using Test

@testset "Julia number-tower interop" begin
    @test (1 + ExactReal(π)) isa ExactReal
    @test (ExactReal(1) + 0.5) isa ExactReal
    @test (1//3 + ExactReal(2//3)) == ExactReal(1)

    # Float64 round-trips
    @test Float64(ExactReal(0.1)) == 0.1
    @test ExactReal(0.1) == 0.1
    @test ExactReal(0.1) != 1//10                # Float64 0.1 != 1/10 exactly

    # Sort
    xs = [ExactReal(π), ExactReal(2), ExactReal(0), sqrt(ExactReal(2))]
    sorted_xs = sort(xs)
    @test sorted_xs[1] == ExactReal(0)
    @test sorted_xs[end] == ExactReal(π)

    # Set/Dict
    s = Set{Real}([1, 1.0, 1//1, ExactReal(1)])
    @test length(s) == 1

    # Generic Real code
    @test sum([ExactReal(1), ExactReal(2), ExactReal(3)]) == ExactReal(6)
end
